import Combine
import Foundation
import ServiceManagement

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let scanIntervalKey = "scanInterval"
    private var cancellables = Set<AnyCancellable>()

    @Published var launchAtLogin: Bool = UserDefaults.standard.bool(forKey: "launchAtLogin") {
        didSet {
            guard oldValue != launchAtLogin else { return }
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    @Published var notifyBuildFinished: Bool = UserDefaults.standard.object(forKey: "notifyBuildFinished") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(notifyBuildFinished, forKey: "notifyBuildFinished")
        }
    }

    @Published var scanInterval: TimeInterval = {
        let saved = UserDefaults.standard.double(forKey: "scanInterval")
        return saved >= 5 ? saved : 20
    }()

    private init() {
        let saved = UserDefaults.standard.double(forKey: scanIntervalKey)
        scanInterval = (saved >= 5 && saved <= 120) ? saved : 20

        $scanInterval
            .map { min(max($0, 5), 120) }
            .removeDuplicates()
            .sink { [weak self] normalized in
                guard let self = self else { return }
                UserDefaults.standard.set(normalized, forKey: self.scanIntervalKey)
            }
            .store(in: &cancellables)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[AppSettings] SMAppService error: \(error)")
            // Revert the stored value without re-triggering didSet
            UserDefaults.standard.set(!enabled, forKey: "launchAtLogin")
            objectWillChange.send()
        }
    }
}

