import Foundation
import CoreServices
import ServiceManagement

struct SyncthingConnectionConfig: Equatable {
    var host: String
    var port: String
    var apiKey: String
    var usesTLS: Bool

    var scheme: String { usesTLS ? "https" : "http" }

    var apiAddress: String {
        "\(scheme)://\(host):\(port)"
    }
}

final class SettingsStore: ObservableObject {
    @Published var host: String {
        didSet { defaults.set(host, forKey: Keys.host) }
    }

    @Published var port: String {
        didSet { defaults.set(port, forKey: Keys.port) }
    }

    @Published var apiKey: String {
        didSet { defaults.set(apiKey, forKey: Keys.apiKey) }
    }

    @Published var usesTLS: Bool {
        didSet { defaults.set(usesTLS, forKey: Keys.usesTLS) }
    }

    @Published var connectionMode: SyncthingConnectionMode {
        didSet { defaults.set(connectionMode.rawValue, forKey: Keys.connectionMode) }
    }

    @Published var iconTheme: IconTheme {
        didSet { defaults.set(iconTheme.rawValue, forKey: Keys.iconTheme) }
    }

    @Published var operatingMode: OperatingMode {
        didSet { defaults.set(operatingMode.rawValue, forKey: Keys.operatingMode) }
    }

    @Published var referenceDeviceID: String {
        didSet { defaults.set(referenceDeviceID, forKey: Keys.referenceDeviceID) }
    }

    @Published var hasCompletedInitialSetup: Bool {
        didSet { defaults.set(hasCompletedInitialSetup, forKey: Keys.hasCompletedInitialSetup) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSynchronizingLaunchAtLogin else { return }
            logLegacyLoginItem("[1] Toggle recibido: \(launchAtLogin ? "activado" : "desactivado")")
            logLegacyLoginItem("[7a] Antes de persistir la preferencia solicitada en UserDefaults")
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            logLegacyLoginItem("[7a] Después de persistir la preferencia solicitada en UserDefaults")
            applyLaunchAtLoginPreference()
        }
    }

    private let defaults: UserDefaults
    private var isSynchronizingLaunchAtLogin = false

    var isConfigured: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var webURL: URL? {
        URL(string: activeConnectionConfig.apiAddress)
    }

    var activeConnectionConfig: SyncthingConnectionConfig {
        SyncthingConnectionConfig(host: host, port: port, apiKey: apiKey, usesTLS: usesTLS)
    }

    var hasCompletedInitialSetupPreferenceExists: Bool {
        defaults.object(forKey: Keys.hasCompletedInitialSetup) != nil
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.host = defaults.string(forKey: Keys.host) ?? "127.0.0.1"
        self.port = defaults.string(forKey: Keys.port) ?? "8384"
        self.apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
        self.usesTLS = defaults.object(forKey: Keys.usesTLS) as? Bool ?? false
        if let savedConnectionMode = SyncthingConnectionMode(rawValue: defaults.string(forKey: Keys.connectionMode) ?? "") {
            self.connectionMode = savedConnectionMode
        } else if defaults.object(forKey: Keys.host) != nil ||
                    defaults.object(forKey: Keys.port) != nil ||
                    defaults.object(forKey: Keys.apiKey) != nil {
            self.connectionMode = .manual
        } else {
            self.connectionMode = .automatic
        }
        self.iconTheme = IconTheme(rawValue: defaults.string(forKey: Keys.iconTheme) ?? "") ?? .automatic
        self.operatingMode = OperatingMode(rawValue: defaults.string(forKey: Keys.operatingMode) ?? "") ?? .distributed
        self.referenceDeviceID = defaults.string(forKey: Keys.referenceDeviceID) ?? ""
        self.hasCompletedInitialSetup = defaults.object(forKey: Keys.hasCompletedInitialSetup) as? Bool ?? false
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)

