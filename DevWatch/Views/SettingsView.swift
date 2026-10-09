import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .opacity(0.15)

            generalSection

            buildsSection

            Spacer()

            footer
        }
        .frame(width: 340, height: 330)
        .background(Color(nsColor: NSColor(calibratedWhite: 0.12, alpha: 1.0)))
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("General")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            settingRow(
                icon: "power",
                title: "Launch at Login",
                description: "Start DevWatch automatically when you log in."
            ) {
                Toggle("", isOn: $settings.launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            settingRow(
                icon: "timer",
                title: "Scan interval",
                description: "Lower interval is more responsive; higher interval saves CPU."
            ) {
                HStack(spacing: 6) {
                    Slider(value: $settings.scanInterval, in: 5...120, step: 1)
                        .controlSize(.small)
                    Text("\(Int(settings.scanInterval))s")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 38)
                }
                .frame(maxWidth: 180)
            }
        }
    }

    private var buildsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Builds")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

            settingRow(
                icon: "bell.badge",
                title: "Notify when builds finish",
                description: "Get a notification when a build succeeds, fails or is cancelled."
            ) {
                Toggle("", isOn: $settings.notifyBuildFinished)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            settingRow(
                icon: "chart.bar.fill",
                title: "Gradle task progress",
                description: GradleProgressReporter.isInstalled
                    ? "Init script installed: Gradle builds report real progress."
                    : "Not installed: Gradle builds show elapsed time and estimates only."
            ) {
                Image(systemName: GradleProgressReporter.isInstalled ? "checkmark.circle.fill" : "minus.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(GradleProgressReporter.isInstalled ? Color.green : Color.white.opacity(0.3))
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") {
                onClose()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func settingRow<Control: View>(
        icon: String,
        title: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.38))
            }

            Spacer()
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
