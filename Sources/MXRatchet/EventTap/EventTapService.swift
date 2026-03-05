import CoreGraphics
import AppKit

class EventTapService {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let mappingStore: MappingStore
    private let appMonitor: ActiveAppMonitor

    init(mappingStore: MappingStore, appMonitor: ActiveAppMonitor) {
        self.mappingStore = mappingStore
        self.appMonitor = appMonitor
    }

    func start() {
        let mask: CGEventMask = (1 << CGEventType.otherMouseDown.rawValue)
                               | (1 << CGEventType.otherMouseUp.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<EventTapService>.fromOpaque(refcon).takeUnretainedValue()
                return service.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            print("EventTapService: Failed to create event tap. Check Accessibility permissions.")
            return
        }

        self.eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .otherMouseDown || type == .otherMouseUp else {
            return Unmanaged.passUnretained(event)
        }

        let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let bundleId = appMonitor.frontmostBundleId
        let profile = mappingStore.activeProfile(for: bundleId)

        guard let config = profile.buttons.first(where: { $0.id == buttonNumber }) else {
            return Unmanaged.passUnretained(event)
        }

        switch config.action {
        case .passthrough:
            return Unmanaged.passUnretained(event)
        case .disabled:
            return nil
        case .keyboardShortcut, .systemAction:
            if type == .otherMouseDown {
                ActionExecutor.execute(config.action)
            }
            return nil
        }
    }

    static func checkAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
