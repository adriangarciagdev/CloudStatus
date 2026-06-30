import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var initialSetupWindow: NSWindow?
    private var viewModel: StatusViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settingsStore = SettingsStore()
        let apiClient = SyncthingAPIClient()
        let viewModel = StatusViewModel(settingsStore: settingsStore, apiClient: apiClient)

        self.viewModel = viewModel

        NSLog(
            "[CloudStatus][Preferences] bundleIdentifier=%@ userDefaultsKeys=%@",
            Bundle.main.bundleIdentifier ?? "nil",
            UserDefaults.standard.dictionaryRepresentation().keys.sorted().joined(separator: ",")
        )

        NSLog(
            "[CloudStatus][InitialSetup] launch bundleIdentifier=%@ hasCompletedInitialSetupExists=%@ hasCompletedInitialSetup=%@ currentMode=%@",
            Bundle.main.bundleIdentifier ?? "nil",
            settingsStore.hasCompletedInitialSetupPreferenceExists ? "true" : "false",
            settingsStore.hasCompletedInitialSetup ? "true" : "false",
            settingsStore.operatingMode.rawValue
        )

        if settingsStore.hasCompletedInitialSetup {
            NSLog("[CloudStatus][InitialSetup] decision=startCloudStatus")
            startCloudStatus(with: viewModel)
        } else {
            NSLog("[CloudStatus][InitialSetup] decision=showOnboarding")
            showInitialSetupWindow(settingsStore: settingsStore, viewModel: viewModel)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController = nil
        initialSetupWindow = nil
        viewModel = nil
    }

    private func showInitialSetupWindow(settingsStore: SettingsStore, viewModel: StatusViewModel) {
        NSLog("[CloudStatus][InitialSetup] presenting onboarding currentMode=%@", settingsStore.operatingMode.rawValue)

        let initialSetupView = InitialSetupView(viewModel: viewModel) { [weak self, weak settingsStore, weak viewModel] selectedMode, selectedServerID in
            guard let self, let settingsStore, let viewModel else { return }

            NSLog(
                "[CloudStatus][InitialSetup] completing onboarding selectedMode=%@ selectedServerID=%@",
                selectedMode.rawValue,
                selectedServerID
            )
            settingsStore.operatingMode = selectedMode
            settingsStore.referenceDeviceID = selectedServerID
            settingsStore.hasCompletedInitialSetup = true
            initialSetupWindow?.close()
            initialSetupWindow = nil
            Task { @MainActor in
                self.startCloudStatus(with: viewModel)
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("initialSetup.title", comment: "Initial setup window title")
        window.contentView = NSHostingView(rootView: initialSetupView)
        window.center()
        window.isReleasedWhenClosed = false

        initialSetupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startCloudStatus(with viewModel: StatusViewModel) {
        if statusBarController == nil {
            statusBarController = StatusBarController(viewModel: viewModel)
        }

        viewModel.start()
    }
}
