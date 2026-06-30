import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let DEBUG_LAYOUT = false

struct MainStatusView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: StatusViewModel
    let openWebUI: () -> Void
    let openSettings: () -> Void
    let quitApp: () -> Void

    @State private var selectedPanel: MainPanel = .activity
    @State private var isStatusHeaderHovered = false

    private enum DistributedLayout {
        static let activityVisibleRows = 4
        static let activityRowHeight: CGFloat = 49
        static let deviceMinRows = 2
        static let deviceMaxRows = 4
        static let deviceRowHeight: CGFloat = 42
        static let rowSpacing: CGFloat = 5
        static let sectionTitleHeight: CGFloat = 16
        static let sectionTitleSpacing: CGFloat = 5
        static let scrollVerticalPadding: CGFloat = 2
        static let compactWindowHeight: CGFloat = 500

        static func sectionHeight(rowHeight: CGFloat, visibleRows: Int) -> CGFloat {
            sectionTitleHeight +
                sectionTitleSpacing +
                scrollVerticalPadding +
                CGFloat(visibleRows) * rowHeight +
                CGFloat(max(visibleRows - 1, 0)) * rowSpacing
        }
    }

    private var lastUpdatedText: String {
        guard let lastUpdated = viewModel.lastUpdated else {
            return NSLocalizedString("main.lastUpdated.none", comment: "No last update available")
        }

        return lastUpdated.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            statusHeader

            Divider()

            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack(alignment: .center, spacing: 10) {
                Button(NSLocalizedString("main.openWebUI", comment: "Open Syncthing Web UI button"), action: openWebUI)
                    .buttonStyle(.borderedProminent)

                Button(NSLocalizedString("main.settings", comment: "Open settings button"), action: openSettings)
                    .buttonStyle(.bordered)

                Spacer(minLength: 8)

                Button(NSLocalizedString("main.quit", comment: "Quit application button"), action: quitApp)
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 360, height: windowHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.settingsStore.operatingMode {
        case .distributed:
            VStack(alignment: .leading, spacing: 9) {
                RecentActivitySection(
                    viewModel: viewModel,
                    rowHeight: DistributedLayout.activityRowHeight
                )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: distributedActivityHeight)

                DevicesSection(
                    devices: viewModel.devices,
                    usesDistributedStatus: true,
                    rowHeight: DistributedLayout.deviceRowHeight
                )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: distributedDevicesHeight)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        case .referenceDevice:
            referenceDeviceContent
        }
    }

    private var referenceDeviceContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            Picker("", selection: $selectedPanel) {
                ForEach(MainPanel.allCases) { panel in
                    Text(panel.title).tag(panel)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch selectedPanel {
                case .activity:
                    RecentActivitySection(viewModel: viewModel)
                case .devices:
                    DevicesSection(
                        devices: referenceModeDevices,
                        referenceDeviceID: viewModel.settingsStore.referenceDeviceID,
                        usesDistributedStatus: false,
                        showsReferenceDivider: true
                    )
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var statusHeader: some View {
        ZStack(alignment: .trailing) {
            HStack(alignment: .center, spacing: 14) {
                IconProvider.panelImage(for: viewModel.menuBarState, colorScheme: colorScheme)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color(viewModel.menuBarState.color))
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(headerTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(String.localizedStringWithFormat(NSLocalizedString("main.lastUpdated", comment: "Last update label"), lastUpdatedText))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 245, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if isStatusHeaderHovered && viewModel.menuBarState != .connectionError {
                QuickActionButton(
                    systemName: viewModel.menuBarState == .paused ? "play.fill" : "pause.fill",
                    tooltip: pauseButtonTooltip,
                    size: 32,
                    isDisabled: viewModel.isChangingPauseState
                ) {
                    Task { await viewModel.toggleSynchronizationPaused() }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onHover { isStatusHeaderHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isStatusHeaderHovered)
        .padding(.top, 0)
        .padding(.bottom, 1)
    }

    private var pauseButtonTooltip: String {
        viewModel.menuBarState == .paused
            ? NSLocalizedString("sync.resume", comment: "Resume all devices tooltip")
            : NSLocalizedString("sync.pause", comment: "Pause all devices tooltip")
    }

    private var headerTitle: String {
        switch viewModel.settingsStore.operatingMode {
        case .distributed:
            switch viewModel.menuBarState {
            case .updated:
                return NSLocalizedString("status.header.distributed.updated", comment: "Distributed panel synced status title")
            case .paused:
                return NSLocalizedString("status.header.paused", comment: "Synchronization paused header title")
            case .syncing:
                return NSLocalizedString("status.header.distributed.syncing", comment: "Distributed panel syncing status title")
            case .attention:
                return NSLocalizedString("status.header.distributed.attention", comment: "Distributed panel attention status title")
            case .connectionError:
                return viewModel.displayedTitle
            }
        case .referenceDevice:
            switch viewModel.menuBarState {
            case .updated:
                return NSLocalizedString("status.header.cloud.updated", comment: "Cloud panel synced status title")
            case .paused:
                return NSLocalizedString("status.header.paused", comment: "Synchronization paused header title")
            case .syncing:
                return NSLocalizedString("status.header.cloud.syncing", comment: "Cloud panel syncing status title")
            case .attention:
                return NSLocalizedString("status.header.cloud.attention", comment: "Cloud panel attention status title")
            case .connectionError:
                return viewModel.displayedTitle
            }
        }
    }

    private var referenceModeDevices: [DeviceInfo] {
        let referenceDeviceID = viewModel.settingsStore.referenceDeviceID
        guard !referenceDeviceID.isEmpty else {
            return viewModel.devices
        }

        let referenceDevices = viewModel.devices.filter { $0.deviceID == referenceDeviceID }
        let otherDevices = viewModel.devices.filter { $0.deviceID != referenceDeviceID }

        guard !referenceDevices.isEmpty else {
            return otherDevices
        }

        return referenceDevices + otherDevices
    }

    private var distributedDevicesHeight: CGFloat {
        return DistributedLayout.sectionHeight(
            rowHeight: DistributedLayout.deviceRowHeight,
            visibleRows: distributedVisibleDeviceRows
        )
    }

    private var distributedVisibleDeviceRows: Int {
        min(
            max(viewModel.devices.count, DistributedLayout.deviceMinRows),
            DistributedLayout.deviceMaxRows
        )
    }

    private var distributedActivityHeight: CGFloat {
        DistributedLayout.sectionHeight(
            rowHeight: DistributedLayout.activityRowHeight,
            visibleRows: DistributedLayout.activityVisibleRows
        )
    }

    private var windowHeight: CGFloat {
        guard viewModel.settingsStore.operatingMode == .distributed else {
            return DistributedLayout.compactWindowHeight
        }

        let extraDeviceRows = max(0, distributedVisibleDeviceRows - DistributedLayout.deviceMinRows)
        let extraDeviceHeight = CGFloat(extraDeviceRows) *
            (DistributedLayout.deviceRowHeight + DistributedLayout.rowSpacing)

        return DistributedLayout.compactWindowHeight + extraDeviceHeight
    }
}

private enum MainPanel: String, CaseIterable, Identifiable {
    case activity
    case devices

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity:
            return NSLocalizedString("activity.panel", comment: "Activity segmented control title")
        case .devices:
            return NSLocalizedString("devices.section", comment: "Devices segmented control title")
        }
    }
}

private struct RecentActivitySection: View {
    @ObservedObject var viewModel: StatusViewModel
    var rowHeight: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 4) {
                HStack(alignment: .center, spacing: 4) {
                    Text(sectionTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)

                    InfoPopoverButton(message: activityInfoMessage)
                        .frame(width: 16, height: 16)
                }

                Spacer(minLength: 8)

                QuickActionButton(
                    systemName: "arrow.clockwise",
                    tooltip: NSLocalizedString("activity.scan", comment: "Scan all folders tooltip"),
                    size: 24,
                    iconSize: 13.5,
                    isDisabled: viewModel.menuBarState == .connectionError || viewModel.isScanning
                ) {
                    Task { await viewModel.scanAllFolders() }
                }
            }
            .frame(height: 16)

            if viewModel.recentActivity.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(viewModel.recentActivity) { item in
                            ActivityRow(item: item) {
                                viewModel.openInFinder(item)
                            }
                            .frame(height: rowHeight)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private var sectionTitle: String {
        switch viewModel.settingsStore.operatingMode {
        case .distributed:
            return NSLocalizedString("activity.distributed", comment: "Distributed activity section title")
        case .referenceDevice:
            return NSLocalizedString("activity.cloud", comment: "Cloud activity section title")
        }
    }

    private var activityInfoMessage: String {
        NSLocalizedString(
            "activity.distributed.info",
            comment: "Explanation shown next to the distributed activity title"
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 28))
                .foregroundColor(.secondary)

            Text(NSLocalizedString("activity.empty.title", comment: "Empty activity title"))
                .font(.system(size: 13, weight: .medium))

            Text(NSLocalizedString("activity.empty.message", comment: "Empty activity message"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InfoPopoverButton: NSViewRepresentable {
    let message: String

    func makeCoordinator() -> Coordinator {
        Coordinator(message: message)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: "info.circle",
            accessibilityDescription: NSLocalizedString(
                "activity.distributed.info.accessibility",
                comment: "Incoming changes info button accessibility label"
            )
        )
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.togglePopover(_:))
        button.setButtonType(.momentaryPushIn)
        button.toolTip = NSLocalizedString(
            "activity.distributed.info.accessibility",
            comment: "Incoming changes info button tooltip"
        )
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.message = message
    }

    final class Coordinator: NSObject {
        weak var button: NSButton?
        var message: String
        private var popover: NSPopover?

        init(message: String) {
            self.message = message
        }

        @objc func togglePopover(_ sender: NSButton) {
            if let popover, popover.isShown {
                popover.performClose(sender)
                return
            }

            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = NSHostingController(rootView: InfoPopoverContent(message: message))
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
            self.popover = popover
        }
    }
}

private struct InfoPopoverContent: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundColor(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 280, alignment: .leading)
            .padding(12)
    }
}

private struct QuickActionButton: View {
    let systemName: String
    let tooltip: String
    let size: CGFloat
    var iconSize: CGFloat? = nil
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.10 : 0))

                Image(systemName: systemName)
                    .font(.system(size: iconSize ?? size * 0.48, weight: .semibold))
                    .id(systemName)
                    .transition(.opacity)
            }
            .frame(width: size, height: size)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(QuickActionButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .help(tooltip)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.16), value: systemName)
    }
}

