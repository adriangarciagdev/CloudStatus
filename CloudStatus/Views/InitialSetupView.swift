import SwiftUI

struct InitialSetupView: View {
    @ObservedObject var viewModel: StatusViewModel

    @State private var selectedMode: OperatingMode?
    @State private var selectedServerID = ""
    @State private var step: InitialSetupStep = .viewMode

    let onComplete: (OperatingMode, String) -> Void

    private var availableServers: [DeviceInfo] {
        viewModel.devices.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            switch step {
            case .viewMode:
                viewModeStep
            case .serverSelection:
                serverSelectionStep
            }

            HStack {
                Spacer()

                Button(NSLocalizedString("initialSetup.continue", comment: "Initial setup continue button")) {
                    continueSetup()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(continueIsDisabled)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onChange(of: availableServers.map(\.deviceID)) { _ in
            updateAutomaticServerSelection()
        }
        .onAppear {
            NSLog("[CloudStatus][InitialSetup] currentStep=%@ selectedMode=%@", step.debugName, selectedMode?.rawValue ?? "nil")
        }
    }

    private var viewModeStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("initialSetup.title", comment: "Initial setup window title"))
                    .font(.title2.weight(.semibold))

                Text(NSLocalizedString("initialSetup.message", comment: "Initial setup explanatory message"))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("", selection: $selectedMode) {
                setupOption(
                    title: NSLocalizedString("initialSetup.distributed.title", comment: "Distributed mode setup option title"),
                    description: NSLocalizedString("initialSetup.distributed.description", comment: "Distributed mode setup option description")
                )
                .tag(Optional(OperatingMode.distributed))

                setupOption(
                    title: NSLocalizedString("initialSetup.cloud.title", comment: "Cloud mode setup option title"),
                    description: NSLocalizedString("initialSetup.cloud.description", comment: "Cloud mode setup option description")
                )
                .tag(Optional(OperatingMode.referenceDevice))
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
    }

    private var serverSelectionStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("initialSetup.cloud.title", comment: "Cloud mode setup option title"))
                    .font(.title2.weight(.semibold))

                Text(NSLocalizedString("initialSetup.server.message", comment: "Initial setup server selection message"))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if availableServers.isEmpty {
                Text(NSLocalizedString("initialSetup.server.empty", comment: "Initial setup empty server list message"))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker(NSLocalizedString("settings.reference.server", comment: "Cloud mode server picker label"), selection: $selectedServerID) {
                    if availableServers.count > 1 && selectedServerID.isEmpty {
                        Text(NSLocalizedString("settings.reference.selectDevice", comment: "Reference device picker placeholder")).tag("")
                    }

                    ForEach(availableServers) { device in
                        Text(device.displayName).tag(device.deviceID)
                    }
                }
            }
        }
        .onAppear {
            updateAutomaticServerSelection()
        }
    }

    private var continueIsDisabled: Bool {
        switch step {
        case .viewMode:
            return selectedMode == nil
        case .serverSelection:
            return selectedServerID.isEmpty || !availableServers.contains { $0.deviceID == selectedServerID }
        }
    }

    private func continueSetup() {
        switch step {
        case .viewMode:
            guard let selectedMode else { return }
            NSLog("[CloudStatus][InitialSetup] selectedMode=%@", selectedMode.rawValue)

            if selectedMode == .referenceDevice {
                step = .serverSelection
                NSLog("[CloudStatus][InitialSetup] currentStep=serverSelection availableServers=%ld", availableServers.count)
                updateAutomaticServerSelection()
                Task { await viewModel.refresh() }
            } else {
                onComplete(.distributed, "")
            }
        case .serverSelection:
            guard !continueIsDisabled else { return }
            NSLog("[CloudStatus][InitialSetup] completing cloud setup serverID=%@", selectedServerID)
            onComplete(.referenceDevice, selectedServerID)
        }
    }

    private func updateAutomaticServerSelection() {
        NSLog("[CloudStatus][InitialSetup] currentStep=%@ availableServers=%ld", step.debugName, availableServers.count)

        if availableServers.count == 1 {
            selectedServerID = availableServers[0].deviceID
        } else if !selectedServerID.isEmpty && !availableServers.contains(where: { $0.deviceID == selectedServerID }) {
            selectedServerID = ""
        }
    }

    private func setupOption(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body)

            Text(description)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private enum InitialSetupStep {
    case viewMode
    case serverSelection

    var debugName: String {
        switch self {
        case .viewMode:
            return "viewMode"
        case .serverSelection:
            return "serverSelection"
        }
    }
}
