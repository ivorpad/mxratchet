import Foundation
import Shared

// MARK: - Setup

signal(SIGPIPE, SIG_IGN)

hidppVerbose = CommandLine.arguments.contains("-v")

func log(_ msg: String) {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    print("[\(f.string(from: Date()))] \(msg)")
    fflush(stdout)
}

// MARK: - Preferences

func loadPreferences() -> UserPreferences {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: prefsPath)),
          let prefs = try? JSONDecoder().decode(UserPreferences.self, from: data) else {
        return UserPreferences()
    }
    return prefs
}

func savePreferences(_ prefs: UserPreferences) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    if let data = try? encoder.encode(prefs) {
        try? data.write(to: URL(fileURLWithPath: prefsPath))
    }
}

// MARK: - Device Management

var currentDevice: HIDPPDevice?
var cachedDPIList: [Int]?

func connectDevice() -> HIDPPDevice? {
    do {
        let device = try HIDPPDevice.openDevice()
        log("Connected to MX Master 3 via \(device.connectionType)")
        return device
    } catch {
        log("Device probe: \(error)")
        return nil
    }
}

func applyPreferences(_ device: HIDPPDevice) {
    let prefs = loadPreferences()
    if let mode = prefs.wheelMode, let ad = prefs.autoDisengage {
        do {
            try device.setSmartShift(mode: UInt8(mode), autoDisengage: UInt8(ad))
            log("Applied wheel mode: \(mode == 2 ? "Ratchet" : "Free spin"), autoDisengage: \(ad)")
        } catch {
            log("Failed to apply wheel mode: \(error)")
        }
    }
    if let dpi = prefs.dpi {
        do {
            try device.setDPI(dpi)
            log("Applied DPI: \(dpi)")
        } catch {
            log("Failed to apply DPI: \(error)")
        }
    }
    if let inv = prefs.thumbWheelInverted {
        do {
            try device.setThumbwheelMode(diverted: false, inverted: inv != 0)
            log("Applied thumb wheel: inverted=\(inv != 0)")
        } catch {
            log("Failed to apply thumb wheel: \(error)")
        }
    }
    if prefs.hiResScroll != nil || prefs.scrollInverted != nil {
        do {
            try device.setHiResWheel(
                hiRes: (prefs.hiResScroll ?? 0) != 0,
                inverted: (prefs.scrollInverted ?? 0) != 0
            )
            log("Applied hi-res scroll: hiRes=\(prefs.hiResScroll != nil), inverted=\(prefs.scrollInverted != nil)")
        } catch {
            log("Failed to apply hi-res scroll: \(error)")
        }
    }
}

func getFullStatus(_ device: HIDPPDevice, includeDPIList: Bool) -> MouseState? {
    var level = 0
    var charging = false
    var mode = 2
    var ad = 0xFF
    var dpi = 1000
    var dpiList: [Int]?
    var anySuccess = false

    do {
        let result = try device.getBatteryStatus()
        level = result.level
        charging = result.charging
        anySuccess = true
    } catch {
        log("Battery query failed: \(error)")
    }

    do {
        let result = try device.getSmartShiftStatus()
        mode = result.mode
        ad = result.autoDisengage
        anySuccess = true
    } catch {
        log("SmartShift query failed: \(error)")
    }

    do {
        dpi = try device.getDPI()
        anySuccess = true
    } catch {
        log("DPI query failed: \(error)")
    }

    if includeDPIList {
        if let cached = cachedDPIList {
            dpiList = cached
        } else {
            do {
                dpiList = try device.getDPIList()
                cachedDPIList = dpiList
            } catch {
                log("DPI list query failed: \(error)")
            }
        }
    }

    guard anySuccess else { return nil }

    return MouseState(
        batteryLevel: level,
        batteryCharging: charging,
        wheelMode: mode,
        autoDisengage: ad,
        dpi: dpi,
        dpiList: dpiList
    )
}

// MARK: - Request Handler

