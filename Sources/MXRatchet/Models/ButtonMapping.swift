import Foundation

// MARK: - System Action

enum SystemAction: String, Codable, CaseIterable {
    case missionControl
    case appExpose
    case showDesktop
    case launchpad
    case spotlight
    case screenshot
    case notificationCenter
    case lockScreen
    case playPause
    case nextTrack
    case prevTrack
    case volumeUp
    case volumeDown
    case mute
    case brightnessUp
    case brightnessDown

    var displayName: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Expose"
        case .showDesktop: return "Show Desktop"
        case .launchpad: return "Launchpad"
        case .spotlight: return "Spotlight"
        case .screenshot: return "Screenshot"
        case .notificationCenter: return "Notification Center"
        case .lockScreen: return "Lock Screen"
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Next Track"
        case .prevTrack: return "Previous Track"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .mute: return "Mute"
        case .brightnessUp: return "Brightness Up"
        case .brightnessDown: return "Brightness Down"
        }
    }
}

// MARK: - Key Combo

struct KeyCombo: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt64
    let displayName: String
}

// MARK: - Button Action

enum ButtonAction: Codable, Equatable {
    case passthrough
    case disabled
    case keyboardShortcut(KeyCombo)
    case systemAction(SystemAction)

    var displayName: String {
        switch self {
        case .passthrough: return "Default"
        case .disabled: return "Disabled"
        case .keyboardShortcut(let combo): return combo.displayName
        case .systemAction(let action): return action.displayName
        }
    }
}

// MARK: - Button Config

struct ButtonConfig: Codable, Identifiable {
    let id: Int    // macOS button number: 2=middle, 3=back, 4=forward
    var label: String
    var action: ButtonAction

    static let defaultButtons: [ButtonConfig] = [
        ButtonConfig(id: 2, label: "Middle Button", action: .passthrough),
        ButtonConfig(id: 3, label: "Back Button", action: .passthrough),
        ButtonConfig(id: 4, label: "Forward Button", action: .passthrough),
    ]
}

// MARK: - Gesture Config

struct GestureConfig: Codable, Equatable {
    var tap: ButtonAction
    var swipeUp: ButtonAction
    var swipeDown: ButtonAction
    var swipeLeft: ButtonAction
    var swipeRight: ButtonAction

    static let `default` = GestureConfig(
        tap: .passthrough,
        swipeUp: .systemAction(.missionControl),
        swipeDown: .systemAction(.appExpose),
        swipeLeft: .passthrough,
        swipeRight: .passthrough
    )
}

// MARK: - App Profile

struct AppProfile: Codable, Identifiable {
    let id: UUID
    var bundleId: String       // "*" for default
    var displayName: String
    var appIconPath: String?
    var buttons: [ButtonConfig]
    var gesture: GestureConfig

    static func makeDefault() -> AppProfile {
        AppProfile(
            id: UUID(),
            bundleId: "*",
            displayName: "Default",
            buttons: ButtonConfig.defaultButtons,
            gesture: .default
        )
    }
}
