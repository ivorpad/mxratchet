import CoreGraphics
import AppKit

// Media key types from IOKit/hidsystem/ev_keymap.h
private let NX_KEYTYPE_SOUND_UP: Int32 = 0
private let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
private let NX_KEYTYPE_BRIGHTNESS_UP: Int32 = 2
private let NX_KEYTYPE_BRIGHTNESS_DOWN: Int32 = 3
private let NX_KEYTYPE_MUTE: Int32 = 7
private let NX_KEYTYPE_PLAY: Int32 = 16
private let NX_KEYTYPE_NEXT: Int32 = 17
private let NX_KEYTYPE_PREVIOUS: Int32 = 18

// CoreDock private framework (loaded at runtime)
private let coreDockHandle = dlopen("/System/Library/PrivateFrameworks/CoreDock.framework/CoreDock", RTLD_NOW)
private typealias CoreDockSendNotificationFn = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void

enum ActionExecutor {
    static func execute(_ action: ButtonAction) {
        switch action {
        case .passthrough:
            break
        case .disabled:
            break
        case .keyboardShortcut(let combo):
            postKeyStroke(keyCode: combo.keyCode, flags: CGEventFlags(rawValue: combo.modifiers))
        case .systemAction(let action):
            performSystemAction(action)
        }
    }

    // MARK: - Keyboard Shortcuts

    static func postKeyStroke(keyCode: UInt16, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - System Actions

    static func performSystemAction(_ action: SystemAction) {
        switch action {
        case .missionControl:
            sendDockNotification("com.apple.expose.awake")
        case .appExpose:
            sendDockNotification("com.apple.expose.front.awake")
        case .showDesktop:
            sendDockNotification("com.apple.showdesktop.awake")
        case .launchpad:
            sendDockNotification("com.apple.launchpad.toggle")
        case .spotlight:
            postKeyStroke(keyCode: 49, flags: .maskCommand)          // Cmd+Space
        case .screenshot:
            postKeyStroke(keyCode: 23, flags: [.maskCommand, .maskShift]) // Cmd+Shift+5
        case .notificationCenter:
            postKeyStroke(keyCode: 45, flags: CGEventFlags(rawValue: 0x800000)) // Fn+N (secondaryFn mask)
        case .lockScreen:
            postKeyStroke(keyCode: 12, flags: [.maskCommand, .maskControl]) // Ctrl+Cmd+Q
        case .playPause:
            postMediaKey(NX_KEYTYPE_PLAY)
        case .nextTrack:
            postMediaKey(NX_KEYTYPE_NEXT)
        case .prevTrack:
            postMediaKey(NX_KEYTYPE_PREVIOUS)
        case .volumeUp:
            postMediaKey(NX_KEYTYPE_SOUND_UP)
        case .volumeDown:
            postMediaKey(NX_KEYTYPE_SOUND_DOWN)
        case .mute:
            postMediaKey(NX_KEYTYPE_MUTE)
        case .brightnessUp:
            postMediaKey(NX_KEYTYPE_BRIGHTNESS_UP)
        case .brightnessDown:
            postMediaKey(NX_KEYTYPE_BRIGHTNESS_DOWN)
        }
    }

    // MARK: - CoreDock (Private Framework)

    private static func sendDockNotification(_ name: String) {
        guard let handle = coreDockHandle,
              let sym = dlsym(handle, "CoreDockSendNotification") else { return }
        let fn = unsafeBitCast(sym, to: CoreDockSendNotificationFn.self)
        fn(name as CFString, nil)
    }

    // MARK: - Media Keys

    private static func postMediaKey(_ keyType: Int32) {
        func doEvent(keyDown: Bool) {
            let flags: UInt64 = keyDown ? 0xA00 : 0xB00
            let data1 = Int((keyType << 16) | Int32(flags))
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        doEvent(keyDown: true)
        doEvent(keyDown: false)
    }
}
