import Foundation

final class SyncthingAPIClient {
    enum APIError: Error {
        case invalidURL
        case invalidResponse
    }

    func testConnection(_ connection: SyncthingConnectionConfig) async throws {
        _ = try await requestSystemStatus(connection: connection)
    }

    func fetchGlobalState(connection: SyncthingConnectionConfig) async throws -> SyncState {
        async let folderConfigs = fetchFolders(connection: connection)
        async let deviceConfigs: [DeviceConfig] = request(
            path: "/rest/config/devices",
            connection: connection
        )

        let (folders, devices) = try await (folderConfigs, deviceConfigs)

        if !devices.isEmpty, devices.allSatisfy({ $0.paused == true }) {
            return .paused
        }

        guard !folders.isEmpty else {
            _ = try await requestSystemStatus(connection: connection)
            return .updated
        }

        for folder in folders where folder.paused != true {
            let status: FolderStatus = try await request(
                path: "/rest/db/status?folder=\(urlEncoded(folder.id))",
                connection: connection
            )

            if status.state != "idle" {
                return .syncing
            }
        }

        return .updated
    }

    func setAllDevicesPaused(_ paused: Bool, connection: SyncthingConnectionConfig) async throws {
        try await requestWithoutResponse(
            path: paused ? "/rest/system/pause" : "/rest/system/resume",
            method: "POST",
            connection: connection
        )
    }

    func scanAllFolders(connection: SyncthingConnectionConfig) async throws {
        try await requestWithoutResponse(
            path: "/rest/db/scan",
            method: "POST",
            connection: connection
        )
    }

    func fetchFolders(connection: SyncthingConnectionConfig) async throws -> [FolderConfig] {
        try await request(
            path: "/rest/config/folders",
            connection: connection
        )
    }

    func fetchDevices(connection: SyncthingConnectionConfig) async throws -> [DeviceInfo] {
        async let deviceConfigs: [DeviceConfig] = request(
            path: "/rest/config/devices",
            connection: connection
        )
        async let connections: SyncthingConnectionsResponse = request(
            path: "/rest/system/connections",
            connection: connection
        )
        async let folderConfigs: [FolderConfig] = fetchFolders(connection: connection)
        async let systemStatus = requestSystemStatus(connection: connection)

        let (configs, connectionStatus, folders, localDeviceID) = try await (
            deviceConfigs,
            connections,
            folderConfigs,
            systemStatus.myID
        )
        let remoteConfigs = Self.remoteConfigs(from: configs, localDeviceID: localDeviceID)
        let activeFolders = folders.filter { $0.paused != true }
        let errorsByFolderID = await fetchFolderErrors(
            for: activeFolders,
            connection: connection
        )

        var devices: [DeviceInfo] = []
        for config in remoteConfigs {
            let isConnected = connectionStatus.connections[config.deviceID]?.connected == true
            let folderChecks = await checkedSharedFolders(
                for: config.deviceID,
                isConnected: isConnected,
                folders: folders,
                isActivelySyncing: false,
                connection: connection
            )
            let sharedFolders = folderChecks.map(\.info)
            devices.append(
                DeviceInfo(
                    deviceID: config.deviceID,
                    name: config.name ?? "",
                    isConnected: isConnected,
                    sharedFolders: sharedFolders,
                    stuckFiles: stuckFiles(
                        sharedWith: config.deviceID,
                        folders: activeFolders,
                        errorsByFolderID: errorsByFolderID
                    ),
                    pendingSyncCounts: pendingSyncCounts(from: folderChecks),
                    syncCompletion: syncCompletion(from: folderChecks)
                )
            )
        }

        return devices
            .sorted { left, right in
                left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
            }
    }

