import Darwin
import Foundation

/// Finds running builds from two sources and merges them per project/platform:
/// - progress files written by the DevWatch Gradle init script (real task progress)
/// - running build processes (xcodebuild, flutter build, eas build --local, Gradle clients)
final class BuildScanner {
    private struct ProgressFile: Decodable {
        let id: String
        let pid: Int
        let projectName: String
        let projectDir: String
        let tasks: String
        let startedAt: Double
        let updatedAt: Double
        let completed: Int
        let total: Int
        let failed: Int
        let currentTask: String
        let state: String
    }

    private struct ProcessMetadata {
        let commandLine: [String]
        let workingDirectory: String?
        let startTime: Date?
    }

    private enum Role: Int {
        /// Low-level build process (Gradle client, xcodebuild).
        case leaf
        /// A tool that drives a leaf build (flutter build, eas build).
        case wrapper
    }

    private struct Candidate {
        var job: BuildJob
        let role: Role
        let updatedAt: Date
        let fromProgressFile: Bool
    }

    /// Finished builds stay visible this long so the result can be seen.
    static let finishedLinger: TimeInterval = 120
    private static let fileRetention: TimeInterval = 600

    private var metadataCache: [Int: ProcessMetadata] = [:]
    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()

    func scan() -> [BuildJob] {
        let processes = scanProcesses()
        let files = readProgressFiles()

        let grouped = Dictionary(grouping: processes + files, by: \.job.id)
        return grouped.values
            .compactMap(merge(_:))
            .sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Merge

    private func merge(_ candidates: [Candidate]) -> BuildJob? {
        let processes = candidates.filter { !$0.fromProgressFile }
        let earliestProcessStart = processes.map(\.job.startedAt).min()

        let file = candidates
            .filter(\.fromProgressFile)
            .filter { candidate in
                // A finished progress file from the previous run must not mask a new build that just started.
                guard candidate.job.state.isFinished, let earliestProcessStart else { return true }
                return (candidate.job.finishedAt ?? candidate.updatedAt) >= earliestProcessStart
            }
            .sorted {
                if $0.job.state.isFinished != $1.job.state.isFinished { return !$0.job.state.isFinished }
                return $0.updatedAt > $1.updatedAt
            }
            .first

        let wrapper = processes.first { $0.role == .wrapper }
        let leaf = processes.first { $0.role == .leaf }

        guard var job = (file ?? wrapper ?? leaf)?.job else { return nil }

        if file != nil, let earliestProcessStart {
            // The init script only learns the start time at the first finished task;
            // the client process knows when the build was really launched.
            job.startedAt = min(job.startedAt, earliestProcessStart)
        }
        if let wrapper, file != nil {
            job.taskSummary = wrapper.job.taskSummary
        }
        // The wrapper knows the user's intent (flutter build appbundle, eas build --profile …).
        job.distribution = wrapper?.job.distribution ?? job.distribution ?? leaf?.job.distribution
        job.stopPID = job.state.isFinished ? nil : (wrapper?.job.stopPID ?? leaf?.job.stopPID)
        return job
    }

    // MARK: - Progress files

    private func readProgressFiles() -> [Candidate] {
        let directory = GradleProgressReporter.progressDirectory
        guard let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }

        let now = Date()
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let file = try? decoder.decode(ProgressFile.self, from: data) else {
                try? fileManager.removeItem(at: url)
                return nil
            }

            let updatedAt = Date(timeIntervalSince1970: file.updatedAt / 1000)
            var state = BuildJob.State(rawValue: file.state) ?? .finished

            if state == .running, !Self.isAlive(pid: file.pid) {
                // The Gradle daemon died mid-build (killed, crashed, machine slept and it was reaped).
                state = .cancelled
                try? fileManager.removeItem(at: url)
            }

            if state.isFinished {
                let age = now.timeIntervalSince(updatedAt)
                if age > Self.fileRetention { try? fileManager.removeItem(at: url) }
                if age > Self.finishedLinger { return nil }
            }

            let root = Self.projectRoot(for: file.projectDir)
            let job = BuildJob(
                tool: .gradle,
                platform: Self.gradlePlatform(tasks: file.tasks, rootDirectory: file.projectDir),
                projectName: Self.projectName(for: root, fallback: file.projectName),
                projectDirectory: root,
                buildDirectory: file.projectDir,
                taskSummary: Self.shortGradleTasks(file.tasks),
                startedAt: Date(timeIntervalSince1970: file.startedAt / 1000),
                finishedAt: state.isFinished ? updatedAt : nil,
                completedTasks: file.completed,
                totalTasks: file.total,
                currentTask: file.currentTask.isEmpty ? nil : file.currentTask,
                state: state,
                stopPID: nil,
                artifactPath: nil,
                distribution: Self.gradleDistribution(tasks: file.tasks)
            )
            return Candidate(job: job, role: .leaf, updatedAt: updatedAt, fromProgressFile: true)
        }
    }

    // MARK: - Processes

    private func scanProcesses() -> [Candidate] {
        guard let output = Self.run("/bin/ps", ["-axww", "-o", "pid=,command="]) else { return [] }

        var candidates: [Candidate] = []
        var livePIDs = Set<Int>()

        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "), let pid = Int(trimmed[..<space]) else { continue }
            let command = String(trimmed[space...])
            guard Self.looksLikeBuild(command) else { continue }

            livePIDs.insert(pid)
            let metadata = metadata(for: pid)
            if let candidate = candidate(pid: pid, metadata: metadata) {
                candidates.append(candidate)
            }
        }

        metadataCache = metadataCache.filter { livePIDs.contains($0.key) }
        return candidates
    }

    private static func looksLikeBuild(_ command: String) -> Bool {
        if command.contains("GradleDaemon") { return false }
        return command.contains("GradleWrapperMain")
            || command.contains("org.gradle.launcher.GradleMain")
            || command.contains("gradle-cli-main")
            || command.contains("xcodebuild")
            || command.contains("flutter_tools.snapshot")
            || (command.contains("eas") && command.contains("build") && command.contains("--local"))
    }

    private func metadata(for pid: Int) -> ProcessMetadata {
        if let cached = metadataCache[pid] { return cached }
        let metadata = ProcessMetadata(
            commandLine: ProcessResolver.commandLine(for: pid) ?? [],
            workingDirectory: ProcessResolver.workingDirectory(for: pid),
            startTime: ProcessResolver.startTime(for: pid)
        )
        metadataCache[pid] = metadata
        return metadata
    }

    private func candidate(pid: Int, metadata: ProcessMetadata) -> Candidate? {
        let args = metadata.commandLine
        guard let executable = args.first, let cwd = metadata.workingDirectory else { return nil }
        let startedAt = metadata.startTime ?? Date()

        func make(tool: BuildJob.Tool, platform: BuildJob.Platform, directory: String, task: String, role: Role, artifact: String? = nil, distribution: BuildJob.Distribution? = nil) -> Candidate {
            let root = Self.projectRoot(for: directory)
            let job = BuildJob(
                tool: tool,
                platform: platform,
                projectName: Self.projectName(for: root, fallback: nil),
                projectDirectory: root,
                buildDirectory: directory,
                taskSummary: task,
                startedAt: startedAt,
                finishedAt: nil,
                completedTasks: nil,
                totalTasks: nil,
                currentTask: nil,
                state: .running,
                stopPID: pid,
                artifactPath: artifact,
                distribution: distribution
            )
            return Candidate(job: job, role: role, updatedAt: startedAt, fromProgressFile: false)
        }

        // ./gradlew runs GradleWrapperMain; a Gradle 9 distribution runs `-jar gradle-cli-main-<version>.jar`.
        if let mainIndex = args.firstIndex(where: {
            $0.hasSuffix("GradleWrapperMain") || $0.hasSuffix("launcher.GradleMain")
                || (($0 as NSString).lastPathComponent.contains("gradle-cli-main") && $0.hasSuffix(".jar"))
        }) {
            let gradleArgs = Array(args[(mainIndex + 1)...])
            let directory = Self.value(after: ["-p", "--project-dir"], in: gradleArgs).map { Self.resolve($0, relativeTo: cwd) } ?? cwd
            let tasks = Self.gradleTasks(from: gradleArgs)
            let rootDirectory = Self.gradleRootDirectory(startingAt: directory)
            return make(
                tool: .gradle,
                platform: Self.gradlePlatform(tasks: tasks, rootDirectory: rootDirectory),
                directory: rootDirectory,
                task: Self.shortGradleTasks(tasks),
                role: .leaf,
                distribution: Self.gradleDistribution(tasks: tasks)
            )
        }

        if (executable as NSString).lastPathComponent == "xcodebuild" {
            let informational = ["-list", "-version", "-showBuildSettings", "-showsdks", "-showdestinations", "-resolvePackageDependencies", "-checkFirstLaunchStatus", "-runFirstLaunch"]
            guard !args.contains(where: informational.contains) else { return nil }

            if args.contains("-exportArchive") {
                let archivePath = Self.value(after: ["-archivePath"], in: args).map { Self.resolve($0, relativeTo: cwd) }
                let exportPath = Self.value(after: ["-exportPath"], in: args).map { Self.resolve($0, relativeTo: cwd) }
                let method = Self.value(after: ["-exportOptionsPlist"], in: args)
                    .flatMap { Self.exportMethod(plistPath: Self.resolve($0, relativeTo: cwd)) }
                let archiveName = archivePath.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
                return make(
                    tool: .xcodebuild,
                    platform: .ios,
                    directory: archivePath.map { ($0 as NSString).deletingLastPathComponent } ?? cwd,
                    task: ["export", archiveName].compactMap { $0 }.joined(separator: " "),
                    role: .leaf,
                    artifact: exportPath,
                    distribution: method.flatMap(Self.appleDistribution(method:))
                )
            }

            let actions = ["archive", "build", "test", "build-for-testing", "analyze", "clean", "install"]
            let action = args.dropFirst().first(where: actions.contains) ?? "build"
            let scheme = Self.value(after: ["-scheme"], in: args)
            let destination = (Self.value(after: ["-destination"], in: args) ?? "") + (Self.value(after: ["-sdk"], in: args) ?? "")
            let platform: BuildJob.Platform = destination.lowercased().contains("macos") ? .desktop : .ios
            let directory = Self.value(after: ["-workspace", "-project"], in: args)
                .map { (Self.resolve($0, relativeTo: cwd) as NSString).deletingLastPathComponent } ?? cwd
            let archive = Self.value(after: ["-archivePath"], in: args).map { path -> String in
                let resolved = Self.resolve(path, relativeTo: cwd)
                return resolved.hasSuffix(".xcarchive") ? resolved : resolved + ".xcarchive"
            }
            return make(
                tool: .xcodebuild,
                platform: platform,
                directory: directory,
                task: [action, scheme].compactMap { $0 }.joined(separator: " "),
                role: .leaf,
                artifact: archive,
                distribution: ["build", "install"].contains(action) && platform == .ios ? .development : nil
            )
        }

        if args.contains(where: { $0.hasSuffix("flutter_tools.snapshot") }), let buildIndex = args.firstIndex(of: "build") {
            let target = args.dropFirst(buildIndex + 1).first(where: { !$0.hasPrefix("-") }) ?? ""
            let platform: BuildJob.Platform
            switch target {
            case "apk", "appbundle", "aar": platform = .android
            case "ios", "ipa", "ios-framework": platform = .ios
            case "web": platform = .web
            case "macos", "linux", "windows": platform = .desktop
            default: platform = .other
            }
            let distribution: BuildJob.Distribution?
            switch target {
            case "apk": distribution = .apk
            case "appbundle": distribution = .playStore
            case "ipa":
                let method = Self.value(after: ["--export-method"], in: args)
                    ?? Self.value(after: ["--export-options-plist"], in: args).flatMap { Self.exportMethod(plistPath: Self.resolve($0, relativeTo: cwd)) }
                distribution = method.flatMap(Self.appleDistribution(method:)) ?? .appStore
            default: distribution = nil
            }
            return make(tool: .flutter, platform: platform, directory: cwd, task: "build \(target)", role: .wrapper, distribution: distribution)
        }

        if args.contains(where: { ($0 as NSString).lastPathComponent == "eas" }), args.contains("build"), args.contains("--local") {
            let target = Self.value(after: ["--platform", "-p"], in: args) ?? ""
            let platform: BuildJob.Platform = target == "android" ? .android : (target == "ios" ? .ios : .other)
            let profile = Self.value(after: ["--profile", "-e"], in: args) ?? "production"
            return make(
                tool: .eas,
                platform: platform,
                directory: cwd,
                task: "eas build \(target) \(profile)",
                role: .wrapper,
                distribution: Self.easDistribution(profile: profile, platform: platform, directory: cwd)
            )
        }

        return nil
    }

    // MARK: - Artifacts

    /// Locates the file a successful build produced (APK, AAB, IPA, xcarchive), if any.
    static func findArtifact(for job: BuildJob) -> String? {
        let fileManager = FileManager.default
        let notBefore = job.startedAt.addingTimeInterval(-5)

        if let path = job.artifactPath {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
            // `xcodebuild -exportArchive` gets an output folder; point at the IPA inside it.
            if isDirectory.boolValue, !path.hasSuffix(".xcarchive"),
               let ipa = (try? fileManager.contentsOfDirectory(atPath: path))?.first(where: { $0.hasSuffix(".ipa") }) {
                return (path as NSString).appendingPathComponent(ipa)
            }
            return path
        }

        var outputDirectories: [URL] = []
        var extensions: Set<String> = []

        switch job.platform {
        case .android:
            extensions = ["apk", "aab"]
            let roots = Set([job.buildDirectory, job.projectDirectory, job.projectDirectory + "/android"])
            for root in roots {
                let rootURL = URL(fileURLWithPath: root)
                outputDirectories.append(rootURL.appendingPathComponent("build/app/outputs"))
                let children = (try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
                for child in children where child.lastPathComponent != "node_modules" {
                    outputDirectories.append(child.appendingPathComponent("build/outputs"))
                }
            }
        case .ios:
            extensions = ["ipa", "xcarchive"]
            outputDirectories.append(URL(fileURLWithPath: job.projectDirectory).appendingPathComponent("build/ios"))
        default:
            return nil
        }

        var newest: (url: URL, date: Date)?
        for directory in outputDirectories where fileManager.fileExists(atPath: directory.path) {
            guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for case let url as URL in enumerator {
                guard extensions.contains(url.pathExtension) else { continue }
                if url.pathExtension == "xcarchive" { enumerator.skipDescendants() }
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      date >= notBefore else { continue }
                if newest == nil || date > newest!.date { newest = (url, date) }
            }
        }
        return newest?.url.path
    }

    // MARK: - Helpers

    static func isAlive(pid: Int) -> Bool {
        kill(pid_t(pid), 0) == 0 || errno == EPERM
    }

    /// Native folders of cross-platform apps (RN/Expo/Flutter) belong to the app at their parent.
    static func projectRoot(for directory: String) -> String {
        let url = URL(fileURLWithPath: directory).standardizedFileURL
        let nativeFolders: Set<String> = ["android", "ios", "macos"]
        guard nativeFolders.contains(url.lastPathComponent.lowercased()) else { return url.path }

        let parent = url.deletingLastPathComponent()
        let markers = ["package.json", "pubspec.yaml", "app.json"]
        let isAppRoot = markers.contains { FileManager.default.fileExists(atPath: parent.appendingPathComponent($0).path) }
        return isAppRoot ? parent.path : url.path
    }

    private static func projectName(for root: String, fallback: String?) -> String {
        let pubspec = URL(fileURLWithPath: root).appendingPathComponent("pubspec.yaml")
        if let content = try? String(contentsOf: pubspec, encoding: .utf8),
           let line = content.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("name:") }) {
            let name = line.dropFirst("name:".count).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }

        let package = URL(fileURLWithPath: root).appendingPathComponent("package.json")
        if let data = try? Data(contentsOf: package),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = json["name"] as? String, !name.isEmpty {
            return name
        }

        if let fallback, !fallback.isEmpty { return fallback }
        return URL(fileURLWithPath: root).lastPathComponent
    }

    private static func gradleRootDirectory(startingAt directory: String) -> String {
        var current = URL(fileURLWithPath: directory).standardizedFileURL
        for _ in 0..<6 {
            for name in ["settings.gradle", "settings.gradle.kts"] where FileManager.default.fileExists(atPath: current.appendingPathComponent(name).path) {
                return current.path
            }
            let parent = current.deletingLastPathComponent()
            if parent == current { break }
            current = parent
        }
        return directory
    }

    private static func gradlePlatform(tasks: String, rootDirectory: String) -> BuildJob.Platform {
        let lowered = tasks.lowercased()
        if ["assemble", "bundle", "install", "lint"].contains(where: lowered.contains) { return .android }
        let manifest = URL(fileURLWithPath: rootDirectory).appendingPathComponent("app/src/main/AndroidManifest.xml")
        return FileManager.default.fileExists(atPath: manifest.path) ? .android : .other
    }

    /// `bundleRelease` builds an AAB for Google Play, `assemble*` an APK, `install*` deploys to a device.
    private static func gradleDistribution(tasks: String) -> BuildJob.Distribution? {
        let names = tasks.split(separator: " ").map { ($0.split(separator: ":").last.map(String.init) ?? String($0)).lowercased() }
        if names.contains(where: { $0.hasPrefix("bundle") }) { return .playStore }
        if names.contains(where: { $0.hasPrefix("install") }) { return .development }
        if names.contains(where: { $0.hasPrefix("assemble") }) { return .apk }
        return nil
    }

    private static func appleDistribution(method: String) -> BuildJob.Distribution? {
        switch method.lowercased() {
        case "app-store", "app-store-connect", "validation": return .appStore
        case "ad-hoc", "release-testing": return .adHoc
        case "enterprise": return .enterprise
        case "development", "debugging": return .development
        default: return nil
        }
    }

    private static func exportMethod(plistPath: String) -> String? {
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["method"] as? String
    }

    /// Reads the build profile from eas.json, following `extends`.
    private static func easDistribution(profile: String, platform: BuildJob.Platform, directory: String) -> BuildJob.Distribution? {
        let url = URL(fileURLWithPath: directory).appendingPathComponent("eas.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = json["build"] as? [String: [String: Any]] else { return nil }

        // Parent first so the requested profile overrides what it extends.
        var chain: [[String: Any]] = []
        var name: String? = profile
        while let current = name, let entry = profiles[current], chain.count < 10 {
            chain.insert(entry, at: 0)
            name = entry["extends"] as? String
        }
        guard !chain.isEmpty else { return nil }

        var settings: [String: Any] = [:]
        for entry in chain {
            for (key, value) in entry {
                if let nested = value as? [String: Any], let existing = settings[key] as? [String: Any] {
                    settings[key] = existing.merging(nested) { $1 }
                } else {
                    settings[key] = value
                }
            }
        }

        if settings["developmentClient"] as? Bool == true { return .development }
        let isInternal = (settings["distribution"] as? String) == "internal"

        switch platform {
        case .android:
            let android = settings["android"] as? [String: Any] ?? [:]
            if let gradleCommand = android["gradleCommand"] as? String {
                return gradleDistribution(tasks: gradleCommand) ?? .apk
            }
            return (android["buildType"] as? String) == "apk" ? .apk : .playStore
        case .ios:
            let ios = settings["ios"] as? [String: Any] ?? [:]
            if ios["simulator"] as? Bool == true { return .development }
            if ios["enterpriseProvisioning"] as? String == "universal" { return .enterprise }
            return isInternal ? .adHoc : .appStore
        default:
            return nil
        }
    }

    private static func gradleTasks(from args: [String]) -> String {
        let optionsWithValue: Set<String> = ["-p", "--project-dir", "-x", "--exclude-task", "-c", "--settings-file", "-I", "--init-script", "-g", "--gradle-user-home", "--console", "--max-workers", "--priority", "--warning-mode"]
        var tasks: [String] = []
        var skipNext = false
        for arg in args {
            if skipNext { skipNext = false; continue }
            if optionsWithValue.contains(arg) { skipNext = true; continue }
            if arg.hasPrefix("-") { continue }
            tasks.append(arg)
        }
        return tasks.joined(separator: " ")
    }

    /// `:app:assembleRelease` → `assembleRelease`; keeps the list readable in a narrow row.
    private static func shortGradleTasks(_ tasks: String) -> String {
        tasks.split(separator: " ")
            .map { $0.split(separator: ":").last.map(String.init) ?? String($0) }
            .joined(separator: " ")
    }

    private static func value(after flags: [String], in args: [String]) -> String? {
        if let index = args.firstIndex(where: flags.contains), index + 1 < args.count {
            return args[index + 1]
        }
        for flag in flags where flag.hasPrefix("--") {
            if let arg = args.first(where: { $0.hasPrefix(flag + "=") }) {
                return String(arg.dropFirst(flag.count + 1))
            }
        }
        return nil
    }

    private static func resolve(_ path: String, relativeTo base: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded).standardizedFileURL.path }
        return URL(fileURLWithPath: base).appendingPathComponent(expanded).standardizedFileURL.path
    }

    private static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