func handleRequest(_ request: MXRequest) -> MXResponse {
    guard let device = currentDevice else {
        return MXResponse(ok: false, error: "Device not connected")
    }

    switch request.action {
    case "getStatus":
        let includeDPIList = request.params?["includeDPIList"] == 1
        if let state = getFullStatus(device, includeDPIList: includeDPIList) {
            return MXResponse(ok: true, data: state)
        }
        return MXResponse(ok: false, error: "Failed to read device status")

    case "setWheelMode":
        guard let mode = request.params?["mode"] else {
            return MXResponse(ok: false, error: "Missing 'mode' parameter")
        }
        let ad = request.params?["autoDisengage"] ?? (mode == 2 ? 0xFF : 0)
        do {
            try device.setSmartShift(mode: UInt8(mode), autoDisengage: UInt8(ad))
            var prefs = loadPreferences()
            prefs.wheelMode = mode
            prefs.autoDisengage = ad
            savePreferences(prefs)
            // Return updated status
            if let state = getFullStatus(device, includeDPIList: false) {
                return MXResponse(ok: true, data: state)
            }
            return MXResponse(ok: true)
        } catch {
            return MXResponse(ok: false, error: "\(error)")
        }

    case "setDPI":
        guard let dpi = request.params?["dpi"] else {
            return MXResponse(ok: false, error: "Missing 'dpi' parameter")
        }
        do {
            try device.setDPI(dpi)
            var prefs = loadPreferences()
            prefs.dpi = dpi
            savePreferences(prefs)
            return MXResponse(ok: true)
        } catch {
            return MXResponse(ok: false, error: "\(error)")
        }

    case "divertButton":
        guard let cid = request.params?["cid"] else {
            return MXResponse(ok: false, error: "Missing 'cid' parameter")
        }
        do {
            try device.divertButton(cid: UInt16(cid))
            log("Diverted button CID \(cid)")
            return MXResponse(ok: true)
        } catch {
            return MXResponse(ok: false, error: "\(error)")
        }

    case "undivertButton":
        guard let cid = request.params?["cid"] else {
            return MXResponse(ok: false, error: "Missing 'cid' parameter")
        }
        do {
            try device.undivertButton(cid: UInt16(cid))
            log("Undiverted button CID \(cid)")
            return MXResponse(ok: true)
        } catch {
            return MXResponse(ok: false, error: "\(error)")
        }

    case "setThumbWheel":
        let diverted = (request.params?["diverted"] ?? 0) != 0
        let inverted = (request.params?["inverted"] ?? 0) != 0
        do {
            try device.setThumbwheelMode(diverted: diverted, inverted: inverted)
            var prefs = loadPreferences()
            prefs.thumbWheelInverted = inverted ? 1 : nil
            savePreferences(prefs)
            log("ThumbWheel: diverted=\(diverted), inverted=\(inverted)")
            return MXResponse(ok: true)
        } catch {
            return MXResponse(ok: false, error: "\(error)")
        }

    case "setHiResScroll":
        let hiRes = (request.params?["hiRes"] ?? 0) != 0
        let inverted = (request.params?["inverted"] ?? 0) != 0
        do {
            try device.setHiResWheel(hiRes: hiRes, inverted: inverted)
            var prefs = loadPreferences()
            prefs.hiResScroll = hiRes ? 1 : nil
            prefs.scrollInverted = inverted ? 1 : nil
            savePreferences(prefs)
            log("HiResScroll: hiRes=\(hiRes), inverted=\(inverted)")
            return MXResponse(ok: true)
        } catch {
            return MXResponse(ok: false, error: "\(error)")
        }

    default:
        return MXResponse(ok: false, error: "Unknown action: \(request.action)")
    }
}

// MARK: - Socket Server

let server = SocketServer(path: socketPath)
server.onRequest = { request in
    // Dispatch HID operations to the main RunLoop thread
    var result: MXResponse?
    let sem = DispatchSemaphore(value: 0)

    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
        result = handleRequest(request)
        sem.signal()
    }
    CFRunLoopWakeUp(CFRunLoopGetMain())
    sem.wait()

    return result ?? MXResponse(ok: false, error: "Internal error")
}

do {
    try server.start()
    log("Socket server listening on \(socketPath)")
} catch {
    fputs("Failed to start socket server: \(error)\n", stderr)
    exit(1)
}

// MARK: - Periodic Device Monitor

let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now(), repeating: 10.0)
timer.setEventHandler {
    if currentDevice == nil {
        currentDevice = connectDevice()
        if let device = currentDevice {
            applyPreferences(device)
        }
    } else {
        // Liveness check: try reading SmartShift status
        do {
            let _ = try currentDevice!.getSmartShiftStatus()
        } catch {
            log("Device disconnected: \(error)")
            currentDevice?.close()
            currentDevice = nil
            cachedDPIList = nil
        }
    }
}
timer.resume()

// Initial connection
currentDevice = connectDevice()
if let device = currentDevice {
    applyPreferences(device)
} else {
    log("MX Master 3 not found, will poll for reconnection...")
}

log("mxratchet-helper started (pid \(ProcessInfo.processInfo.processIdentifier))")

// Run the main RunLoop (processes IOKit callbacks + dispatched blocks)
CFRunLoopRun()