    func fetchDistributedDevices(
        connection: SyncthingConnectionConfig,
        downloadingDeviceIDs: Set<String>,
        previousConnectionSnapshots: [String: DeviceConnectionSnapshot],
        localIsSyncing: Bool
    ) async throws -> DistributedDevicesResult {
        Self.debugLog("fetchDistributedDevices START downloadingDeviceIDs=\(Self.debugDeviceIDs(downloadingDeviceIDs)) previousSnapshots=\(previousConnectionSnapshots.count) localIsSyncing=\(localIsSyncing)")

        async let deviceConfigs: [DeviceConfig] = request(
            path: "/rest/config/devices",
            connection: connection
        )
        async let connections: SyncthingConnectionsResponse = request(
            path: "/rest/system/connections",
            connection: connection
        )
        async let folderConfigs: [FolderConfig] = fetchFolders(connection: connection)
        async let systemStatus = requestSystemStatus(connection: connection)

        let (configs, connectionStatus, folders, localDeviceID) = try await (
            deviceConfigs,
            connections,
            folderConfigs,
            systemStatus.myID
        )
        let remoteConfigs = Self.remoteConfigs(from: configs, localDeviceID: localDeviceID)
        let activeFolders = folders.filter { $0.paused != true }
        let errorsByFolderID = await fetchFolderErrors(
            for: activeFolders,
            connection: connection
        )
        Self.debugLog("fetchDistributedDevices loaded devices=\(configs.count) remoteDevices=\(remoteConfigs.count) folders=\(folders.count) activeFolders=\(activeFolders.count)")
        let connectionSnapshots = Self.connectionSnapshots(from: connectionStatus)
        let syncingDeviceIDs = Self.syncingDeviceIDs(
            configs: remoteConfigs,
            connections: connectionStatus.connections,
            currentSnapshots: connectionSnapshots,
            previousSnapshots: previousConnectionSnapshots,
            localIsSyncing: localIsSyncing
        )
        Self.debugLog("fetchDistributedDevices syncingDeviceIDs=\(Self.debugDeviceIDs(syncingDeviceIDs)) threshold=\(Self.connectionDeltaThresholdBytes)B")

        var devices: [DeviceInfo] = []
        for config in remoteConfigs {
            let isConnected = connectionStatus.connections[config.deviceID]?.connected == true
            Self.debugLog("device process name=\(config.name ?? "") id=\(config.deviceID) connected=\(isConnected) inRecentDownloadingIDs=\(downloadingDeviceIDs.contains(config.deviceID)) inSyncingIDs=\(syncingDeviceIDs.contains(config.deviceID))")

            let folderChecks = await checkedSharedFolders(
                for: config.deviceID,
                isConnected: isConnected,
                folders: activeFolders,
                isActivelySyncing: downloadingDeviceIDs.contains(config.deviceID) || syncingDeviceIDs.contains(config.deviceID),
                connection: connection
            )
            let status = distributedStatus(
                for: config.deviceID,
                isConnected: isConnected,
                folderChecks: folderChecks,
                downloadingDeviceIDs: downloadingDeviceIDs,
                syncingDeviceIDs: syncingDeviceIDs
            )
            let pausedSharedFolders = folders
                .filter { $0.paused == true && $0.devices?.contains { $0.deviceID == config.deviceID } == true }
                .map { folder in
                    let label = folder.label?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return SharedFolderInfo(
                        name: label?.isEmpty == false ? label! : folder.id,
                        state: .attention
                    )
                }
            let sharedFolders = (folderChecks.map(\.info) + pausedSharedFolders).sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            Self.debugLog("device final name=\(config.name ?? "") id=\(config.deviceID) status=\(status.debugName)")

            devices.append(
                DeviceInfo(
                    deviceID: config.deviceID,
                    name: config.name ?? "",
                    isConnected: isConnected,
                    syncStatus: status,
                    sharedFolders: sharedFolders,
                    stuckFiles: stuckFiles(
                        sharedWith: config.deviceID,
                        folders: activeFolders,
                        errorsByFolderID: errorsByFolderID
                    ),
                    pendingSyncCounts: pendingSyncCounts(from: folderChecks),
                    syncCompletion: syncCompletion(from: folderChecks)
                )
            )
        }

        let sortedDevices = devices.sorted { left, right in
            if left.syncStatus.distributedSortRank != right.syncStatus.distributedSortRank {
                return left.syncStatus.distributedSortRank < right.syncStatus.distributedSortRank
            }

            return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
        }
        Self.debugLog("fetchDistributedDevices END sorted=\(sortedDevices.map { "\($0.displayName):\($0.syncStatus.debugName)" }.joined(separator: ", "))")
        return DistributedDevicesResult(devices: sortedDevices, connectionSnapshots: connectionSnapshots)
    }

