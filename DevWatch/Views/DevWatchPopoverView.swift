import SwiftUI

struct DevWatchPopoverView: View {
    @ObservedObject var viewModel: DevWatchViewModel
    let onOpenSettings: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            searchBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            if let stopped = viewModel.recentlyStopped {
                stoppedBanner(stopped)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !viewModel.builds.isEmpty {
                buildList
                    .transition(.move(edge: .top).combined(with: .opacity))

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }

            Group {
                if let errorMessage = viewModel.errorMessage, viewModel.services.isEmpty {
                    EmptyStateView(
                        title: "Unable to Scan Ports",
                        message: errorMessage,
                        isError: true
                    )
                } else if viewModel.visibleServices.isEmpty, !viewModel.isRefreshing {
                    EmptyStateView(
                        title: "No Local Services Running",
                        message: "DevWatch shows services tied to real project folders plus Docker containers with published local ports."
                    )
                } else if viewModel.projectSections.isEmpty, !viewModel.isRefreshing {
                    EmptyStateView(
                        title: "No Matching Services",
                        message: "Try filtering by project name, service name, port, or command."
                    )
                } else {
                    serviceList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(width: 380, height: 460)
        .animation(.easeInOut(duration: 0.25), value: viewModel.recentlyStopped == nil)
        .animation(.easeInOut(duration: 0.25), value: viewModel.builds.map(\.id))
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) {
                appeared = true
            }
        }
        .onDisappear {
            appeared = false
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("DevWatch")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(spacing: 5) {
                    if !viewModel.visibleServices.isEmpty {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                    }
                    Text(
                        viewModel.visibleServices.isEmpty
                            ? "no local services"
                            : "\(viewModel.projectSections.count) section\(viewModel.projectSections.count == 1 ? "" : "s") · \(viewModel.filteredServices.count) service\(viewModel.filteredServices.count == 1 ? "" : "s")"
                    )
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: viewModel.filteredServices.count)
                }
            }

            Spacer()

            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.4))
                    .padding(.trailing, 6)
                    .transition(.opacity)
            }

            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: [.command])
            .help("Refresh (⌘R)")
        }
    }

    private var buildList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Builds")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                Spacer()
                if !viewModel.runningBuilds.isEmpty {
                    Text("\(viewModel.runningBuilds.count) running")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.32))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 0)

            // Keep services visible even with several builds: scroll beyond three rows.
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(viewModel.builds) { job in
                        BuildRowView(
                            job: job,
                            estimate: { viewModel.estimate(for: job, now: $0) },
                            stopAction: { viewModel.stopBuild(job) },
                            revealArtifactAction: { viewModel.revealArtifact(job) },
                            copyArtifactAction: { viewModel.copyArtifactPath(job) },
                            openFolderAction: { viewModel.openBuildFolder(job) },
                            dismissAction: { viewModel.dismissBuild(job) }
                        )
                    }
                }
            }
            .frame(height: CGFloat(min(viewModel.builds.count, 3)) * 68)
        }
    }

    private var serviceList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.projectSections.enumerated()), id: \.element.id) { sectionIndex, section in
                    if section.services.count > 1 || section.name == "Docker" {
                        ProjectHeaderView(section: section)
                            .padding(.horizontal, 16)
                            .padding(.top, sectionIndex == 0 ? 6 : 12)
                            .padding(.bottom, 4)
                    }

                    ForEach(Array(section.services.enumerated()), id: \.element.id) { index, service in
                        PortRowView(
                            service: service,
                            isNew: viewModel.newServiceIDs.contains(service.id),
                            openAction: { viewModel.openInBrowser(service) },
                            copyURLAction: { viewModel.copyURL(service) },
                            copyPortAction: { viewModel.copyPort(service) },
                            killAction: { viewModel.killProcess(service) },
                            forceKillAction: { viewModel.forceKillProcess(service) },
                            revealAction: { viewModel.revealProcess(service) },
                            renameAliasAction: { viewModel.renameAlias(service) },
                            showInfoAction: { viewModel.showInfo(service) },
                            showCommandAction: { viewModel.showCommand(service) }
                        )
                        .opacity(appeared ? 1 : 0)
                        .animation(
                            .easeOut(duration: 0.22).delay(Double(index) * 0.04),
                            value: appeared
                        )

                        if index < section.services.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, 52)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.32))

            TextField("Filter projects, services, ports...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.88))

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.28))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(0.07))
        )
    }

    private var footer: some View {
        HStack {
            UpdatedLabel(date: viewModel.lastUpdated)
            Spacer()
            Button {
                viewModel.saveSnapshot()
            } label: {
                Text("snapshot")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help("Save dev session snapshot")

            Text("·")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.18))

            Text("auto · 5s")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.18))
        }
    }

    private func stoppedBanner(_ service: PortService) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red.opacity(0.8))
                .frame(width: 5, height: 5)
            Text("\(service.processName) stopped on :\(service.port)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.1))
    }
}

private struct ProjectHeaderView: View {
    let section: DevWatchViewModel.ProjectSection

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))

                Text(section.subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.28))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text("\(section.services.count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.32))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.06)))
        }
    }
}

private struct UpdatedLabel: View {
    let date: Date?
    @State private var text = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.22))
            .onReceive(timer) { _ in update() }
            .onAppear { update() }
    }

    private func update() {
        guard let date else { text = ""; return }
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 5 { text = "updated just now" }
        else if diff < 60 { text = "updated \(diff)s ago" }
        else { text = "updated \(diff / 60)m ago" }
    }
}
