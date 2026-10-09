import SwiftUI

struct PortRowView: View {
    let service: PortService
    let isNew: Bool
    let openAction: () -> Void
    let copyURLAction: () -> Void
    let copyPortAction: () -> Void
    let killAction: () -> Void
    let forceKillAction: () -> Void
    let revealAction: () -> Void
    let renameAliasAction: () -> Void
    let showInfoAction: () -> Void
    let showCommandAction: () -> Void

    @State private var showNewFlash = false
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .scaleEffect(isPulsing ? 1.35 : 1.0)
                        .opacity(isPulsing ? 0.4 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                            value: isPulsing
                        )

                    Text(service.primaryName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let runtime = service.runtimeBadgeText {
                        HStack(spacing: 4) {
                            Image(systemName: service.runtimeSymbolName)
                                .font(.system(size: 8, weight: .bold))

                            Text(runtime)
                        }
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                }

                HStack(spacing: 5) {
                    Text(":\(service.port)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))

                    Text("·")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.2))
                    Text(service.secondaryName)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.36))
                        .lineLimit(1)

                    if let uptime = service.uptimeString {
                        Text("·")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.2))
                        Text(uptime)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.28))
                    }
                }
            }

            Spacer(minLength: 8)

            Menu {
                Button("Copy URL", action: copyURLAction)
                Button("Copy Port", action: copyPortAction)
                if service.canOpenInBrowser {
                    Button("Open in Browser", action: openAction)
                }
                Button("Info", action: showInfoAction)
                Button("Reveal Process", action: revealAction)
                Button("Show Command Used to Start", action: showCommandAction)
                Button("Rename Alias", action: renameAliasAction)
                Divider()
                Button("Kill Process", action: killAction)
                Button("Force Kill", role: .destructive, action: forceKillAction)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(showNewFlash ? Color.green.opacity(0.12) : .clear)
                .animation(.easeOut(duration: 1.5), value: showNewFlash)
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy URL", action: copyURLAction)
            Button("Copy Port", action: copyPortAction)
            if service.canOpenInBrowser {
                Button("Open in Browser", action: openAction)
            }
            Button("Info", action: showInfoAction)
            Button("Reveal Process", action: revealAction)
            Button("Show Command Used to Start", action: showCommandAction)
            Button("Rename Alias", action: renameAliasAction)
            Divider()
            Button("Kill Process", action: killAction)
            Button("Force Kill", role: .destructive, action: forceKillAction)
        }
        .onAppear {
            isPulsing = true
            if isNew {
                showNewFlash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showNewFlash = false
                }
            }
        }
    }
}