    func hasIncompleteConnectedDevice(connection: SyncthingConnectionConfig, devices: [DeviceInfo]) async throws -> Bool {
        let connectedDeviceIDs = Set(devices.filter(\.isConnected).map(\.deviceID))
        guard !connectedDeviceIDs.isEmpty else { return false }

        let folders = try await fetchFolders(connection: connection)

        for folder in folders where folder.paused != true {
            let sharedConnectedDeviceIDs = folder.devices?
                .map(\.deviceID)
                .filter { connectedDeviceIDs.contains($0) } ?? []

            for deviceID in sharedConnectedDeviceIDs {
                let completion: FolderCompletion = try await request(
                    path: "/rest/db/completion?folder=\(urlEncoded(folder.id))&device=\(urlEncoded(deviceID))",
                    connection: connection
                )

                if !completion.isComplete {
                    return true
                }
            }
        }

        return false
    }

    func fetchEvents(
        since lastSeenID: Int,
        connection: SyncthingConnectionConfig,
        eventTypes: String = "RemoteChangeDetected",
        limit: Int? = nil,
        timeout: Int = 60
    ) async throws -> [SyncthingEvent] {
        var path = "/rest/events?since=\(lastSeenID)&events=\(eventTypes)&timeout=\(timeout)"

        if let limit {
            path += "&limit=\(limit)"
        }

        Self.debugLog("fetchEvents path=\(path)")

        return try await request(
            path: path,
            connection: connection,
            timeoutInterval: TimeInterval(timeout + 10),
            decoder: Self.eventDecoder
        )
    }

    private func requestSystemStatus(connection: SyncthingConnectionConfig) async throws -> SyncthingSystemStatus {
        try await request(path: "/rest/system/status", connection: connection)
    }

    private static func remoteConfigs(from configs: [DeviceConfig], localDeviceID: String) -> [DeviceConfig] {
        configs.filter { !deviceID($0.deviceID, matches: localDeviceID) }
    }

    private static func deviceID(_ left: String, matches right: String) -> Bool {
        left.caseInsensitiveCompare(right) == .orderedSame
    }

    private enum FolderCheckState {
        case complete
        case incomplete
        case unknown
    }

    private struct CheckedSharedFolder {
        let info: SharedFolderInfo
        let checkState: FolderCheckState
        let pendingSyncCounts: PendingSyncCounts?
        let completion: Double?
    }

    private func distributedStatus(
        for deviceID: String,
        isConnected: Bool,
        folderChecks: [CheckedSharedFolder],
        downloadingDeviceIDs: Set<String>,
        syncingDeviceIDs: Set<String>
    ) -> DeviceSyncStatus {
        guard isConnected else {
            Self.debugLog("decision device=\(deviceID) status=disconnected reason=connection false")
            return .disconnected
        }

        if downloadingDeviceIDs.contains(deviceID) {
            Self.debugLog("decision device=\(deviceID) status=downloadingChanges reason=RemoteDownloadProgress recent")
            return .downloadingChanges
        }

        if syncingDeviceIDs.contains(deviceID) {
            Self.debugLog("decision device=\(deviceID) status=syncing reason=connection delta while local state syncing")
            return .syncing
        }

        guard !folderChecks.isEmpty else {
            Self.debugLog("decision device=\(deviceID) status=unknownConnected reason=no shared active folders")
            return .unknownConnected
        }

        if folderChecks.contains(where: { $0.checkState == .incomplete }) {
            Self.debugLog("decision device=\(deviceID) status=needsSyncing reason=shared folder incomplete")
            return .needsSyncing
        }

        if folderChecks.allSatisfy({ $0.checkState == .complete }) {
            Self.debugLog("decision device=\(deviceID) status=syncedWithThisDevice reason=all shared folders complete")
            return .syncedWithThisDevice
        }

        Self.debugLog("decision device=\(deviceID) status=unknownConnected reason=some shared folder states unknown")
        return .unknownConnected
    }

