import SwiftUI

@main
struct DevWatchApp: App {
    @StateObject private var menuBarController = MenuBarController()

    init() {
        LegacyMigration.runIfNeeded()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
