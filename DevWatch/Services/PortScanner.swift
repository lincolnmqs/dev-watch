import Darwin
import Foundation

final class PortScanner {
    private struct CachedProcessMetadata {
        let startTime: Date?
        let executablePath: String?
        let workingDirectory: String?
        let commandLine: [String]
        let projectDirectory: String?
        let projectName: String?
        let detectedName: String?
    }

    private let aliasStore: AliasStore
    private var processCache: [Int: CachedProcessMetadata] = [:]
    private var projectContextCache: [String: ServiceIdentifier.ProjectContext?] = [:]

    init(aliasStore: AliasStore = .shared) {
        self.aliasStore = aliasStore
    }

    func scanOpenPorts() throws -> [PortService] {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // Query only TCP listening sockets. This reduces process scanning cost significantly.
        process.arguments = ["-iTCP", "-sTCP:LISTEN", "-P", "-n"]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "Unknown lsof error"
            throw PortScannerError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let output = String(data: outputData, encoding: .utf8) ?? ""
        return parse(output: output)
    }

    private func parse(output: String) -> [PortService] {
        let lines = output.split(whereSeparator: \.isNewline)
        guard lines.count > 1 else { return [] }

        let parsed = lines.dropFirst().compactMap(parseLine(_:))
        let deduplicated = Dictionary(grouping: parsed, by: \.id).compactMap { $0.value.first }
        let activePIDs = Set(deduplicated.map(\.pid))
        processCache = processCache.filter { activePIDs.contains($0.key) }
        let activeProjects = Set(deduplicated.compactMap(\.projectDirectory))
        projectContextCache = projectContextCache.filter { activeProjects.contains($0.key) }

        return deduplicated.sorted {
            if $0.port == $1.port {
                return $0.primaryName.localizedCaseInsensitiveCompare($1.primaryName) == .orderedAscending
            }
            return $0.port < $1.port
        }
    }

    private func parseLine(_ line: Substring) -> PortService? {
        let columns = line.split(separator: " ", omittingEmptySubsequences: true)
        guard columns.count >= 8 else { return nil }

        let processName = String(columns[0])
        guard let pid = Int(columns[1]) else { return nil }

        guard let protocolIndex = columns.firstIndex(where: { $0 == "TCP" || $0 == "UDP" }) else {
            return nil
        }

        let rawAddress = columns[protocolIndex...].joined(separator: " ")
        let protocolName = String(columns[protocolIndex])
        let endpoint = columns[(protocolIndex + 1)...].joined(separator: " ")
        let normalizedEndpoint = endpoint.replacingOccurrences(of: " (LISTEN)", with: "")

        guard !normalizedEndpoint.isEmpty else { return nil }

        let localEndpoint = normalizedEndpoint.components(separatedBy: "->").first ?? normalizedEndpoint
        let trimmedEndpoint = localEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let colonIndex = trimmedEndpoint.lastIndex(of: ":") else { return nil }

        let host = String(trimmedEndpoint[..<colonIndex])
        let portSection = trimmedEndpoint[trimmedEndpoint.index(after: colonIndex)...]
        let digits = portSection.prefix { $0.isNumber }

        guard let port = Int(digits), port > 0 else { return nil }

        let isListeningTCP = rawAddress.contains("(LISTEN)")
        let isLocalHost = isUsefulLocalHost(host)

        guard protocolName == "TCP", isListeningTCP, isLocalHost else { return nil }

        let metadata = metadata(for: pid, processName: processName, port: port)

        return PortService(
            processName: processName,
            pid: pid,
            protocolName: protocolName,
            port: port,
            rawAddress: rawAddress,
            host: host,
            startTime: metadata.startTime,
            executablePath: metadata.executablePath,
            workingDirectory: metadata.workingDirectory,
            commandLine: metadata.commandLine,
            projectName: metadata.projectName,
            projectDirectory: metadata.projectDirectory,
            detectedName: metadata.detectedName,
            alias: aliasStore.alias(for: port),
            dockerContainer: nil
        )
    }

    private func isUsefulLocalHost(_ host: String) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        return normalizedHost == "*" || normalizedHost == "127.0.0.1" || normalizedHost == "::1" || normalizedHost == "localhost"
    }

    private func metadata(for pid: Int, processName: String, port: Int) -> CachedProcessMetadata {
        if let cached = processCache[pid] {
            return cached
        }

        let startTime = ProcessResolver.startTime(for: pid)
        let executablePath = ProcessResolver.executablePath(for: pid)
        let workingDirectory = ProcessResolver.workingDirectory(for: pid)
        let commandLine = ProcessResolver.commandLine(for: pid) ?? []
        let projectDirectory = ProjectDetector.projectDirectory(from: workingDirectory, commandLine: commandLine)
        let projectName = ProjectDetector.projectName(from: projectDirectory)
        let projectContext = projectDirectory.flatMap(projectContext(for:))
        let detected = ServiceIdentifier.identify(
            processName: processName,
            executablePath: executablePath,
            commandLine: commandLine,
            port: port,
            projectContext: projectContext
        )

        let metadata = CachedProcessMetadata(
            startTime: startTime,
            executablePath: executablePath,
            workingDirectory: workingDirectory,
            commandLine: commandLine,
            projectDirectory: projectDirectory,
            projectName: projectName,
            detectedName: detected?.name
        )

        processCache[pid] = metadata
        return metadata
    }

    private func projectContext(for directory: String) -> ServiceIdentifier.ProjectContext? {
        if let cached = projectContextCache[directory] {
            return cached
        }

        let file = URL(fileURLWithPath: directory).appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            projectContextCache[directory] = nil
            return nil
        }

        let scripts = json["scripts"] as? [String: String] ?? [:]
        let dependencies = Set((json["dependencies"] as? [String: Any] ?? [:]).keys)
        let devDependencies = Set((json["devDependencies"] as? [String: Any] ?? [:]).keys)
        let context = ServiceIdentifier.ProjectContext(
            packageName: json["name"] as? String,
            scripts: scripts,
            dependencyNames: dependencies.union(devDependencies)
        )

        projectContextCache[directory] = context
        return context
    }
}

enum PortScannerError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message.isEmpty ? "Failed to scan open ports." : message
        }
    }
}
