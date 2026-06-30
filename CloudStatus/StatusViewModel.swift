import AppKit
import Combine
import Foundation

@MainActor
final class StatusViewModel: ObservableObject {
    @Published private(set) var state: SyncState = .connectionError
    @Published private(set) var menuBarState: SyncState = .connectionError
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isChangingPauseState = false
    @Published private(set) var isScanning = false
    @Published private(set) var recentActivity: [RecentActivityItem]
    @Published private(set) var devices: [DeviceInfo] = []

    let settingsStore: SettingsStore

    private let apiClient: SyncthingAPIClient
    private var refreshTask: Task<Void, Never>?
    private var activityTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var lastEventID = 0
    private var lastActivityEndpointKey: String?
    private var remoteDownloadProgressByDeviceID: [String: Date] = [:]
    private var previousDistributedConnectionSnapshots: [String: DeviceConnectionSnapshot] = [:]
    private let activityLimit = 20
    private let remoteDownloadProgressWindow: TimeInterval = 30

    var displayedState: SyncState {
        guard settingsStore.operatingMode == .referenceDevice else {
            return state
        }

        return isReferenceDeviceConnected ? .updated : .connectionError
    }

    var displayedTitle: String {
        switch settingsStore.operatingMode {
        case .distributed:
            switch menuBarState {
            case .updated:
                return NSLocalizedString("status.distributed.updated", comment: "Distributed mode synced status title")
            case .syncing:
                return NSLocalizedString("status.distributed.syncing", comment: "Distributed mode syncing status title")
            case .attention:
                return NSLocalizedString("status.distributed.attention", comment: "Distributed mode attention status title")
            case .paused:
                return NSLocalizedString("status.paused", comment: "Synchronization paused status title")
            case .connectionError:
                return NSLocalizedString("status.distributed.connectionError", comment: "Distributed mode connection error status title")
            }
        case .referenceDevice:
            switch menuBarState {
            case .updated:
                return NSLocalizedString("status.cloud.updated", comment: "Cloud mode synced status title")
            case .syncing:
                return NSLocalizedString("status.cloud.syncing", comment: "Cloud mode syncing status title")
            case .attention:
                return NSLocalizedString("status.cloud.attention", comment: "Cloud mode attention status title")
            case .paused:
                return NSLocalizedString("status.paused", comment: "Synchronization paused status title")
            case .connectionError:
                return NSLocalizedString("status.cloud.connectionError", comment: "Cloud mode connection error status title")
            }
        }
    }

    private var isReferenceDeviceConnected: Bool {
        let referenceDeviceID = settingsStore.referenceDeviceID
        guard !referenceDeviceID.isEmpty else { return false }

        return devices.first { $0.deviceID == referenceDeviceID }?.isConnected == true
    }

    init(settingsStore: SettingsStore, apiClient: SyncthingAPIClient) {
        self.settingsStore = settingsStore
        self.apiClient = apiClient
        self.recentActivity = Self.loadRecentActivity(for: settingsStore)

        settingsStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func start() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }

