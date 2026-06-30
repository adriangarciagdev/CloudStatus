import AppKit
import Foundation

enum SyncState: String, Codable, Equatable {
    case updated
    case syncing
    case attention
    case paused
    case connectionError

    var title: String {
        switch self {
        case .updated:
            return "Actualizado"
        case .syncing:
            return "Sincronizando"
        case .attention:
            return "Atención"
        case .paused:
            return "Pausado"
        case .connectionError:
            return "Error de conexión"
        }
    }

    var systemSymbolName: String {
        switch self {
        case .updated:
            return "checkmark.icloud.fill"
        case .syncing:
            return "arrow.clockwise"
        case .attention:
            return "exclamationmark.icloud.fill"
        case .paused:
            return "pause.circle.fill"
        case .connectionError:
            return "xmark.icloud.fill"
        }
    }

    var color: NSColor {
        switch self {
        case .updated:
            return .systemGreen
        case .syncing:
            return .systemBlue
        case .attention:
            return .systemOrange
        case .paused:
            return .systemOrange
        case .connectionError:
            return .systemRed
        }
    }
}

struct FolderConfig: Decodable {
    let id: String
    let label: String?
    let path: String?
    let paused: Bool?
    let devices: [FolderDevice]?
}

struct FolderDevice: Decodable {
    let deviceID: String
}

struct FolderStatus: Decodable {
    let state: String?
}

struct FolderCompletion: Decodable {
    let completion: Double?
    let needBytes: Int64?
    let needItems: Int?
    let needDeletes: Int?

    var hasCompletionData: Bool {
        completion != nil ||
            needBytes != nil ||
            needItems != nil ||
            needDeletes != nil
    }

    var isComplete: Bool {
        (completion ?? 0) >= 100 &&
        (needBytes ?? 0) == 0 &&
        (needItems ?? 0) == 0 &&
        (needDeletes ?? 0) == 0
    }
}

enum SharedFolderState: Equatable {
    case synced
    case syncing
    case attention

    var symbol: String {
        switch self {
        case .synced:
            return "✓"
        case .syncing:
            return "↻"
        case .attention:
            return "!"
        }
    }
}

struct SharedFolderInfo: Equatable {
    let name: String
    let state: SharedFolderState?
    let syncCompletion: Double?

    init(
        name: String,
        state: SharedFolderState?,
        syncCompletion: Double? = nil
    ) {
        self.name = name
        self.state = state
        self.syncCompletion = syncCompletion
    }
}

struct StuckFileInfo: Equatable {
    let path: String
    let reason: String
}

struct PendingSyncCounts: Equatable {
    let items: Int
    let deletions: Int
}

struct FolderErrorsResponse: Decodable {
    let errors: [FolderError]
}

struct FolderError: Decodable {
    let path: String
    let error: String
}

enum DeviceSyncStatus: Equatable {
    case connected
    case disconnected
    case syncedWithThisDevice
    case needsSyncing
    case downloadingChanges
    case syncing
    case unknownConnected

    var localizedTitle: String {
        switch self {
        case .connected, .unknownConnected:
            return NSLocalizedString("device.status.connected", comment: "Connected device status")
        case .disconnected:
            return NSLocalizedString("device.status.disconnected", comment: "Disconnected device status")
        case .syncedWithThisDevice:
            return NSLocalizedString("device.status.syncedWithThisDevice", comment: "Synced with this device status")
        case .needsSyncing:
            return NSLocalizedString("device.status.needsSyncing", comment: "Needs syncing device status")
        case .downloadingChanges:
            return NSLocalizedString("device.status.downloadingChanges", comment: "Downloading changes device status")
        case .syncing:
            return NSLocalizedString("device.status.syncing", comment: "Syncing device status")
        }
    }

    var distributedSortRank: Int {
        switch self {
        case .downloadingChanges:
            return 0
        case .syncing:
            return 1
        case .needsSyncing:
            return 2
        case .syncedWithThisDevice:
            return 3
        case .connected, .unknownConnected:
            return 4
        case .disconnected:
            return 5
        }
    }

