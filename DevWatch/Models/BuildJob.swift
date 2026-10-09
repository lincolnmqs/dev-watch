import Foundation

struct BuildJob: Identifiable, Hashable {
    enum Tool: String {
        case gradle = "Gradle"
        case xcodebuild = "Xcode"
        case flutter = "Flutter"
        case eas = "EAS"
    }

    enum Platform: String {
        case android = "Android"
        case ios = "iOS"
        case web = "Web"
        case desktop = "Desktop"
        case other = "Build"
    }

    /// Where the build output is headed, when the command line makes it clear.
    enum Distribution: String {
        case apk = "APK"
        case playStore = "Play Store"
        case appStore = "App Store"
        case adHoc = "Ad Hoc"
        case enterprise = "Enterprise"
        case development = "Dev"
    }

    enum State: String {
        case running
        case succeeded
        case failed
        case cancelled
        /// The process exited but DevWatch could not observe its exit status.
        case finished

        var isFinished: Bool { self != .running }
    }

    let tool: Tool
    let platform: Platform
    var projectName: String
    var projectDirectory: String
    var buildDirectory: String
    var taskSummary: String
    var startedAt: Date
    var finishedAt: Date?
    var completedTasks: Int?
    var totalTasks: Int?
    var currentTask: String?
    var state: State
    var stopPID: Int?
    var artifactPath: String?
    var distribution: Distribution?

    /// One build per project and platform: this keeps the row stable while a build is
    /// first seen as a bare process and later picks up a progress file.
    var id: String {
        "\(platform.rawValue)|\(projectDirectory)"
    }

    var historyKey: String {
        "\(id)|\(taskSummary)"
    }

    var displayTask: String {
        let trimmed = taskSummary.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? tool.rawValue.lowercased() : trimmed
    }

    var measuredProgress: Double? {
        guard let completedTasks, let totalTasks, totalTasks > 0 else { return nil }
        return min(Double(completedTasks) / Double(totalTasks), 1)
    }

    func elapsed(at now: Date = Date()) -> TimeInterval {
        max((finishedAt ?? now).timeIntervalSince(startedAt), 0)
    }

    func estimate(typicalDuration: TimeInterval?, now: Date = Date()) -> BuildEstimate {
        let elapsed = elapsed(at: now)

        if let progress = measuredProgress {
            // Task counts are front-loaded (cheap up-to-date checks first, compilation later),
            // so a purely linear guess is noisy early on. Lean on history until progress is meaningful.
            var expectedTotal: TimeInterval?
            if let typicalDuration {
                let linear = progress > 0.05 ? elapsed / progress : typicalDuration
                expectedTotal = typicalDuration * (1 - progress) + linear * progress
            } else if progress >= 0.25 {
                expectedTotal = elapsed / progress
            }
            return BuildEstimate(progress: progress, isEstimated: false, remaining: expectedTotal.map { max($0 - elapsed, 0) })
        }

        if let typicalDuration, typicalDuration > 0 {
            return BuildEstimate(
                progress: min(elapsed / typicalDuration, 0.97),
                isEstimated: true,
                remaining: max(typicalDuration - elapsed, 0)
            )
        }

        return BuildEstimate(progress: nil, isEstimated: false, remaining: nil)
    }
}

struct BuildEstimate {
    /// nil means indeterminate.
    let progress: Double?
    /// True when progress is derived from previous build durations rather than reported by the tool.
    let isEstimated: Bool
    let remaining: TimeInterval?
}

enum DurationFormatter {
    static func short(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s" }
        return "\(seconds / 3600)h \(String(format: "%02d", (seconds % 3600) / 60))m"
    }
}