        synchronizeLaunchAtLoginState()
    }

    func applyConnectionConfig(_ config: SyncthingConnectionConfig) {
        host = config.host
        port = config.port
        apiKey = config.apiKey
        usesTLS = config.usesTLS
    }

    func detectLocalSyncthingConfig() -> SyncthingConnectionConfig? {
        let configURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Syncthing/config.xml")

        guard let parser = XMLParser(contentsOf: configURL) else { return nil }
        let delegate = SyncthingConfigParserDelegate()
        parser.delegate = delegate

        guard parser.parse(),
              let apiKey = delegate.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            return nil
        }

        let address = delegate.address?.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = Self.hostAndPort(from: address)

        return SyncthingConnectionConfig(
            host: components.host,
            port: components.port,
            apiKey: apiKey,
            usesTLS: delegate.usesTLS
        )
    }

    private static func hostAndPort(from address: String?) -> (host: String, port: String) {
        guard let address, !address.isEmpty else {
            return ("127.0.0.1", "8384")
        }

        let normalizedAddress = address
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")

        if normalizedAddress.hasPrefix(":") {
            return ("127.0.0.1", String(normalizedAddress.dropFirst()))
        }

        if let colonIndex = normalizedAddress.lastIndex(of: ":") {
            let host = String(normalizedAddress[..<colonIndex])
            let port = String(normalizedAddress[normalizedAddress.index(after: colonIndex)...])
            return (host.isEmpty || host == "0.0.0.0" || host == "[::]" ? "127.0.0.1" : host, port.isEmpty ? "8384" : port)
        }

        return (normalizedAddress, "8384")
    }

    private func applyLaunchAtLoginPreference() {
        if #available(macOS 13.0, *) {
            logLegacyLoginItem("Aplicando preferencia mediante SMAppService (macOS 13+)")
            do {
                if launchAtLogin {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                synchronizeLaunchAtLoginState()
                return
            }
        } else {
            logLegacyLoginItem("Aplicando preferencia mediante LSSharedFileList (macOS 12)")
            setLegacyLaunchAtLoginEnabled(launchAtLogin)
        }

        synchronizeLaunchAtLoginState()
    }

    private func synchronizeLaunchAtLoginState() {
        let isEnabled: Bool

        if #available(macOS 13.0, *) {
            isEnabled = SMAppService.mainApp.status == .enabled
        } else {
            logLegacyLoginItem("[6] Antes de la lectura final del estado")
            isEnabled = legacyLoginItem() != nil
            logLegacyLoginItem("[6] Después de la lectura final del estado: \(isEnabled)")
        }

        isSynchronizingLaunchAtLogin = true
        launchAtLogin = isEnabled
        logLegacyLoginItem("[7] Antes de persistir el estado final en UserDefaults: \(isEnabled)")
        defaults.set(isEnabled, forKey: Keys.launchAtLogin)
        logLegacyLoginItem("[7] Después de persistir el estado final en UserDefaults")
        isSynchronizingLaunchAtLogin = false
    }

    private func setLegacyLaunchAtLoginEnabled(_ isEnabled: Bool) {
        logLegacyLoginItem("Inicio de la modificación LSSharedFileList: enabled=\(isEnabled)")
        guard let loginItems = legacyLoginItemsList() else { return }
        logLegacyLoginItem("Lista de Login Items abierta para modificación")

        if isEnabled {
            logLegacyLoginItem("[3] Antes de comprobar si existe una entrada previa")
            guard legacyLoginItem(in: loginItems) == nil else { return }
            logLegacyLoginItem("[3] Después de comprobar la entrada previa: no existe")

            let appURL = Bundle.main.bundleURL
            logLegacyLoginItem("[2] Bundle.main.bundleURL: \(appURL.absoluteString)")
            logLegacyLoginItem("[2] Ruta usada: \(appURL.path); isFileURL=\(appURL.isFileURL); existe=\(FileManager.default.fileExists(atPath: appURL.path))")

            logLegacyLoginItem("[5] Antes de LSSharedFileListInsertItemURL")
            let wasInserted = CSLInsertLoginItemLast(loginItems, appURL as CFURL)
            logLegacyLoginItem("[5] Después de CSLInsertLoginItemLast; éxito=\(wasInserted)")

            if wasInserted {
                logLegacyLoginItem("Login item añadido")
            } else {
                logLegacyLoginItem("Error al añadir: LSSharedFileListInsertItemURL devolvió nil")
            }
        } else if let item = legacyLoginItem(in: loginItems) {
            logLegacyLoginItem("[4] Antes de LSSharedFileListItemRemove")
            let status = LSSharedFileListItemRemove(loginItems, item)
            logLegacyLoginItem("[4] Después de LSSharedFileListItemRemove; OSStatus=\(status)")
            if status == noErr {
                logLegacyLoginItem("Login item eliminado")
            } else {
                logLegacyLoginItem("Error al eliminar: OSStatus \(status)")
            }
        } else {
            logLegacyLoginItem("No se encontró un login item que eliminar")
        }
    }

    private func legacyLoginItem() -> LSSharedFileListItem? {
        guard let loginItems = legacyLoginItemsList() else { return nil }
        return legacyLoginItem(in: loginItems)
    }

    private func legacyLoginItem(in loginItems: LSSharedFileList) -> LSSharedFileListItem? {
        logLegacyLoginItem("[3] Antes de LSSharedFileListCopySnapshot")
        let unmanagedSnapshot = LSSharedFileListCopySnapshot(loginItems, nil)
        logLegacyLoginItem("[3] Después de LSSharedFileListCopySnapshot; devolvió nil=\(unmanagedSnapshot == nil)")
        guard let snapshot = unmanagedSnapshot?.takeRetainedValue() as? [LSSharedFileListItem] else {
            logLegacyLoginItem("Error al leer la lista: LSSharedFileListCopySnapshot devolvió nil")
            return nil
        }
        logLegacyLoginItem("[3] Snapshot convertido correctamente; elementos=\(snapshot.count)")

        let appURL = Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        logLegacyLoginItem("URL utilizada para buscar: \(appURL.path); elementos en la lista: \(snapshot.count)")

        let matchingItem = snapshot.first { item in
            var resolutionError: Unmanaged<CFError>?
            logLegacyLoginItem("[3] Antes de LSSharedFileListItemCopyResolvedURL")
            guard let resolvedURL = LSSharedFileListItemCopyResolvedURL(item, 0, &resolutionError) else {
                logLegacyLoginItem("[3] LSSharedFileListItemCopyResolvedURL devolvió nil")
                let errorDescription = resolutionError?.takeRetainedValue().localizedDescription ?? "sin detalle"
                logLegacyLoginItem("No se pudo resolver un login item: \(errorDescription)")
                return false
            }
            logLegacyLoginItem("[3] Después de LSSharedFileListItemCopyResolvedURL; antes de takeRetainedValue")

            let itemURL = resolvedURL.takeRetainedValue() as URL
            logLegacyLoginItem("[3] Después de takeRetainedValue y conversión a URL: \(itemURL.absoluteString)")
            let normalizedItemURL = itemURL.standardizedFileURL.resolvingSymlinksInPath()
            logLegacyLoginItem("Login item inspeccionado: \(normalizedItemURL.path)")
            return normalizedItemURL == appURL
        }

        if matchingItem != nil {
            logLegacyLoginItem("Login item encontrado")
        } else {
            logLegacyLoginItem("Login item no encontrado")
        }

        return matchingItem
    }

    private func legacyLoginItemsList() -> LSSharedFileList? {
        logLegacyLoginItem("[3] Antes de LSSharedFileListCreate")
        let loginItems = LSSharedFileListCreate(
            nil,
            kLSSharedFileListSessionLoginItems.takeUnretainedValue(),
            nil
        )?.takeRetainedValue()
        logLegacyLoginItem("[3] Después de LSSharedFileListCreate/takeRetainedValue; devolvió nil=\(loginItems == nil)")

        if loginItems == nil {
            logLegacyLoginItem("Error al abrir kLSSharedFileListSessionLoginItems")
        }

        return loginItems
    }

    private func logLegacyLoginItem(_ message: String) {
        NSLog("[CloudStatus][LoginItems][Monterey] %@", message)
    }
}