private struct QuickActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct DevicesSection: View {
    let devices: [DeviceInfo]
    var referenceDeviceID: String?
    var usesDistributedStatus = false
    var rowHeight: CGFloat? = nil
    var showsReferenceDivider = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(NSLocalizedString("devices.section", comment: "Devices section title"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            if devices.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                            if showsReferenceDivider,
                               index == 1,
                               referenceDeviceID != nil,
                               devices.first?.deviceID == referenceDeviceID {
                                Divider()
                                    .opacity(0.45)
                                    .padding(.leading, 43)
                                    .padding(.trailing, 8)
                            }

                            DeviceRow(
                                device: device,
                                isReference: device.deviceID == referenceDeviceID,
                                usesDistributedStatus: usesDistributedStatus,
                                rowHeight: rowHeight
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.vertical, 1)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 28))
                .foregroundColor(.secondary)

            Text(NSLocalizedString("devices.empty.title", comment: "Empty devices title"))
                .font(.system(size: 13, weight: .medium))

            Text(NSLocalizedString("devices.empty.message", comment: "Empty devices message"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DeviceRow: View {
    private static let sharedFoldersPopoverDelayNanoseconds: UInt64 = 400_000_000
    private static let stuckFilesDisplayLimit = 5

    let device: DeviceInfo
    let isReference: Bool
    let usesDistributedStatus: Bool
    let rowHeight: CGFloat?

    @State private var isPopoverPresented = false
    @State private var popoverPresentationTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 11) {
            HStack(spacing: 11) {
                Image(systemName: statusSymbolName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(statusColor)
                    .frame(width: 24, height: 24)

                Text(displayName)
                    .font(.system(size: 13, weight: isReference ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)
                .debugLayoutBorder(.yellow)

            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 85, alignment: .leading)
                .layoutPriority(1)
                .debugLayoutBorder(.blue)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .onHover { hovering in
            popoverPresentationTask?.cancel()

            if hovering {
                popoverPresentationTask = Task {
                    try? await Task.sleep(
                        nanoseconds: Self.sharedFoldersPopoverDelayNanoseconds
                    )
                    guard !Task.isCancelled else { return }
                    isPopoverPresented = true
                }
            } else {
                popoverPresentationTask = nil
                isPopoverPresented = false
            }

            #if DEBUG
            print("[CloudStatus][DeviceHover] \(device.displayName) \(hovering ? "entered" : "exited")")
            #endif
        }
        .popover(
            isPresented: $isPopoverPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .trailing
        ) {
            sharedFoldersPopover
        }
        .onDisappear {
            popoverPresentationTask?.cancel()
            popoverPresentationTask = nil
        }
        .debugLayoutBorder(.red)
    }

    private var sharedFoldersHeading: String {
        let count = device.sharedFolders.count
        let countKey = count == 1 ? "device.sharedFolders.one" : "device.sharedFolders.other"
        return String.localizedStringWithFormat(
            NSLocalizedString(countKey, comment: "Number of folders shared with a device"),
            count
        )
    }

    private var sharedFoldersPopover: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(sharedFoldersHeading)
                .font(.system(size: 12, weight: .semibold))

            if !device.sharedFolders.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(device.sharedFolders.enumerated()), id: \.offset) { _, folder in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            if let state = folder.state {
                                Text(state.symbol)
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 12, alignment: .center)
                            }

                            Text(sharedFolderDisplayName(folder))
                                .font(.system(size: 12))
                                .lineLimit(hasDetailedSyncIssues ? 2 : 1)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: popoverContentWidth, alignment: .leading)
            }

            if showsPendingSyncCounts {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    if let counts = device.pendingSyncCounts, counts.items > 0 {
                        Text(pendingItemsText(counts.items))
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let counts = device.pendingSyncCounts, counts.deletions > 0 {
                        Text(pendingDeletionsText(counts.deletions))
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: popoverContentWidth, alignment: .leading)
            }

            if showsStuckFiles {
                Divider()

                Text(NSLocalizedString("device.stuckFiles.heading", comment: "Stuck files heading"))
                    .font(.system(size: 12, weight: .semibold))

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(device.stuckFiles.prefix(Self.stuckFilesDisplayLimit).enumerated()), id: \.offset) { _, file in
                        Text("• \(file.path) — \(file.reason)")
                            .font(.system(size: 12))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if remainingStuckFilesCount > 0 {
                        Text(
                            String.localizedStringWithFormat(
                                NSLocalizedString("device.stuckFiles.more", comment: "Additional stuck files count"),
                                String(remainingStuckFilesCount)
                            )
                        )
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: popoverContentWidth, alignment: .leading)
            }
        }
        .padding(10)
        .frame(width: hasDetailedSyncIssues ? popoverContentWidth : nil, alignment: .leading)
        .fixedSize(horizontal: !hasDetailedSyncIssues, vertical: true)
    }

