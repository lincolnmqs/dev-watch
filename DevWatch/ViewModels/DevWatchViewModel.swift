import AppKit
import Combine
import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class DevWatchViewModel: ObservableObject {
    private struct ProjectGroupKey: Hashable {
        let name: String
        let directory: String?
    }

    struct ProjectSection: Identifiable {
        let name: String
        let directory: String?
        let services: [PortService]

        var id: String {
            [name, directory ?? "unknown"].joined(separator: "::")
        }

        var subtitle: String {
            return "\(services.count) service\(services.count == 1 ? "" : "s")"
        }
    }

    @Published private(set) var services: [PortService] = []
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var newServiceIDs: Set<String> = []
    @Published private(set) var recentlyStopped: PortService?
    @Published private(set) var recentSnapshots: [SessionSnapshot] = []
    @Published private(set) var builds: [BuildJob] = []

    private let scanner: PortScanner
    private let aliasStore: AliasStore
    private let snapshotStore: SnapshotStore
    private let buildScanner = BuildScanner()
    private let buildHistory = BuildHistoryStore()
    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var buildTimer: Timer?
    private var isScanningBuilds = false
    private var hasScannedBuilds = false
    private var stoppedBuildIDs: Set<String> = []
    private var powerStateObserver: NSObjectProtocol?
    private var infoPanel: NSPanel?
    private var isFirstLoad = true
    private var isPanelVisible = false

    private var refreshInterval: TimeInterval {
        // Enable user control, but keep safe minimum/maximum bounds for battery/idle usage.
        let configured = min(max(settings.scanInterval, 5), 120)

        if isPanelVisible {
            return min(configured, 30)
        }

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return max(configured, 60)
        }

        return max(configured, 30)
    }

    var runningBuilds: [BuildJob] {
        builds.filter { $0.state == .running }
    }

    /// Progress shown next to the menu bar icon: the least advanced running build, so it never jumps ahead.
    var menuBarBuildEstimate: BuildEstimate? {
        let estimates: [BuildEstimate] = runningBuilds.map { estimate(for: $0) }
        let withProgress = estimates.filter { $0.progress != nil }
        return withProgress.min { ($0.progress ?? 0) < ($1.progress ?? 0) } ?? estimates.first
    }

    var visibleServices: [PortService] {
        services.filter { ProjectDetector.isUserProjectDirectory($0.projectDirectory) }
    }

    var filteredServices: [PortService] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return visibleServices }

        return visibleServices.filter { service in
            let haystacks = [
                service.primaryName,
                service.processName,
                service.projectName ?? "",
                service.projectDirectory ?? "",
                service.commandSummary ?? "",
                String(service.port)
            ]

            return haystacks.contains { $0.lowercased().contains(query) }
        }
    }

    var projectSections: [ProjectSection] {
        let grouped = Dictionary(grouping: filteredServices) { service in
            ProjectGroupKey(
                name: service.projectDisplayName,
                directory: service.projectDirectory
            )
        }

        return grouped
            .map { key, services in
                ProjectSection(
                    name: key.name,
                    directory: key.directory,
                    services: services.sorted {
                        $0.port < $1.port
                    }
                )
            }
            .sorted { lhs, rhs in
                if lhs.name == "Ungrouped" { return false }
                if rhs.name == "Ungrouped" { return true }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    init(
        scanner: PortScanner,
        aliasStore: AliasStore = .shared,
        snapshotStore: SnapshotStore = SnapshotStore()
    ) {
        self.scanner = scanner
        self.aliasStore = aliasStore
        self.snapshotStore = snapshotStore
        self.recentSnapshots = snapshotStore.loadRecent()

        settings.$scanInterval
            .sink { [weak self] _ in
                self?.startAutoRefresh()
            }
            .store(in: &cancellables)

        observePowerState()
        requestNotificationPermission()
        startAutoRefresh()
        refresh()
        refreshBuilds()
    }

    deinit {
        refreshTimer?.invalidate()
        buildTimer?.invalidate()
        if let powerStateObserver {
            NotificationCenter.default.removeObserver(powerStateObserver)
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil

        Task.detached(priority: .userInitiated) { [scanner] in
            do {
                let newServices = try scanner.scanOpenPorts()
                await MainActor.run {
                    self.handleRefreshResult(newServices: newServices)
                    self.isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    self.services = []
                    self.errorMessage = error.localizedDescription
                    self.isRefreshing = false
                }
            }
        }
    }

    func setPanelVisible(_ visible: Bool) {
        guard isPanelVisible != visible else { return }
        isPanelVisible = visible
        startAutoRefresh()

        if visible {
            refresh()
            refreshBuilds()
        }
    }

    // MARK: - Builds

    func estimate(for job: BuildJob, now: Date = Date()) -> BuildEstimate {
        job.estimate(typicalDuration: buildHistory.typicalDuration(for: job), now: now)
    }

    func refreshBuilds() {
        guard !isScanningBuilds else { return }
        isScanningBuilds = true

        Task.detached(priority: .utility) { [buildScanner] in
            let scanned = buildScanner.scan()
            await MainActor.run {
                self.applyBuilds(scanned)
                self.isScanningBuilds = false
                self.scheduleBuildScan()
            }
        }
    }

    func stopBuild(_ job: BuildJob) {
        guard let pid = job.stopPID else { return }
        // SIGTERM rather than SIGINT: shells start background jobs with SIGINT ignored. Gradle's client
        // still cancels the daemon build from its shutdown hook; xcodebuild and Flutter exit cleanly.
        if kill(pid_t(pid), SIGTERM) == 0 {
            stoppedBuildIDs.insert(job.id)
            refreshBuilds()
        } else {
            errorMessage = "Unable to stop build (PID \(pid))."
        }
    }

    func revealArtifact(_ job: BuildJob) {
        guard let path = job.artifactPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func copyArtifactPath(_ job: BuildJob) {
        guard let path = job.artifactPath else { return }
        copyToPasteboard(path)
    }

    func openBuildFolder(_ job: BuildJob) {
        NSWorkspace.shared.open(URL(fileURLWithPath: job.projectDirectory))
    }

    func dismissBuild(_ job: BuildJob) {
        builds.removeAll { $0.id == job.id && $0.state.isFinished }
    }

    private func applyBuilds(_ scanned: [BuildJob]) {
        let now = Date()
        let previousByID = Dictionary(builds.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let scannedIDs = Set(scanned.map(\.id))
        var next: [BuildJob] = []

        for var job in scanned {
            if job.state.isFinished, let previous = previousByID[job.id], previous.state == .running {
                // Once the Gradle client exits, the scan only knows the first-task time; keep the real start.
                job.startedAt = min(job.startedAt, previous.startedAt)
            }

            if job.state == .running {
                next.append(job)
            } else if let previous = previousByID[job.id], previous.state.isFinished {
                next.append(previous)
            } else if hasScannedBuilds {
                next.append(completeBuild(job))
            } else {
                // Finished before DevWatch launched: show it, but don't notify or skew history.
                next.append(job)
            }
        }

        for previous in builds where !scannedIDs.contains(previous.id) {
            if previous.state == .running {
                var finished = previous
                finished.state = .finished
                finished.finishedAt = now
                next.append(completeBuild(finished))
            } else if let finishedAt = previous.finishedAt, now.timeIntervalSince(finishedAt) < BuildScanner.finishedLinger {
                next.append(previous)
            }
        }

        builds = next.sorted {
            if ($0.state == .running) != ($1.state == .running) { return $0.state == .running }
            return $0.startedAt > $1.startedAt
        }
        hasScannedBuilds = true
    }

    private func completeBuild(_ job: BuildJob) -> BuildJob {
        var finished = job
        finished.stopPID = nil
        if finished.finishedAt == nil { finished.finishedAt = Date() }
        if stoppedBuildIDs.remove(job.id) != nil, finished.state == .finished || finished.state == .failed {
            finished.state = .cancelled
        }

        if finished.state == .succeeded || finished.state == .finished {
            finished.artifactPath = BuildScanner.findArtifact(for: finished)
            if finished.distribution == nil, let artifact = finished.artifactPath {
                switch (artifact as NSString).pathExtension {
                case "apk": finished.distribution = .apk
                case "aab": finished.distribution = .playStore
                default: break
                }
            }
            buildHistory.record(finished)
        }

        if settings.notifyBuildFinished {
            notifyBuildFinished(finished)
        }
        return finished
    }

    private func notifyBuildFinished(_ job: BuildJob) {
        let duration = DurationFormatter.short(job.elapsed())
        let kind = [job.platform.rawValue, job.distribution?.rawValue].compactMap { $0 }.joined(separator: " · ")
        let title: String
        switch job.state {
        case .succeeded, .finished: title = "\(kind) build finished"
        case .failed: title = "\(kind) build failed"
        case .cancelled: title = "\(kind) build cancelled"
        case .running: return
        }

        var body = "\(job.projectName) · \(job.displayTask) · \(duration)"
        if let artifact = job.artifactPath {
            body += "\n\((artifact as NSString).lastPathComponent) is ready"
        }
        sendNotification(title: title, body: body, interruptionLevel: .active)
    }

    private func scheduleBuildScan() {
        let interval: TimeInterval
        if !runningBuilds.isEmpty {
            interval = isPanelVisible ? 1 : 2
        } else if ProcessInfo.processInfo.isLowPowerModeEnabled {
            interval = 15
        } else {
            interval = isPanelVisible ? 3 : 6
        }

        buildTimer?.invalidate()
        buildTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refreshBuilds()
            }
        }
    }

    private func handleRefreshResult(newServices: [PortService]) {
        let previousIDs = Set(services.map(\.id))
        let currentIDs = Set(newServices.map(\.id))

        let appearedIDs = currentIDs.subtracting(previousIDs)
        let disappearedIDs = previousIDs.subtracting(currentIDs)

        if !isFirstLoad {
            let previousByPort = Dictionary(services.map { ($0.port, $0) }, uniquingKeysWith: { first, _ in first })

            for id in appearedIDs {
                if let s = newServices.first(where: { $0.id == id }) {
                    sendNotification(
                        title: "New service on :\(s.port)",
                        body: "\(s.primaryName) is now listening"
                    )
                }
            }

            for service in newServices {
                guard let previous = previousByPort[service.port], previous.id != service.id else { continue }
                sendNotification(
                    title: "Port conflict on :\(service.port)",
                    body: "\(service.primaryName) replaced \(previous.primaryName)"
                )
            }

            if let stopped = services.first(where: { disappearedIDs.contains($0.id) }) {
                sendNotification(
                    title: "Service stopped",
                    body: "\(stopped.primaryName) on :\(stopped.port) is no longer listening"
                )
                recentlyStopped = stopped
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if self.recentlyStopped?.id == stopped.id {
                        self.recentlyStopped = nil
                    }
                }
            }
        }

        services = newServices
        lastUpdated = Date()

        if !appearedIDs.isEmpty {
            newServiceIDs = appearedIDs
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.newServiceIDs = []
            }
        }

        isFirstLoad = false
    }

    func openInBrowser(_ service: PortService) {
        guard service.canOpenInBrowser,
              let url = URL(string: service.localhostURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    func killProcess(_ service: PortService) {
        sendKill(signal: "-TERM", service: service)
    }

    func forceKillProcess(_ service: PortService) {
        sendKill(signal: "-KILL", service: service)
    }

    func copyURL(_ service: PortService) {
        copyToPasteboard(service.localhostURLString)
    }

    func copyPort(_ service: PortService) {
        copyToPasteboard(String(service.port))
    }

    func revealProcess(_ service: PortService) {
        guard let executablePath = service.executablePath else {
            errorMessage = "Unable to reveal process binary for PID \(service.pid)."
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: executablePath)])
    }

    func showCommand(_ service: PortService) {
        guard let command = service.commandSummary else {
            errorMessage = "DevWatch could not read the launch command for PID \(service.pid)."
            return
        }

        let alert = NSAlert()
        alert.messageText = service.primaryName
        alert.informativeText = command
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "Close")

        if alert.runModal() == .alertFirstButtonReturn {
            copyToPasteboard(command)
        }
    }

    func showInfo(_ service: PortService) {
        let lines = [
            "Port: \(service.port)",
            "PID: \(service.pid)",
            "Process: \(service.processName)",
            "Runtime: \(service.runtimeBadgeText ?? "Unknown")",
            "Project: \(service.projectName ?? "-")",
            "Directory: \(service.projectDirectory ?? "-")",
            "Command: \(service.commandSummary ?? "-")"
        ]

        showInfoPanel(
            title: service.primaryName,
            body: lines.joined(separator: "\n"),
            command: service.commandSummary
        )
    }

    func renameAlias(_ service: PortService) {
        let alert = NSAlert()
        alert.messageText = "Alias for :\(service.port)"
        alert.informativeText = "Use a short label like Frontend, API, or Database."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: service.alias ?? service.detectedName ?? "")
        field.placeholderString = service.primaryName
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            aliasStore.set(field.stringValue, for: service.port)
            refresh()
        case .alertSecondButtonReturn:
            aliasStore.remove(for: service.port)
            refresh()
        default:
            break
        }
    }

    func saveSnapshot() {
        do {
            _ = try snapshotStore.saveSnapshot(services: visibleServices)
            recentSnapshots = snapshotStore.loadRecent()
            sendNotification(
                title: "Session snapshot saved",
                body: "\(visibleServices.count) service\(visibleServices.count == 1 ? "" : "s") captured"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendKill(signal: String, service: PortService) {
        let process = Process()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = [signal, String(service.pid)]
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                refresh()
                return
            }

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            errorMessage = message?.isEmpty == false ? message : "Failed to terminate PID \(service.pid)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func observePowerState() {
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("NSProcessInfoPowerStateDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.startAutoRefresh()
            }
        }
    }

    private func showInfoPanel(title: String, body: String, command: String?) {
        infoPanel?.close()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 292),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = title
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.level = .floating

        let rootView = ServiceInfoView(
            title: title,
            bodyText: body,
            hasCommand: command != nil,
            onCopyCommand: { [weak self] in
                guard let self, let command else { return }
                self.copyToPasteboard(command)
            },
            onClose: { [weak panel] in
                panel?.close()
            }
        )

        let hostingController = NSHostingController(rootView: rootView)
        panel.contentViewController = hostingController
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        infoPanel = panel
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    private func sendNotification(title: String, body: String, interruptionLevel: UNNotificationInterruptionLevel = .passive) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.interruptionLevel = interruptionLevel
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

private struct ServiceInfoView: View {
    let title: String
    let bodyText: String
    let hasCommand: Bool
    let onCopyCommand: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)

            ScrollView {
                Text(bodyText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }

            HStack {
                Spacer()

                if hasCommand {
                    Button("Copy Command", action: onCopyCommand)
                }

                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 292)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