enum OperatingMode: String, CaseIterable, Identifiable {
    case distributed
    case referenceDevice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distributed:
            return "Distribuido"
        case .referenceDevice:
            return "Dispositivo de referencia"
        }
    }

    var localizedTitle: String {
        switch self {
        case .distributed:
            return NSLocalizedString("settings.viewMode.distributed", comment: "Distributed view mode option")
        case .referenceDevice:
            return NSLocalizedString("settings.viewMode.referenceDevice", comment: "Reference device view mode option")
        }
    }
}

enum SyncthingConnectionMode: String, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .automatic:
            return NSLocalizedString("settings.connection.automatic", comment: "Automatic Syncthing connection mode")
        case .manual:
            return NSLocalizedString("settings.connection.manual", comment: "Manual Syncthing connection mode")
        }
    }
}

private final class SyncthingConfigParserDelegate: NSObject, XMLParserDelegate {
    var address: String?
    var apiKey: String?
    var usesTLS = false

    private var elementStack: [String] = []
    private var captureBuffer = ""
    private var isInsideGUI = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        elementStack.append(elementName)
        captureBuffer = ""

        if elementName == "gui" {
            isInsideGUI = true
            usesTLS = attributeDict["tls"] == "true"
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        captureBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        defer {
            _ = elementStack.popLast()
            captureBuffer = ""
            if elementName == "gui" {
                isInsideGUI = false
            }
        }

        guard isInsideGUI else { return }

        switch elementName {
        case "address":
            address = captureBuffer
        case "apikey":
            apiKey = captureBuffer
        default:
            break
        }
    }
}

private enum Keys {
    static let host = "syncthingHost"
    static let port = "syncthingPort"
    static let apiKey = "syncthingAPIKey"
    static let usesTLS = "syncthingUsesTLS"
    static let connectionMode = "syncthingConnectionMode"
    static let iconTheme = "iconTheme"
    static let operatingMode = "operatingMode"
    static let referenceDeviceID = "referenceDeviceID"
    static let hasCompletedInitialSetup = "hasCompletedInitialSetup"
    static let launchAtLogin = "launchAtLogin"
}