    private var showsStuckFiles: Bool {
        usesDistributedStatus &&
            device.syncStatus == .needsSyncing &&
            !device.stuckFiles.isEmpty
    }

    private var hasDetailedSyncIssues: Bool {
        showsPendingSyncCounts || showsStuckFiles
    }

    private var popoverContentWidth: CGFloat {
        hasDetailedSyncIssues ? 460 : 260
    }

    private func sharedFolderDisplayName(_ folder: SharedFolderInfo) -> String {
        guard folder.state == .syncing,
              let completion = folder.syncCompletion,
              completion.isFinite,
              (0...100).contains(completion) else {
            return folder.name
        }

        return "\(folder.name) \(Int(completion.rounded()))%"
    }

    private var showsPendingSyncCounts: Bool {
        guard usesDistributedStatus,
              device.syncStatus == .needsSyncing,
              let counts = device.pendingSyncCounts else {
            return false
        }

        return counts.items > 0 || counts.deletions > 0
    }

    private func pendingItemsText(_ count: Int) -> String {
        let key = count == 1 ? "device.pendingItems.one" : "device.pendingItems.other"
        return String.localizedStringWithFormat(
            NSLocalizedString(key, comment: "Pending item count"),
            localizedCount(count)
        )
    }

    private func pendingDeletionsText(_ count: Int) -> String {
        let key = count == 1 ? "device.pendingDeletions.one" : "device.pendingDeletions.other"
        return String.localizedStringWithFormat(
            NSLocalizedString(key, comment: "Pending deletion count"),
            localizedCount(count)
        )
    }

