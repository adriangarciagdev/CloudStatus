import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let viewModel: StatusViewModel
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?

    init(viewModel: StatusViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        configurePopover()
        configureButton()
        observeApplicationFocus()
        bindViewModel()
        updateIcon()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 430)
        popover.contentViewController = NSHostingController(
            rootView: MainStatusView(
                viewModel: viewModel,
                openWebUI: { [weak self] in self?.openWebUI() },
                openSettings: { [weak self] in self?.openSettings() },
                quitApp: { NSApp.terminate(nil) }
            )
        )
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func observeApplicationFocus() {
        NotificationCenter.default.publisher(
            for: NSApplication.didResignActiveNotification,
            object: NSApp
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.popover.performClose(nil)
        }
        .store(in: &cancellables)
    }

    private func bindViewModel() {
        viewModel.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIcon()
            }
            .store(in: &cancellables)

        viewModel.$menuBarState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIcon()
            }
            .store(in: &cancellables)

        viewModel.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIcon()
            }
            .store(in: &cancellables)

        viewModel.settingsStore.$iconTheme
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIcon()
            }
            .store(in: &cancellables)

        viewModel.settingsStore.$operatingMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIcon()
            }
            .store(in: &cancellables)

        viewModel.settingsStore.$referenceDeviceID
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIcon()
            }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        let state = viewModel.menuBarState
        let image = IconProvider.menuBarImage(for: state, theme: viewModel.settingsStore.iconTheme)

        image?.size = NSSize(width: 22, height: 22)

        button.image = image
        button.contentTintColor = nil
        button.toolTip = "CloudStatus: \(viewModel.displayedTitle)"
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func openWebUI() {
        guard let url = viewModel.settingsStore.webURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func openSettings() {
        popover.performClose(nil)

        if settingsWindow == nil {
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = NSLocalizedString("settings.window.title", comment: "Settings window title")
            settingsWindow?.center()
            settingsWindow?.isReleasedWhenClosed = false
        }

        settingsWindow?.contentView = NSHostingView(
            rootView: SettingsView(settingsStore: viewModel.settingsStore, devices: viewModel.devices) { [viewModel] in
                Task { await viewModel.refresh() }
            }
        )

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
