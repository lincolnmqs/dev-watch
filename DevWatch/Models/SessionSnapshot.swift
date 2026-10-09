import Foundation

struct SessionSnapshot: Codable, Identifiable {
    struct ServiceRecord: Codable, Identifiable {
        let id: String
        let port: Int
        let host: String
        let processName: String
        let primaryName: String
        let pid: Int
        let projectName: String?
        let projectDirectory: String?
        let commandSummary: String?
        let runtime: String?
    }

    let id: UUID
    let createdAt: Date
    let hostname: String
    let services: [ServiceRecord]

    var title: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}