    private func localizedCount(_ count: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
    }

    private var remainingStuckFilesCount: Int {
        max(0, device.stuckFiles.count - Self.stuckFilesDisplayLimit)
    }

    private var statusText: String {
        let displayedStatus = device.syncStatus

        let completionKey: String
        switch displayedStatus {
        case .needsSyncing:
            completionKey = "device.status.needsSyncingWithCompletion"
        case .syncing:
            completionKey = "device.status.syncingWithCompletion"
        case .downloadingChanges:
            completionKey = "device.status.downloadingChangesWithCompletion"
        case .syncedWithThisDevice, .connected, .disconnected, .unknownConnected:
            return displayedStatus.localizedTitle
        }

        guard let completion = device.syncCompletion,
              completion.isFinite,
              (0..<100).contains(completion) else {
            return displayedStatus.localizedTitle
        }

        return String.localizedStringWithFormat(
            NSLocalizedString(completionKey, comment: "Active device status with completion percentage"),
            Int(completion.rounded())
        )
    }

    private var displayName: String {
        device.displayName
    }

    private var statusSymbolName: String {
        switch device.syncStatus {
        case .downloadingChanges:
            return "arrow.down.circle.fill"
        case .syncing:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .needsSyncing:
            return "exclamationmark.circle.fill"
        case .syncedWithThisDevice, .connected, .unknownConnected:
            return "checkmark.circle.fill"
        case .disconnected:
            return "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch device.syncStatus {
        case .downloadingChanges:
            return .blue
        case .syncing:
            return .blue
        case .needsSyncing:
            return .orange
        case .syncedWithThisDevice, .connected, .unknownConnected:
            return .green
        case .disconnected:
            return .secondary
        }
    }
}

