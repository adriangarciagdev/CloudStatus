import AppKit
import SwiftUI

enum IconTheme: String, CaseIterable, Identifiable {
    case automatic
    case white
    case black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .white:
            return "White"
        case .black:
            return "Black"
        }
    }

    var localizedTitle: String {
        switch self {
        case .automatic:
            return NSLocalizedString("settings.iconTheme.automatic", comment: "Automatic icon theme option")
        case .white:
            return NSLocalizedString("settings.iconTheme.white", comment: "White icon theme option")
        case .black:
            return NSLocalizedString("settings.iconTheme.black", comment: "Black icon theme option")
        }
    }
}

enum IconProvider {
    static func menuBarImage(for state: SyncState, theme: IconTheme) -> NSImage? {
        if let assetImage = NSImage(named: assetName(for: state, theme: theme))?.copy() as? NSImage {
            assetImage.isTemplate = theme == .automatic
            return assetImage
        }

        let fallbackImage = NSImage(
            systemSymbolName: state.systemSymbolName,
            accessibilityDescription: state.title
        )
        fallbackImage?.isTemplate = theme == .automatic
        return fallbackImage
    }

    static func panelImage(for state: SyncState, colorScheme: ColorScheme) -> Image {
        let theme: IconTheme = colorScheme == .dark ? .white : .black
        let assetName = assetName(for: state, theme: theme)

        if NSImage(named: assetName) != nil {
            return Image(assetName)
        }

        return Image(systemName: state.systemSymbolName)
    }

    private static func assetName(for state: SyncState, theme: IconTheme) -> String {
        let assetTheme: IconTheme = theme == .automatic ? .white : theme
        return "\(assetTheme.rawValue)-\(assetSuffix(for: state))"
    }

    private static func assetSuffix(for state: SyncState) -> String {
        switch state {
        case .updated:
            return "uptodate"
        case .syncing:
            return "syncing"
        case .attention:
            return "abnormal"
        case .paused:
            return "pause"
        case .connectionError:
            return "error"
        }
    }
}