    private func checkedSharedFolders(
        for deviceID: String,
        isConnected: Bool,
        folders: [FolderConfig],
        isActivelySyncing: Bool,
        connection: SyncthingConnectionConfig
    ) async -> [CheckedSharedFolder] {
        let sharedFolders = folders.filter { folder in
            folder.devices?.contains { $0.deviceID == deviceID } == true
        }

        var result: [CheckedSharedFolder] = []
        for folder in sharedFolders {
            let name = folder.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name?.isEmpty == false ? name! : folder.id

            if folder.paused == true {
                result.append(
                    CheckedSharedFolder(
                        info: SharedFolderInfo(name: displayName, state: .attention),
                        checkState: .unknown,
                        pendingSyncCounts: nil,
                        completion: nil
                    )
                )
                continue
            }

            guard isConnected else {
                result.append(
                    CheckedSharedFolder(
                        info: SharedFolderInfo(name: displayName, state: nil),
                        checkState: .unknown,
                        pendingSyncCounts: nil,
                        completion: nil
                    )
                )
                continue
            }

            do {
                let completion: FolderCompletion = try await request(
                    path: "/rest/db/completion?folder=\(urlEncoded(folder.id))&device=\(urlEncoded(deviceID))",
                    connection: connection
                )

                let state: SharedFolderState?
                let checkState: FolderCheckState
                if completion.hasCompletionData, completion.isComplete {
                    state = .synced
                    checkState = .complete
                } else if completion.hasCompletionData, isActivelySyncing {
                    state = .syncing
                    checkState = .incomplete
                } else if completion.hasCompletionData {
                    state = .attention
                    checkState = .incomplete
                } else {
                    state = nil
                    checkState = .unknown
                }
                result.append(
                    CheckedSharedFolder(
                        info: SharedFolderInfo(
                            name: displayName,
                            state: state,
                            syncCompletion: completion.completion
                        ),
                        checkState: checkState,
                        pendingSyncCounts: completion.needItems != nil || completion.needDeletes != nil
                            ? PendingSyncCounts(
                                items: max(0, completion.needItems ?? 0),
                                deletions: max(0, completion.needDeletes ?? 0)
                            )
                            : nil,
                        completion: completion.completion
                    )
                )
            } catch {
                result.append(
                    CheckedSharedFolder(
                        info: SharedFolderInfo(name: displayName, state: nil),
                        checkState: .unknown,
                        pendingSyncCounts: nil,
                        completion: nil
                    )
                )
            }
        }

        return result.sorted {
            $0.info.name.localizedCaseInsensitiveCompare($1.info.name) == .orderedAscending
        }
    }

    private func fetchFolderErrors(
        for folders: [FolderConfig],
        connection: SyncthingConnectionConfig
    ) async -> [String: [StuckFileInfo]] {
        var result: [String: [StuckFileInfo]] = [:]

        for folder in folders {
            do {
                let response: FolderErrorsResponse = try await request(
                    path: "/rest/folder/errors?folder=\(urlEncoded(folder.id))",
                    connection: connection
                )
                result[folder.id] = response.errors
                    .map { StuckFileInfo(path: $0.path, reason: $0.error) }
                    .sorted {
                        $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
                    }
            } catch {
                Self.debugLog("folder errors unavailable folder=\(folder.id) error=\(error)")
            }
        }

        return result
    }

    private func stuckFiles(
        sharedWith deviceID: String,
        folders: [FolderConfig],
        errorsByFolderID: [String: [StuckFileInfo]]
    ) -> [StuckFileInfo] {
        folders
            .filter { $0.devices?.contains { $0.deviceID == deviceID } == true }
            .flatMap { errorsByFolderID[$0.id] ?? [] }
    }

    private func pendingSyncCounts(
        from folderChecks: [CheckedSharedFolder]
    ) -> PendingSyncCounts? {
        guard !folderChecks.isEmpty,
              folderChecks.allSatisfy({ $0.pendingSyncCounts != nil }) else {
            return nil
        }

        return folderChecks.reduce(PendingSyncCounts(items: 0, deletions: 0)) { total, folder in
            let counts = folder.pendingSyncCounts!
            return PendingSyncCounts(
                items: total.items + counts.items,
                deletions: total.deletions + counts.deletions
            )
        }
    }