        startActivityListener()
    }

    func refresh() async {
        Self.debugLog("refresh START mode=\(settingsStore.operatingMode.rawValue)")

        let connection = await resolvedConnectionConfig()

        guard settingsStore.isConfigured else {
            Self.debugLog("refresh not configured; clearing devices and recent RemoteDownloadProgress")
            state = .connectionError
            menuBarState = .connectionError
            lastUpdated = nil
            devices = []
            remoteDownloadProgressByDeviceID = [:]
            previousDistributedConnectionSnapshots = [:]
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            state = try await apiClient.fetchGlobalState(
                connection: connection
            )
            lastUpdated = Date()
            Self.debugLog("refresh globalState=\(state.rawValue)")
        } catch {
            Self.debugLog("refresh globalState error=\(error); clearing devices")
            state = .connectionError
            menuBarState = .connectionError
            lastUpdated = Date()
            devices = []
            previousDistributedConnectionSnapshots = [:]
            return
        }

        do {
            let downloadingDeviceIDs = recentDownloadingDeviceIDs()
            Self.debugLog("refresh devices calling fetchDistributedDevices mode=\(settingsStore.operatingMode.rawValue) recentDownloadingDeviceIDs=\(Self.debugDeviceIDs(downloadingDeviceIDs)) previousConnectionSnapshots=\(previousDistributedConnectionSnapshots.count) localIsSyncing=\(state == .syncing)")
            let result = try await apiClient.fetchDistributedDevices(
                connection: connection,
                downloadingDeviceIDs: downloadingDeviceIDs,
                previousConnectionSnapshots: previousDistributedConnectionSnapshots,
                localIsSyncing: state == .syncing
            )
            devices = result.devices
            previousDistributedConnectionSnapshots = result.connectionSnapshots
            Self.debugLog("refresh devices storedConnectionSnapshots=\(previousDistributedConnectionSnapshots.count)")
            Self.debugLog("refresh devices mode=\(settingsStore.operatingMode.rawValue) devices=\(devices.map { "\($0.displayName)|\($0.deviceID)|\($0.syncStatus.debugName)" }.joined(separator: ", "))")
        } catch {
            Self.debugLog("refresh devices error=\(error); clearing devices")
            devices = []
            previousDistributedConnectionSnapshots = [:]
            menuBarState = .connectionError
            return
        }

        menuBarState = await resolveMenuBarState(from: state)
        Self.debugLog("refresh END menuBarState=\(menuBarState.rawValue)")
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        activityTask?.cancel()
        activityTask = nil
    }

    func toggleSynchronizationPaused() async {
        guard settingsStore.isConfigured,
              menuBarState != .connectionError,
              !isChangingPauseState else { return }

        isChangingPauseState = true
        defer { isChangingPauseState = false }

        do {
            try await apiClient.setAllDevicesPaused(
                menuBarState != .paused,
                connection: settingsStore.activeConnectionConfig
            )
        } catch {
            Self.debugLog("toggle pause error=\(error)")
        }

        await refresh()
    }

    func scanAllFolders() async {
        guard settingsStore.isConfigured,
              menuBarState != .connectionError,
              !isScanning else { return }

        isScanning = true
        defer { isScanning = false }

        do {
            try await apiClient.scanAllFolders(
                connection: settingsStore.activeConnectionConfig
            )
        } catch {
            Self.debugLog("scan all folders error=\(error)")
        }
    }

    func openInFinder(_ item: RecentActivityItem) {
        guard let url = item.fileURL else { return }

        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    private func startActivityListener() {
        activityTask?.cancel()
        activityTask = Task { [weak self] in
            await self?.listenForActivity()
        }
    }

    private func resolveMenuBarState(from state: SyncState) async -> SyncState {
        guard state != .connectionError else { return .connectionError }
        guard state != .paused else { return .paused }

        switch settingsStore.operatingMode {
        case .distributed:
            guard state != .syncing else { return .syncing }

            do {
                return try await apiClient.hasIncompleteConnectedDevice(
                    connection: settingsStore.activeConnectionConfig,
                    devices: devices
                ) ? .attention : .updated
            } catch {
                return .connectionError
            }
        case .referenceDevice:
            guard isReferenceDeviceConnected else { return .attention }
            return state == .syncing ? .syncing : .updated
        }
    }

    private func listenForActivity() async {
        while !Task.isCancelled {
            guard settingsStore.isConfigured else {
                Self.debugLog("events not configured; resetting lastEventID and endpoint key")
                lastEventID = 0
                lastActivityEndpointKey = nil
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                continue
            }

            let connection = await resolvedConnectionConfig()

            let endpointKey = [
                connection.host,
                connection.port,
                connection.scheme,
                settingsStore.operatingMode.rawValue,
                settingsStore.referenceDeviceID
            ].joined(separator: "|")

            do {
                let folders = try await apiClient.fetchFolders(
                    connection: connection
                )
                let foldersByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
                let eventTypes = "RemoteChangeDetected,RemoteDownloadProgress"
                Self.debugLog("events poll setup eventTypes=\(eventTypes) lastEventID=\(lastEventID)")

                if endpointKey != lastActivityEndpointKey {
                    Self.debugLog("events endpoint changed old=\(lastActivityEndpointKey ?? "nil") new=\(endpointKey)")
                    let latestEvents = try await apiClient.fetchEvents(
                        since: 0,
                        connection: connection,
                        eventTypes: eventTypes,
                        limit: 1,
                        timeout: 1
                    )
                    lastEventID = latestEvents.last?.id ?? 0
                    Self.debugLog("events endpoint initialized latestCount=\(latestEvents.count) lastEventID=\(lastEventID)")
                    lastActivityEndpointKey = endpointKey
                    remoteDownloadProgressByDeviceID = [:]
                    Self.debugLog("events cleared recent RemoteDownloadProgress due endpoint change")
                    recentActivity = Self.loadRecentActivity(for: settingsStore)
                }

                Self.debugLog("events polling since=\(lastEventID) eventTypes=\(eventTypes)")
                let events = try await apiClient.fetchEvents(
                    since: lastEventID,
                    connection: connection,
                    eventTypes: eventTypes
                )
                Self.debugLog("events received count=\(events.count) ids=\(events.map { "\($0.id):\($0.type)" }.joined(separator: ","))")

                if let newestID = events.last?.id {
                    lastEventID = newestID
                    Self.debugLog("events updated lastEventID=\(lastEventID)")
                }

                recordRemoteDownloadProgress(from: events)

                let items = events.compactMap {
                    activityItem(
                        from: $0,
                        foldersByID: foldersByID,
                        devices: devices
                    )
                }
                if !items.isEmpty {
                    addActivityItems(items)
                }
            } catch {
                Self.debugLog("events error=\(error); sleeping 5s")
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func recentDownloadingDeviceIDs() -> Set<String> {
        let cutoff = Date().addingTimeInterval(-remoteDownloadProgressWindow)
        let before = remoteDownloadProgressByDeviceID
        remoteDownloadProgressByDeviceID = remoteDownloadProgressByDeviceID.filter { _, date in
            date >= cutoff
        }
        let removed = Set(before.keys).subtracting(remoteDownloadProgressByDeviceID.keys)
        if !removed.isEmpty {
            Self.debugLog("recentDownloadingDeviceIDs prunedExpired=\(Self.debugDeviceIDs(removed)) cutoff=\(Self.debugTimestamp(cutoff))")
        }

        let current = Set(remoteDownloadProgressByDeviceID.keys)
        Self.debugLog("recentDownloadingDeviceIDs current=\(Self.debugDeviceIDs(current))")
        return current
    }

    private func recordRemoteDownloadProgress(from events: [SyncthingEvent]) {
        let now = Date()
        for event in events where event.type == "RemoteDownloadProgress" {
            guard let deviceID = event.data?.device else {
                Self.debugLog("RemoteDownloadProgress ignored id=\(event.id) reason=missing device")
                continue
            }

            Self.debugLog("RemoteDownloadProgress received id=\(event.id) eventTime=\(Self.debugTimestamp(event.time)) device=\(deviceID) folder=\(event.data?.folder ?? "nil") state=\(Self.debugState(event.data?.state))")
            if event.data?.state?.isEmpty == false {
                remoteDownloadProgressByDeviceID[deviceID] = now
                Self.debugLog("RemoteDownloadProgress add recent device=\(deviceID) addedAt=\(Self.debugTimestamp(now)) recentDownloadingDeviceIDs=\(Self.debugDeviceIDs(Set(remoteDownloadProgressByDeviceID.keys)))")
            } else {
                remoteDownloadProgressByDeviceID.removeValue(forKey: deviceID)
                Self.debugLog("RemoteDownloadProgress remove recent device=\(deviceID) reason=empty state recentDownloadingDeviceIDs=\(Self.debugDeviceIDs(Set(remoteDownloadProgressByDeviceID.keys)))")
            }
        }
    }

    private func activityItem(
        from event: SyncthingEvent,
        foldersByID: [String: FolderConfig],
        devices: [DeviceInfo]
    ) -> RecentActivityItem? {
        guard let data = event.data,
              data.type == "file" else {
            return nil
        }

        guard event.type == "RemoteChangeDetected" else {
            return nil
        }

        let sourceDeviceName = Self.device(matching: data.modifiedBy, in: devices)?.displayName

        guard let itemPath = data.item ?? data.path,
              let folderID = data.folder ?? data.folderID else {
            return nil
        }

        let action: ActivityAction = Self.activityAction(from: data.action)
        let folder = foldersByID[folderID]
        let fileName = URL(fileURLWithPath: itemPath).lastPathComponent

        return RecentActivityItem(
            fileName: fileName.isEmpty ? itemPath : fileName,
            relativePath: itemPath,
            folderName: data.label ?? (folder?.label?.isEmpty == false ? folder?.label : folderID),
            folderPath: folder?.path,
            date: event.time,
            action: action,
            sourceDeviceID: data.modifiedBy,
            sourceDeviceName: sourceDeviceName
        )
    }

    private func addActivityItems(_ items: [RecentActivityItem]) {
        var merged = items.sorted { $0.date > $1.date } + recentActivity
        var seen = Set<String>()

        merged = merged.filter { item in
            let dedupeBucket = Int(item.date.timeIntervalSince1970 / 8)
            let key = "\(item.folderPath ?? item.folderName ?? "")|\(item.relativePath)|\(item.action.rawValue)|\(item.sourceDeviceID ?? "")|\(dedupeBucket)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }

        recentActivity = Array(merged.prefix(activityLimit))
        persistRecentActivity()
    }

    private static func activityAction(from action: String?) -> ActivityAction {
        guard let action = action?.lowercased() else {
            return .updated
        }

        return action.contains("delete") ? .deleted : .updated
    }

    private static func device(matching candidateID: String?, in devices: [DeviceInfo]) -> DeviceInfo? {
        devices.first { deviceID(candidateID, matches: $0.deviceID) }
    }

    private static func deviceID(_ candidateID: String?, matches fullDeviceID: String) -> Bool {
        guard let candidateID else { return false }

        let normalizedCandidate = candidateID.uppercased()
        let normalizedFullID = fullDeviceID.uppercased()

        return normalizedCandidate == normalizedFullID ||
            normalizedFullID.hasPrefix(normalizedCandidate) ||
            normalizedFullID.replacingOccurrences(of: "-", with: "").hasPrefix(normalizedCandidate)
    }

    private func persistRecentActivity() {
        guard let data = try? JSONEncoder().encode(recentActivity) else { return }
        UserDefaults.standard.set(data, forKey: Self.activityStoreKey(for: settingsStore))
    }

    private static func loadRecentActivity(for settingsStore: SettingsStore) -> [RecentActivityItem] {
        let key = activityStoreKey(for: settingsStore)
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([RecentActivityItem].self, from: data) else {
            return []
        }

        return Array(items.sorted { $0.date > $1.date }.prefix(20))
    }

    private static func activityStoreKey(for settingsStore: SettingsStore) -> String {
        [
            "recentActivityItems.remoteChanges.v1",
            settingsStore.host,
            settingsStore.port,
            settingsStore.activeConnectionConfig.scheme,
            settingsStore.operatingMode.rawValue,
            settingsStore.referenceDeviceID
        ].joined(separator: "|")
    }

    private func resolvedConnectionConfig() async -> SyncthingConnectionConfig {
        guard settingsStore.connectionMode == .automatic,
              let detectedConfig = settingsStore.detectLocalSyncthingConfig() else {
            return settingsStore.activeConnectionConfig
        }

        do {
            try await apiClient.testConnection(detectedConfig)
            settingsStore.applyConnectionConfig(detectedConfig)
            return detectedConfig
        } catch {
            Self.debugLog("automatic config detection failed connection test error=\(error)")
            return settingsStore.activeConnectionConfig
        }
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("[CloudStatus][DevicesDebug][ViewModel] \(debugTimestamp()) \(message)")
        #endif
    }

    private static func debugTimestamp(_ date: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func debugDeviceIDs(_ deviceIDs: Set<String>) -> String {
        deviceIDs.sorted().joined(separator: ",")
    }

    private static func debugState(_ state: [String: Int]?) -> String {
        guard let state else { return "nil" }
        guard !state.isEmpty else { return "[:]" }

        return state
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
    }
}
