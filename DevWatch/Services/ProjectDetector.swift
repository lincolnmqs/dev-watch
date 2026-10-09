import Foundation

struct ProjectDetector {
    private static let projectMarkers = [
        ".git",
        "package.json",
        "Cargo.toml",
        "pyproject.toml",
        "Gemfile"
    ]

    private static let workspaceMarkers = [
        "pnpm-workspace.yaml",
        "turbo.json",
        "nx.json",
        "lerna.json"
    ]

    static func isUserProjectDirectory(_ directory: String?) -> Bool {
        guard let directory, !directory.isEmpty, directory != "/" else { return false }

        let normalized = URL(fileURLWithPath: directory).standardizedFileURL.path.lowercased()
        let home = FileManager.default.homeDirectoryForCurrentUser.path.lowercased()

        guard normalized.hasPrefix(home) else { return false }

        let excludedFragments = [
            "/library/",
            "/.docker/",
            "/docker/",
            "/containers/",
            "/application support/",
            "/caches/",
            "/logs/",
            "/tmp/",
            "/.trash/"
        ]

        guard !excludedFragments.contains(where: { normalized.contains($0) }) else {
            return false
        }

        return isProjectDirectory(directory)
    }

    static func projectDirectory(from directory: String?, commandLine: [String]) -> String? {
        if let directory, isProjectDirectory(directory) {
            return preferredProjectRoot(for: directory)
        }

        for argument in commandLine {
            let expanded = (argument as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/") else { continue }

            if let resolved = resolveProjectDirectory(fromPath: expanded) {
                return preferredProjectRoot(for: resolved)
            }
        }

        if let directory {
            return preferredProjectRoot(for: directory)
        }

        return nil
    }

    static func projectName(from directory: String?) -> String? {
        guard let directory, !directory.isEmpty, directory != "/" else { return nil }
        let url = URL(fileURLWithPath: directory)

        if let name = nameFromPackageJSON(at: url) { return name }
        if let name = nameFromCargoToml(at: url) { return name }
        if let name = nameFromPyproject(at: url) { return name }
        if let name = nameFromGitDirectory(at: url) { return name }

        let last = url.lastPathComponent
        return last.isEmpty ? nil : last
    }

    private static func nameFromPackageJSON(at url: URL) -> String? {
        let file = url.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String,
              !name.isEmpty else { return nil }
        return name
    }

    private static func nameFromCargoToml(at url: URL) -> String? {
        let file = url.appendingPathComponent("Cargo.toml")
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        var inPackage = false
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[package]" { inPackage = true; continue }
            if trimmed.hasPrefix("[") { inPackage = false }
            if inPackage, trimmed.hasPrefix("name") {
                let parts = trimmed.components(separatedBy: "=")
                if parts.count >= 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
            }
        }
        return nil
    }

    private static func nameFromPyproject(at url: URL) -> String? {
        let file = url.appendingPathComponent("pyproject.toml")
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        var inSection = false
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[project]" || trimmed == "[tool.poetry]" { inSection = true; continue }
            if trimmed.hasPrefix("[") { inSection = false }
            if inSection, trimmed.hasPrefix("name") {
                let parts = trimmed.components(separatedBy: "=")
                if parts.count >= 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
            }
        }
        return nil
    }

    private static func nameFromGitDirectory(at url: URL) -> String? {
        var current = url
        for _ in 0..<5 {
            let git = current.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: git.path) {
                return current.lastPathComponent
            }
            let parent = current.deletingLastPathComponent()
            if parent == current { break }
            current = parent
        }
        return nil
    }

    private static func isProjectDirectory(_ directory: String) -> Bool {
        guard !directory.isEmpty, directory != "/" else { return false }
        let url = URL(fileURLWithPath: directory)
        let candidates = projectMarkers + ["yarn.lock", "manage.py"]

        return candidates.contains { FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path) }
    }

    private static func preferredProjectRoot(for directory: String) -> String {
        let url = URL(fileURLWithPath: directory).standardizedFileURL

        if let workspaceRoot = findWorkspaceRoot(startingAt: url) {
            return workspaceRoot.path
        }

        return url.path
    }

    private static func findWorkspaceRoot(startingAt url: URL) -> URL? {
        var current = url
        var bestMatch: URL?

        for _ in 0..<8 {
            if hasExplicitWorkspaceMarker(at: current) {
                bestMatch = current
            }

            let parent = current.deletingLastPathComponent()
            if parent == current { break }
            current = parent
        }

        return bestMatch
    }

    private static func hasExplicitWorkspaceMarker(at url: URL) -> Bool {
        if workspaceMarkers.contains(where: { marker in
            FileManager.default.fileExists(atPath: url.appendingPathComponent(marker).path)
        }) {
            return true
        }

        let packageFile = url.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        return json["workspaces"] != nil
    }

    private static func resolveProjectDirectory(fromPath path: String) -> String? {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        guard exists else { return nil }

        if isDirectory.boolValue {
            if isProjectDirectory(path) {
                return path
            }

            if let nested = findWorkspaceRoot(startingAt: URL(fileURLWithPath: path)) {
                return nested.path
            }

            return nil
        }

        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        guard isProjectDirectory(parent) || findWorkspaceRoot(startingAt: URL(fileURLWithPath: parent)) != nil else {
            return nil
        }
        return parent
    }
}
