import Foundation

final class SnapshotStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func saveSnapshot(services: [PortService]) throws -> SessionSnapshot {
        let snapshot = SessionSnapshot(
            id: UUID(),
            createdAt: Date(),
            hostname: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            services: services.map {
                SessionSnapshot.ServiceRecord(
                    id: $0.id,
                    port: $0.port,
                    host: $0.host,
                    processName: $0.processName,
                    primaryName: $0.primaryName,
                    pid: $0.pid,
                    projectName: $0.projectName,
                    projectDirectory: $0.projectDirectory,
                    commandSummary: $0.commandSummary,
                    runtime: $0.runtimeBadgeText
                )
            }
        )

        let url = try snapshotsDirectory().appendingPathComponent("\(snapshot.id.uuidString).json")
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
        pruneOldSnapshots()
        return snapshot
    }

    func loadRecent(limit: Int = 5) -> [SessionSnapshot] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: try snapshotsDirectory(),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let snapshots = urls.compactMap { url -> SessionSnapshot? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(SessionSnapshot.self, from: data)
        }

        return snapshots
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    private func pruneOldSnapshots(maxCount: Int = 20) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: try snapshotsDirectory(),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let sorted = urls.sorted { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate > rightDate
        }

        for url in sorted.dropFirst(maxCount) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func snapshotsDirectory() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport
            .appendingPathComponent("DevWatch", isDirectory: true)
            .appendingPathComponent("Snapshots", isDirectory: true)

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory
    }
}
