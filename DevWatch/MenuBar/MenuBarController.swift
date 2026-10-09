import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: ObservableObject {
    private static var activeStatusItem: NSStatusItem?

    let viewModel: DevWatchViewModel
    private var statusItem: NSStatusItem!
    private var panel: MenuBarPanel?
    private var settingsPanel: NSPanel?
    private var statusMenu: NSMenu?
    private var cancellables: Set<AnyCancellable> = []
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init() {
        self.viewModel = DevWatchViewModel(scanner: PortScanner())

        if Self.shouldTerminateDuplicateProcess() {
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return
        }

        setupStatusItem()
        setupPanel()
        observeServices()
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    private func setupStatusItem() {
        if let existing = Self.activeStatusItem {
            NSStatusBar.system.removeStatusItem(existing)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        Self.activeStatusItem = statusItem

        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: "DevWatch")
        button.action = #selector(handleStatusItemClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open DevWatch", action: #selector(openFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit DevWatch", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusMenu = menu
    }

    private static func shouldTerminateDuplicateProcess() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)

        return runningApps.contains { $0.processIdentifier != currentPID }
    }

    private func setupPanel() {
        let contentView = DevWatchPopoverView(viewModel: viewModel, onOpenSettings: { [weak self] in
            self?.openSettings()
        })
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: NSColor(calibratedWhite: 0.12, alpha: 0.98)))
            )

        let hostingController = NSHostingController(rootView: contentView)
        let panel = MenuBarPanel(contentRect: NSRect(x: 0, y: 0, width: 396, height: 476))
        panel.contentViewController = hostingController
        self.panel = panel
        setupDismissMonitors()
    }

    private func observeServices() {
        viewModel.$services
            .receive(on: RunLoop.main)
            .sink { [weak self] services in
                self?.updateBadge(count: services.count)
            }
            .store(in: &cancellables)

        viewModel.$builds
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateBuildIndicator()
            }
            .store(in: &cancellables)
    }

    /// While a build runs, the status item turns into a hammer with the build percentage.
    private func updateBuildIndicator() {
        guard let button = statusItem.button else { return }

        guard let estimate = viewModel.menuBarBuildEstimate else {
            button.image = NSImage(systemSymbolName: "dot.radiowaves.left.and.right", accessibilityDescription: "DevWatch")
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            return
        }

        button.image = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: "Build running")
        if let progress = estimate.progress {
            let percent = Int((progress * 100).rounded(.down))
            button.attributedTitle = NSAttributedString(
                string: " \(estimate.isEstimated ? "~" : "")\(percent)%",
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]
            )
            button.imagePosition = .imageLeading
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
        }
    }

    private func updateBadge(count: Int) {
        guard let button = statusItem.button, viewModel.runningBuilds.isEmpty else { return }
        button.title = ""
        button.imagePosition = .imageOnly
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let currentEvent = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }

        if currentEvent.type == .rightMouseUp {
            showStatusMenu()
            return
        }

        togglePopover(sender)
    }

    @objc func openSettings() {
        if let existing = settingsPanel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView { [weak self] in
            self?.settingsPanel?.orderOut(nil)
            self?.settingsPanel = nil
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 330),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Settings"
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.level = .floating
        panel.contentViewController = NSHostingController(rootView: settingsView)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsPanel = panel
    }

    @objc private func openFromMenu() {
        guard let button = statusItem.button else { return }
        showPanel(relativeTo: button)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func showStatusMenu() {
        guard let statusMenu, let button = statusItem.button else { return }

        panel?.orderOut(nil)
        viewModel.setPanelVisible(false)

        statusItem.menu = statusMenu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        guard let panel else { return }

        if panel.isVisible {
            panel.orderOut(nil)
            viewModel.setPanelVisible(false)
        } else {
            showPanel(relativeTo: sender)
        }
    }

    private func showPanel(relativeTo button: NSStatusBarButton) {
        guard let panel, let buttonWindow = button.window else { return }

        let buttonFrame = button.convert(button.bounds, to: nil)
        let screenFrame = buttonWindow.convertToScreen(buttonFrame)
        let panelSize = panel.frame.size

        let origin = NSPoint(
            x: round(screenFrame.midX - panelSize.width / 2),
            y: round(screenFrame.minY - panelSize.height - 6)
        )

        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        viewModel.setPanelVisible(true)
    }

    private func setupDismissMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, let panel, panel.isVisible else { return event }

            if event.type == .keyDown, event.keyCode == 53 {
                panel.orderOut(nil)
                self.viewModel.setPanelVisible(false)
                return nil
            }

            if let window = event.window, window == panel {
                return event
            }

            panel.orderOut(nil)
            self.viewModel.setPanelVisible(false)
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel, panel.isVisible else { return }
            panel.orderOut(nil)
            self.viewModel.setPanelVisible(false)
        }
    }
}

private final class MenuBarPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
