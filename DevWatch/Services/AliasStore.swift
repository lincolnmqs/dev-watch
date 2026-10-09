import Combine
import Foundation

final class AliasStore: ObservableObject {
    static let shared = AliasStore()

    @Published private(set) var aliases: [Int: String] = [:]

    private let key = "devwatch.port.aliases"

    init() {
        load()
    }

    func alias(for port: Int) -> String? {
        aliases[port]
    }

    func set(_ name: String, for port: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            aliases.removeValue(forKey: port)
        } else {
            aliases[port] = trimmed
        }
        save()
    }

    func remove(for port: Int) {
        aliases.removeValue(forKey: port)
        save()
    }

    private func save() {
        let dict = Dictionary(uniqueKeysWithValues: aliases.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(dict, forKey: key)
    }

    private func load() {
        guard let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: String] else { return }
        aliases = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in
            guard let port = Int(k) else { return nil }
            return (port, v)
        })
    }
}