private struct ActivityRow: View {
    let item: RecentActivityItem
    let openInFinder: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 11) {
            FileIconView(item: item)
                .frame(width: 39, height: 39)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                TimelineView(.periodic(from: Date(), by: 15)) { context in
                    Text(subtitle(relativeTo: context.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if item.fileURL != nil {
                Button(action: openInFinder) {
                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                .opacity(isHovering ? 0.9 : 0)
                .help(NSLocalizedString("activity.showInFinder", comment: "Show activity item in Finder help text"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovering ? Color(NSColor.controlAccentColor).opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .current
        formatter.unitsStyle = .full
        return formatter
    }()

    private func subtitle(relativeTo date: Date) -> String {
        let relativeTime = Self.relativeFormatter.localizedString(for: item.date, relativeTo: date)

        switch item.action {
        case .updated:
            if let source = item.sourceDisplayName {
                let format = NSLocalizedString("activity.source.updated", comment: "Updated activity subtitle with source")
                return String.localizedStringWithFormat(format, source, relativeTime)
            }

            let format = NSLocalizedString("activity.updated", comment: "Updated activity subtitle")
            return String.localizedStringWithFormat(format, relativeTime)
        case .deleted:
            if let source = item.sourceDisplayName {
                let format = NSLocalizedString("activity.source.deleted", comment: "Deleted activity subtitle with source")
                return String.localizedStringWithFormat(format, source, relativeTime)
            }

            let format = NSLocalizedString("activity.deleted", comment: "Deleted activity subtitle")
            return String.localizedStringWithFormat(format, relativeTime)
        }
    }
}

private struct FileIconView: View {
    let item: RecentActivityItem

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: Self.icon(for: item))
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)

            if item.action == .deleted {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .overlay(
                        Circle()
                            .stroke(Color(NSColor.windowBackgroundColor), lineWidth: 1)
                    )
                    .offset(x: -2, y: -2)
            }
        }
    }

    private static func icon(for item: RecentActivityItem) -> NSImage {
        if let url = item.fileURL, FileManager.default.fileExists(atPath: url.path) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        let fileExtension = (item.fileName as NSString).pathExtension
        if let type = UTType(filenameExtension: fileExtension) {
            return NSWorkspace.shared.icon(for: type)
        }

        return NSWorkspace.shared.icon(for: .data)
    }
}

private extension View {
    @ViewBuilder
    func debugLayoutBorder(_ color: Color) -> some View {
        if DEBUG_LAYOUT {
            overlay(
                Rectangle()
                    .stroke(color.opacity(0.75), lineWidth: 1)
            )
        } else {
            self
        }
    }
}
