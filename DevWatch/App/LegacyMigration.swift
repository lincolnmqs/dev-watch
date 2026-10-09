import Foundation
import ServiceManagement

/// One-time import of data from the app's previous name (PortWatch), so renaming loses nothing:
/// preferences (aliases, settings, build history), snapshots and the launch-at-login item.
enum LegacyMigration {
    private static let legacyBundleIdentifier = "com.lincolnmarques.PortWatch"
    private static let migratedKey = "didMigrateFromPortWatch"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        defer { defaults.set(true, forKey: migratedKey) }

        if let legacy = defaults.persistentDomain(forName: legacyBundleIdentifier) {
            for (key, value) in legacy where defaults.object(forKey: key) == nil && !key.hasPrefix("NSWindow Frame") {
                defaults.set(value, forKey: key)
            }
        }

        moveApplicationSupport()

        // The login item belonged to the old bundle; register the renamed app in its place.
        if defaults.bool(forKey: "launchAtLogin"), SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }

    private static func moveApplicationSupport() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }

        let legacy = appSupport.appendingPathComponent("PortWatch", isDirectory: true)
        let current = appSupport.appendingPathComponent("DevWatch", isDirectory: true)
        guard fileManager.fileExists(atPath: legacy.path) else { return }

        if !fileManager.fileExists(atPath: current.path) {
            try? fileManager.moveItem(at: legacy, to: current)
            return
        }

        // Both exist: bring over snapshots that are not already there.
        let legacySnapshots = legacy.appendingPathComponent("Snapshots", isDirectory: true)
        let currentSnapshots = current.appendingPathComponent("Snapshots", isDirectory: true)
        try? fileManager.createDirectory(at: currentSnapshots, withIntermediateDirectories: true)
        let files = (try? fileManager.contentsOfDirectory(at: legacySnapshots, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            let destination = currentSnapshots.appendingPathComponent(file.lastPathComponent)
            if !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: file, to: destination)
            }
        }
    }
}
