import Foundation

/// Remembers how long previous builds took so running builds can show a time estimate.
final class BuildHistoryStore {
    private let defaultsKey = "buildDurations"
    private let maxSamples = 8
    private var durations: [String: [TimeInterval]]

    init() {
        durations = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [TimeInterval]] ?? [:]
    }

    /// Median of recent successful runs; robust against the occasional cold or cached build.
    func typicalDuration(for job: BuildJob) -> TimeInterval? {
        guard let samples = durations[job.historyKey], !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    func record(_ job: BuildJob) {
        let duration = job.elapsed()
        guard duration >= 3 else { return }

        var samples = durations[job.historyKey] ?? []
        samples.append(duration)
        durations[job.historyKey] = Array(samples.suffix(maxSamples))
        UserDefaults.standard.set(durations, forKey: defaultsKey)
    }
}
