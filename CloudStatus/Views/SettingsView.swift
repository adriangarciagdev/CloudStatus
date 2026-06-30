import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    let devices: [DeviceInfo]
    let onSave: () -> Void

    private let apiClient = SyncthingAPIClient()

    @State private var draft: SettingsDraft
    @State private var connectionMessage: String?
    @State private var connectionMessageIsError = false
    @State private var isTestingConnection = false
    @State private var supportProjectWindow: NSWindow?
    @State private var isSupportLinkHovered = false

    init(settingsStore: SettingsStore, devices: [DeviceInfo], onSave: @escaping () -> Void) {
        self.settingsStore = settingsStore
        self.devices = devices
        self.onSave = onSave
        _draft = State(initialValue: SettingsDraft(settingsStore: settingsStore))
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

        guard !version.isEmpty else { return "v0.8" }
        return "v\(version)"
    }

    private var referenceDeviceOptions: [DeviceInfo] {
        devices.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSection(NSLocalizedString("settings.connection.section", comment: "Syncthing connection settings section")) {
                ForEach(SyncthingConnectionMode.allCases) { mode in
                    selectionButton(
                        title: mode.localizedTitle,
                        isSelected: draft.connectionMode == mode
                    ) {
                        draft.connectionMode = mode
                        connectionMessage = nil
                        if mode == .automatic {
                            Task { await testAutomaticConnection(applyOnSuccess: true) }
                        }
                    }
                }

                if draft.connectionMode == .automatic {
                    if let connectionMessage {
                        Text(connectionMessage)
                            .font(.caption)
                            .foregroundColor(connectionMessageIsError ? .red : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    settingsTextField(NSLocalizedString("settings.connection.address", comment: "Syncthing API address field label"), text: $draft.apiAddress)
                    settingsSecureField(NSLocalizedString("settings.connection.apiKey", comment: "Syncthing API key field label"), text: $draft.apiKey)

                    HStack {
                        Spacer()
                            .frame(width: 88)

                        Button(NSLocalizedString("settings.connection.test", comment: "Test Syncthing connection button")) {
                            Task { await testManualConnection(applyOnSuccess: true) }
                        }
                        .disabled(isTestingConnection)

                        if let connectionMessage {
                            Text(connectionMessage)
                                .font(.caption)
                                .foregroundColor(connectionMessageIsError ? .red : .secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            settingsSection(NSLocalizedString("settings.startup.section", comment: "Automatic startup settings section title")) {
                Toggle(NSLocalizedString("settings.startup.launchAtLogin", comment: "Launch CloudStatus at login toggle"), isOn: $draft.launchAtLogin)
                    .onChange(of: draft.launchAtLogin) { isEnabled in
                        NSLog("[CloudStatus][LoginItems][Monterey] [1] Toggle UI cambiado: %@", isEnabled ? "activado" : "desactivado")
                    }
            }

            settingsSection(NSLocalizedString("settings.iconTheme.section", comment: "Icon theme settings section title")) {
                ForEach(IconTheme.allCases) { theme in
                    selectionButton(
                        title: theme.localizedTitle,
                        isSelected: draft.iconTheme == theme
                    ) {
                        draft.iconTheme = theme
                    }
                }
            }

            settingsSection(NSLocalizedString("settings.viewMode.section", comment: "View mode settings section title")) {
                ForEach(OperatingMode.allCases) { mode in
                    selectionButton(
                        title: mode.localizedTitle,
                        isSelected: draft.operatingMode == mode
                    ) {
                        draft.operatingMode = mode
                    }
                }

                if draft.operatingMode == .referenceDevice {
                    Picker(NSLocalizedString("settings.reference.server", comment: "Cloud mode server picker label"), selection: $draft.referenceDeviceID) {
                        if draft.referenceDeviceID.isEmpty {
                            Text(NSLocalizedString("settings.reference.selectDevice", comment: "Reference device picker placeholder")).tag("")
                        }

                        if selectedReferenceDeviceIsMissing {
                            Text(NSLocalizedString("settings.reference.deviceUnavailable", comment: "Reference device missing picker option")).tag(draft.referenceDeviceID)
                        }

                        ForEach(referenceDeviceOptions) { device in
                            Text(device.displayName).tag(device.deviceID)
                        }
                    }
                    .disabled(referenceDeviceOptions.isEmpty)
                }
            }

            Spacer(minLength: 0)

            Divider()

            ZStack {
                Button {
                    showSupportProjectWindow()
                } label: {
                    HStack(spacing: 7) {
                        Text("☕")
                        Text(NSLocalizedString("support.open", comment: "Open support project window button"))
                    }
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(supportLinkColor)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.12), value: isSupportLinkHovered)
                .onHover { hovering in
                    isSupportLinkHovered = hovering
                    hovering ? NSCursor.pointingHand.push() : NSCursor.pop()
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CloudStatus")
                        Text(String.localizedStringWithFormat(NSLocalizedString("settings.version", comment: "Settings app version label"), appVersionText))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Spacer()

                    Button(NSLocalizedString("settings.save", comment: "Save settings button")) {
                        Task { await saveDraft() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasPendingChanges || isTestingConnection)
                }
            }
        }
        .padding(24)
        .frame(width: 460, height: 520)
        .task {
            if draft.connectionMode == .automatic {
                await testAutomaticConnection(applyOnSuccess: false)
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Divider()
            }

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
    }

    private func selectionButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(
                title,
                systemImage: isSelected ? "largecircle.fill.circle" : "circle"
            )
        }
        .buttonStyle(.plain)
    }

    private func settingsTextField(_ title: String, text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .frame(width: 78, alignment: .trailing)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func settingsSecureField(_ title: String, text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .frame(width: 78, alignment: .trailing)
            SecureField("", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var selectedReferenceDeviceIsMissing: Bool {
        !draft.referenceDeviceID.isEmpty &&
        !referenceDeviceOptions.contains { $0.deviceID == draft.referenceDeviceID }
    }

    private var hasPendingChanges: Bool {
        draft != SettingsDraft(settingsStore: settingsStore)
    }

    private var supportLinkColor: Color {
        isSupportLinkHovered
            ? Color(nsColor: .labelColor)
            : Color(nsColor: .secondaryLabelColor)
    }

    private func applyDraft() {
        settingsStore.connectionMode = draft.connectionMode
        settingsStore.iconTheme = draft.iconTheme
        settingsStore.operatingMode = draft.operatingMode
        settingsStore.referenceDeviceID = draft.referenceDeviceID
        settingsStore.launchAtLogin = draft.launchAtLogin
    }

    private func applyConnection(_ connection: SyncthingConnectionConfig) {
        settingsStore.applyConnectionConfig(connection)
        draft.apiAddress = connection.apiAddress
        draft.apiKey = connection.apiKey
    }

    private func saveDraft() async {
        NSLog("[CloudStatus][LoginItems][Monterey] Guardar: antes de aplicar el borrador")

        switch draft.connectionMode {
        case .automatic:
            settingsStore.connectionMode = .automatic
            await testAutomaticConnection(applyOnSuccess: true)
        case .manual:
            guard await testManualConnection(applyOnSuccess: true) else { return }
            settingsStore.connectionMode = .manual
        }

        applyDraft()
        UserDefaults.standard.set(true, forKey: "debugPreferencesWriteTest")
        UserDefaults.standard.synchronize()
        NSLog("[CloudStatus][Preferences] debugPreferencesWriteTest written; bundleIdentifier=%@", Bundle.main.bundleIdentifier ?? "nil")
        NSLog("[CloudStatus][LoginItems][Monterey] Guardar: después de aplicar el borrador")
        onSave()
        NSLog("[CloudStatus][LoginItems][Monterey] Guardar: después de onSave")
    }

    @discardableResult
    private func testManualConnection(applyOnSuccess: Bool) async -> Bool {
        guard let connection = draft.manualConnectionConfig else {
            connectionMessage = NSLocalizedString("settings.connection.failed", comment: "Syncthing connection failed message")
            connectionMessageIsError = true
            return false
        }

        return await testConnection(connection, applyOnSuccess: applyOnSuccess)
    }

    @discardableResult
    private func testAutomaticConnection(applyOnSuccess: Bool) async -> Bool {
        guard let connection = settingsStore.detectLocalSyncthingConfig() else {
            connectionMessage = NSLocalizedString("settings.connection.failed", comment: "Syncthing connection failed message")
            connectionMessageIsError = true
            return false
        }

        return await testConnection(connection, applyOnSuccess: applyOnSuccess)
    }

    @discardableResult
    private func testConnection(_ connection: SyncthingConnectionConfig, applyOnSuccess: Bool) async -> Bool {
        isTestingConnection = true
        defer { isTestingConnection = false }

        do {
            try await apiClient.testConnection(connection)
            if applyOnSuccess {
                applyConnection(connection)
                settingsStore.connectionMode = draft.connectionMode
            }
            connectionMessage = draft.connectionMode == .automatic
                ? String.localizedStringWithFormat(
                    NSLocalizedString("settings.connection.detected", comment: "Detected Syncthing API address"),
                    connection.apiAddress
                )
                : NSLocalizedString("settings.connection.success", comment: "Syncthing connection succeeded message")
            connectionMessageIsError = false
            return true
        } catch {
            connectionMessage = NSLocalizedString("settings.connection.failed", comment: "Syncthing connection failed message")
            connectionMessageIsError = true
            return false
        }
    }

    private func showSupportProjectWindow() {
        if let supportProjectWindow {
            supportProjectWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("support.window.title", comment: "Support project window title")
        window.contentView = NSHostingView(rootView: SupportProjectView(appVersionText: appVersionText))
        window.center()
        window.isReleasedWhenClosed = false
        supportProjectWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsDraft: Equatable {
    var connectionMode: SyncthingConnectionMode
    var apiAddress: String
    var apiKey: String
    var iconTheme: IconTheme
    var operatingMode: OperatingMode
    var referenceDeviceID: String
    var launchAtLogin: Bool

    init(
        connectionMode: SyncthingConnectionMode = .automatic,
        apiAddress: String = "",
        apiKey: String = "",
        iconTheme: IconTheme = .automatic,
        operatingMode: OperatingMode = .distributed,
        referenceDeviceID: String = "",
        launchAtLogin: Bool = false
    ) {
        self.connectionMode = connectionMode
        self.apiAddress = apiAddress
        self.apiKey = apiKey
        self.iconTheme = iconTheme
        self.operatingMode = operatingMode
        self.referenceDeviceID = referenceDeviceID
        self.launchAtLogin = launchAtLogin
    }

    init(settingsStore: SettingsStore) {
        self.connectionMode = settingsStore.connectionMode
        self.apiAddress = settingsStore.activeConnectionConfig.apiAddress
        self.apiKey = settingsStore.apiKey
        self.iconTheme = settingsStore.iconTheme
        self.operatingMode = settingsStore.operatingMode
        self.referenceDeviceID = settingsStore.referenceDeviceID
        self.launchAtLogin = settingsStore.launchAtLogin
    }

    var manualConnectionConfig: SyncthingConnectionConfig? {
        let trimmedAddress = apiAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAddress = trimmedAddress.contains("://") ? trimmedAddress : "http://\(trimmedAddress)"
        guard let url = URL(string: normalizedAddress),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }

        return SyncthingConnectionConfig(
            host: host,
            port: url.port.map(String.init) ?? (url.scheme == "https" ? "8384" : "8384"),
            apiKey: apiKey,
            usesTLS: url.scheme == "https"
        )
    }
}