    var debugName: String {
        switch self {
        case .connected:
            return "connected"
        case .disconnected:
            return "disconnected"
        case .syncedWithThisDevice:
            return "syncedWithThisDevice"
        case .needsSyncing:
            return "needsSyncing"
        case .downloadingChanges:
            return "downloadingChanges"
        case .syncing:
            return "syncing"
        case .unknownConnected:
            return "unknownConnected"
        }
    }
}

struct DeviceInfo: Identifiable, Equatable {
    let deviceID: String
    let name: String
    let isConnected: Bool
    let syncStatus: DeviceSyncStatus
    let sharedFolders: [SharedFolderInfo]
    let stuckFiles: [StuckFileInfo]
    let pendingSyncCounts: PendingSyncCounts?
    let syncCompletion: Double?

    init(
        deviceID: String,
        name: String,
        isConnected: Bool,
        syncStatus: DeviceSyncStatus? = nil,
        sharedFolders: [SharedFolderInfo] = [],
        stuckFiles: [StuckFileInfo] = [],
        pendingSyncCounts: PendingSyncCounts? = nil,
        syncCompletion: Double? = nil
    ) {
        self.deviceID = deviceID
        self.name = name
        self.isConnected = isConnected
        self.syncStatus = syncStatus ?? (isConnected ? .connected : .disconnected)
        self.sharedFolders = sharedFolders
        self.stuckFiles = stuckFiles
        self.pendingSyncCounts = pendingSyncCounts
        self.syncCompletion = syncCompletion
    }

    var id: String { deviceID }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty else { return trimmedName }

        let firstGroup = deviceID.split(separator: "-").first.map(String.init)
        return firstGroup?.isEmpty == false ? firstGroup! : deviceID
    }
}

struct DeviceConfig: Decodable {
    let deviceID: String
    let name: String?
    let paused: Bool?
}

struct SyncthingConnectionsResponse: Decodable {
    let connections: [String: DeviceConnection]
}

struct SyncthingSystemStatus: Decodable {
    let myID: String
}

struct DeviceConnection: Decodable {
    let connected: Bool?
    let inBytesTotal: Int64?
    let outBytesTotal: Int64?
}

struct DeviceConnectionSnapshot: Equatable {
    let inBytesTotal: Int64
    let outBytesTotal: Int64
}

struct DistributedDevicesResult {
    let devices: [DeviceInfo]
    let connectionSnapshots: [String: DeviceConnectionSnapshot]
}

enum ActivityAction: String, Codable {
    case updated
    case deleted
}

struct RecentActivityItem: Identifiable, Codable, Equatable {
    let id: UUID
    let fileName: String
    let relativePath: String
    let folderName: String?
    let folderPath: String?
    let date: Date
    let action: ActivityAction
    let sourceDeviceID: String?
    let sourceDeviceName: String?

    init(
        id: UUID = UUID(),
        fileName: String,
        relativePath: String,
        folderName: String?,
        folderPath: String?,
        date: Date,
        action: ActivityAction,
        sourceDeviceID: String?,
        sourceDeviceName: String?
    ) {
        self.id = id
        self.fileName = fileName
        self.relativePath = relativePath
        self.folderName = folderName
        self.folderPath = folderPath
        self.date = date
        self.action = action
        self.sourceDeviceID = sourceDeviceID
        self.sourceDeviceName = sourceDeviceName
    }

    var fileURL: URL? {
        guard let folderPath else { return nil }
        return URL(fileURLWithPath: folderPath).appendingPathComponent(relativePath)
    }

    var sourceDisplayName: String? {
        if let sourceDeviceName, !sourceDeviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sourceDeviceName
        }

        return sourceDeviceID
    }
}

struct SyncthingEvent: Decodable {
    let id: Int
    let type: String
    let time: Date
    let data: SyncthingEventData?
}

struct SyncthingEventData: Decodable {
    let item: String?
    let path: String?
    let folder: String?
    let folderID: String?
    let label: String?
    let error: String?
    let type: String?
    let action: String?
    let modifiedBy: String?
    let device: String?
    let state: [String: Int]?
}
