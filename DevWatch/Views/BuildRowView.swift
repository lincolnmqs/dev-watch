import SwiftUI

struct BuildRowView: View {
    let job: BuildJob
    let estimate: (Date) -> BuildEstimate
    let stopAction: () -> Void
    let revealArtifactAction: () -> Void
    let copyArtifactAction: () -> Void
    let openFolderAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        // Ticks every second while running so elapsed time and history-based estimates move between scans.
        TimelineView(.periodic(from: .now, by: job.state == .running ? 1 : 60)) { context in
            content(now: context.date)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu { menuItems }
        .help(job.currentTask.map { "Running \($0)" } ?? job.buildDirectory)
    }

    private func content(now: Date) -> some View {
        let estimate = estimate(now)

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    statusIndicator

                    Text(job.projectName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Image(systemName: platformSymbol)
                            .font(.system(size: 8, weight: .bold))
                        Text(job.platform == .other ? job.tool.rawValue : job.platform.rawValue)
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent.opacity(0.95))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(accent.opacity(0.14)))

                    Spacer(minLength: 4)

                    percentLabel(estimate)
                }

                BuildProgressBar(
                    progress: barProgress(estimate),
                    tint: barTint,
                    isEstimated: estimate.isEstimated && job.state == .running
                )

                HStack(spacing: 5) {
                    Text(job.displayTask)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    ForEach(detailParts(estimate, now: now), id: \.self) { part in
                        Text("·")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.2))
                        Text(part)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.32))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }

            Menu { menuItems } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        if job.state == .running, job.stopPID != nil {
            Button("Stop Build", action: stopAction)
        }
        if job.artifactPath != nil {
            Button("Show \(artifactName) in Finder", action: revealArtifactAction)
            Button("Copy Artifact Path", action: copyArtifactAction)
        }
        Button("Open Project Folder", action: openFolderAction)
        if job.state.isFinished {
            Divider()
            Button("Dismiss", action: dismissAction)
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch job.state {
        case .running:
            PulsingDot(color: accent)
        case .succeeded, .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(job.state == .succeeded ? Color.green : Color.white.opacity(0.5))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.red.opacity(0.9))
        case .cancelled:
            Image(systemName: "stop.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.4))
        }
    }

    @ViewBuilder
    private func percentLabel(_ estimate: BuildEstimate) -> some View {
        switch job.state {
        case .running:
            if let progress = estimate.progress {
                Text("\(estimate.isEstimated ? "~" : "")\(Int((progress * 100).rounded(.down)))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(estimate.isEstimated ? 0.55 : 0.9))
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.3), value: Int(progress * 100))
            }
        case .succeeded, .finished:
            if job.artifactPath != nil {
                Button(action: revealArtifactAction) {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                        Text(artifactExtension)
                    }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Show \(artifactName) in Finder")
            }
        case .failed, .cancelled:
            EmptyView()
        }
    }

    private func barProgress(_ estimate: BuildEstimate) -> Double? {
        switch job.state {
        case .running: return estimate.progress
        case .succeeded, .finished: return 1
        case .failed, .cancelled: return job.measuredProgress ?? 1
        }
    }

    private var barTint: Color {
        switch job.state {
        case .running: return accent
        case .succeeded: return .green
        case .finished: return .white.opacity(0.35)
        case .failed: return .red.opacity(0.8)
        case .cancelled: return .white.opacity(0.2)
        }
    }

    private func detailParts(_ estimate: BuildEstimate, now: Date) -> [String] {
        let elapsed = DurationFormatter.short(job.elapsed(at: now))

        switch job.state {
        case .running:
            var parts = [elapsed]
            if let remaining = estimate.remaining {
                parts.append(remaining >= 1 ? "~\(DurationFormatter.short(remaining)) left" : "finishing…")
            } else if estimate.progress == nil, job.tool == .gradle, GradleProgressReporter.isInstalled {
                parts.append("starting…")
            }
            return parts
        case .succeeded, .finished: return ["done in \(elapsed)"]
        case .failed: return ["failed after \(elapsed)"]
        case .cancelled: return ["cancelled"]
        }
    }

    private var artifactName: String {
        job.artifactPath.map { ($0 as NSString).lastPathComponent } ?? "artifact"
    }

    private var artifactExtension: String {
        job.artifactPath.map { ($0 as NSString).pathExtension.uppercased() } ?? ""
    }

    private var accent: Color {
        switch job.platform {
        case .android: return Color(red: 0.35, green: 0.85, blue: 0.5)
        case .ios: return Color(red: 0.35, green: 0.62, blue: 1.0)
        case .web: return Color(red: 1.0, green: 0.66, blue: 0.3)
        case .desktop: return Color(red: 0.72, green: 0.55, blue: 1.0)
        case .other: return Color.white.opacity(0.75)
        }
    }

    private var platformSymbol: String {
        switch job.platform {
        case .android: return "shippingbox.fill"
        case .ios: return "iphone"
        case .web: return "globe"
        case .desktop: return "desktopcomputer"
        case .other: return "hammer.fill"
        }
    }
}

private struct BuildProgressBar: View {
    /// nil renders an indeterminate sweep.
    let progress: Double?
    let tint: Color
    let isEstimated: Bool

    @State private var sweep = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))

                if let progress {
                    Capsule()
                        .fill(tint.opacity(isEstimated ? 0.55 : 1))
                        .frame(width: max(proxy.size.width * progress, 4))
                        .animation(.easeOut(duration: 0.6), value: progress)
                } else {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0), tint.opacity(0.9), tint.opacity(0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * 0.35)
                        .offset(x: sweep ? proxy.size.width * 0.65 : 0)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: sweep)
                        .onAppear { sweep = true }
                }
            }
        }
        .frame(height: 4)
        .clipShape(Capsule())
    }
}

private struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .scaleEffect(isPulsing ? 1.35 : 1.0)
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