    private func syncCompletion(from folderChecks: [CheckedSharedFolder]) -> Double? {
        guard !folderChecks.isEmpty else { return nil }

        let completions = folderChecks.compactMap(\.completion)
        guard completions.count == folderChecks.count,
              completions.allSatisfy({ $0.isFinite && (0...100).contains($0) }) else {
            return nil
        }

        return completions.min()
    }

    private func request<T: Decodable>(
        path: String,
        connection: SyncthingConnectionConfig,
        timeoutInterval: TimeInterval = 8,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        guard let url = URL(string: "\(connection.apiAddress)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(connection.apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = timeoutInterval

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        return try decoder.decode(T.self, from: data)
    }

    private func requestWithoutResponse(
        path: String,
        method: String,
        connection: SyncthingConnectionConfig,
        timeoutInterval: TimeInterval = 8
    ) async throws {
        guard let url = URL(string: "\(connection.apiAddress)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(connection.apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = timeoutInterval

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
    }

    private func urlEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private static let connectionDeltaThresholdBytes: Int64 = 256 * 1024

    private static func connectionSnapshots(
        from response: SyncthingConnectionsResponse
    ) -> [String: DeviceConnectionSnapshot] {
        response.connections.mapValues {
            DeviceConnectionSnapshot(
                inBytesTotal: $0.inBytesTotal ?? 0,
                outBytesTotal: $0.outBytesTotal ?? 0
            )
        }
    }

    private static func syncingDeviceIDs(
        configs: [DeviceConfig],
        connections: [String: DeviceConnection],
        currentSnapshots: [String: DeviceConnectionSnapshot],
        previousSnapshots: [String: DeviceConnectionSnapshot],
        localIsSyncing: Bool
    ) -> Set<String> {
        guard localIsSyncing else {
            debugLog("connection deltas ignored reason=local state is not syncing")
            return []
        }

        let connectedDeviceIDs = configs.compactMap { config -> String? in
            connections[config.deviceID]?.connected == true ? config.deviceID : nil
        }

        var syncingDeviceIDs = Set<String>()
        for deviceID in connectedDeviceIDs {
            guard let current = currentSnapshots[deviceID],
                  let previous = previousSnapshots[deviceID] else {
                debugLog("connection delta device=\(deviceID) skipped reason=missing snapshot current=\(currentSnapshots[deviceID] != nil) previous=\(previousSnapshots[deviceID] != nil)")
                continue
            }

            let deltaIn = max(0, current.inBytesTotal - previous.inBytesTotal)
            let deltaOut = max(0, current.outBytesTotal - previous.outBytesTotal)
            let isSignificant = deltaIn >= connectionDeltaThresholdBytes || deltaOut >= connectionDeltaThresholdBytes
            debugLog("connection delta device=\(deviceID) deltaIn=\(deltaIn) deltaOut=\(deltaOut) significant=\(isSignificant)")

            if isSignificant {
                syncingDeviceIDs.insert(deviceID)
            }
        }

        if syncingDeviceIDs.isEmpty, connectedDeviceIDs.count == 1, let onlyDeviceID = connectedDeviceIDs.first {
            debugLog("connection delta fallback device=\(onlyDeviceID) reason=local syncing with single connected device and no significant delta")
            syncingDeviceIDs.insert(onlyDeviceID)
        } else if syncingDeviceIDs.isEmpty {
            debugLog("connection delta no syncing devices reason=no significant delta connectedCount=\(connectedDeviceIDs.count)")
        }

        return syncingDeviceIDs
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("[CloudStatus][DevicesDebug][API] \(debugTimestamp()) \(message)")
        #endif
    }

    private static func debugTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func debugDeviceIDs(_ deviceIDs: Set<String>) -> String {
        deviceIDs.sorted().joined(separator: ",")
    }

    private static func debugOptional<T>(_ value: T?) -> String {
        value.map { "\($0)" } ?? "nil"
    }

    private static var eventDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = iso8601DateFormatter.date(from: value) {
                return date
            }

            if let date = iso8601DateFormatterWithoutFractions.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid event date: \(value)"
            )
        }
        return decoder
    }

    private static let iso8601DateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601DateFormatterWithoutFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
