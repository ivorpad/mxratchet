// mxratchet-hid.swift — Control MX Master 3 ratchet mode via HID++ 2.0
// Uses IOKit IOHIDDevice to send HID++ long reports on macOS.
// Requires root (sudo) for BLE HID access.

import Foundation
import IOKit
import IOKit.hid

// MARK: - Constants

let LOGITECH_VID: Int32 = 0x046D
let MX_MASTER_3_PIDS: [Int32] = [0xB023, 0x4082, 0xC548]

let REPORT_ID_LONG: CFIndex = 0x11   // HID++ 2.0 long report (20 bytes total)
let LONG_PAYLOAD_SIZE = 19            // 3 header + 16 data (report ID excluded)

let FEATURE_SMARTSHIFT: UInt16 = 0x2110
let FEATURE_SMARTSHIFT_3G: UInt16 = 0x2111

let MODE_FREESPIN: UInt8 = 1
let MODE_RATCHET: UInt8 = 2
let AUTO_DISENGAGE_ALWAYS: UInt8 = 0xFF

let SW_ID: UInt8 = 0x02
let DEV_IDX_DIRECT: UInt8 = 0xFF

let verbose = CommandLine.arguments.contains("-v")

// MARK: - Helpers

struct HIDPPError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

func ioReturnDesc(_ ret: IOReturn) -> String {
    let u = UInt32(bitPattern: ret)
    let names: [UInt32: String] = [
        0:          "success",
        0xE00002BC: "kIOReturnError",
        0xE00002C1: "kIOReturnNotPrivileged",
        0xE00002C5: "kIOReturnExclusiveAccess",
        0xE00002E2: "kIOReturnNotPermitted",
        0xE00002F0: "kIOReturnNotResponding",
    ]
    return names[u] ?? "0x\(String(u, radix: 16))"
}

func log(_ msg: String) { if verbose { fputs("[\(ts())] \(msg)\n", stderr) } }
func ts() -> String { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: Date()) }

// MARK: - HID++ Device

class HIDPPDevice {
    let device: IOHIDDevice
    let devIndex: UInt8
    private var responseData: [UInt8] = []
    private var responseReady = false
    private let lock = NSCondition()
    private var reportBuffer: UnsafeMutablePointer<UInt8>?

    init(device: IOHIDDevice, devIndex: UInt8) {
        self.device = device
        self.devIndex = devIndex
    }

    func open() throws {
        let ret = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard ret == kIOReturnSuccess else {
            if UInt32(bitPattern: ret) == 0xE00002E2 {
                throw HIDPPError(message:
                    "Permission denied. Run with sudo, or add your terminal to " +
                    "System Settings > Privacy & Security > Input Monitoring and restart it.")
            }
            throw HIDPPError(message: "IOHIDDeviceOpen failed: \(ioReturnDesc(ret))")
        }

        // Get max input report size from device properties
        let maxSize = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 64
        reportBuffer = .allocate(capacity: maxSize)

        IOHIDDeviceRegisterInputReportCallback(
            device, reportBuffer!, maxSize,
            { ctx, _, _, _, reportID, report, length in
                guard let ctx else { return }
                let self_ = Unmanaged<HIDPPDevice>.fromOpaque(ctx).takeUnretainedValue()
                let raw = Array(UnsafeBufferPointer(start: report, count: length))
                if verbose {
                    let hex = raw.map { String(format: "%02X", $0) }.joined(separator: " ")
                    fputs("  [cb] reportID=0x\(String(format: "%02X", reportID)) len=\(length) raw=\(hex)\n", stderr)
                }
                // Only process HID++ report IDs (0x10 short, 0x11 long). Ignore mouse/kbd.
                guard reportID == 0x10 || reportID == 0x11 else { return }

                var data = raw
                // macOS includes report ID as first byte of report data for non-zero IDs
                // (see Chromium hid_connection_mac.cc). Strip it if present.
                if data.count > 0 && data[0] == UInt8(reportID) {
                    data.removeFirst()
                }
                self_.lock.lock()
                self_.responseData = data
                self_.responseReady = true
                self_.lock.signal()
                self_.lock.unlock()
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    func close() {
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        reportBuffer?.deallocate()
        reportBuffer = nil
    }

    /// Send HID++ 2.0 long request and return response payload.
    func request(featureIndex: UInt8, function: UInt8, params: [UInt8] = []) throws -> [UInt8] {
        let funcSwid = ((function & 0x0F) << 4) | (SW_ID & 0x0F)

        // Build 20-byte report: [reportID, devIndex, featureIndex, func|swid, data×16]
        // Include report ID in data — macOS BLE IOKit expects this (see niw/HIDPP).
        var payload = [UInt8](repeating: 0, count: LONG_PAYLOAD_SIZE + 1)
        payload[0] = 0x11  // Report ID in data buffer
        payload[1] = devIndex
        payload[2] = featureIndex
        payload[3] = funcSwid
        for (i, p) in params.prefix(16).enumerated() {
            payload[4 + i] = p
        }

        log("TX: \(payload.map { String(format: "%02X", $0) }.joined(separator: " "))")

        // Output reports first — the BLE report descriptor defines 0x11 as Output.
        // Feature reports are a fallback (MaxFeature=1 on BLE, so usually won't work).
        let sendStrategies: [(IOHIDReportType, String)] = [
            (kIOHIDReportTypeOutput, "output"),
            (kIOHIDReportTypeFeature, "feature"),
        ]

        var sendOK = false
        for (reportType, name) in sendStrategies {
            let ret = IOHIDDeviceSetReport(device, reportType, REPORT_ID_LONG, payload, payload.count)
            if ret == kIOReturnSuccess {
                log("Sent via \(name) report")
                sendOK = true
                break
            }
            log("\(name) report failed: \(ioReturnDesc(ret))")
        }
        guard sendOK else {
            throw HIDPPError(message: "SetReport failed with all report types")
        }

        // Wait for matching HID++ response, skipping notifications
        for _ in 0..<20 {
            lock.lock()
            responseReady = false
            lock.unlock()

            CFRunLoopRunInMode(.defaultMode, 0.5, true)

            lock.lock()
            let ready = responseReady
            let data = responseData
            lock.unlock()

            guard ready, data.count >= 3 else { continue }
            log("RX: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")

            do {
                return try parseResponse(data, featureIndex: featureIndex, function: function)
            } catch let e as HIDPPError where e.message.hasPrefix("Response mismatch") {
                log("Skipping notification: \(e.message)")
                continue  // Skip notifications, keep waiting for our response
            }
        }
        throw HIDPPError(message: "No matching HID++ response after 20 attempts")
    }

    private func parseResponse(_ data: [UInt8], featureIndex: UInt8, function: UInt8) throws -> [UInt8] {
        let rFeat = data[1]
        let rFunc = data[2]

        // HID++ error response: featureIndex = 0xFF
        if rFeat == 0xFF {
            let errCode = data.count > 5 ? data[5] : 0
            let names: [UInt8: String] = [
                1: "Unknown", 2: "InvalidArgument", 3: "OutOfRange",
                4: "HWError", 5: "LogitechInternal", 6: "InvalidFeatureIndex",
                7: "InvalidFunctionID", 8: "Busy", 9: "Unsupported",
            ]
            throw HIDPPError(message: "HID++ error: \(names[errCode] ?? "code \(errCode)")")
        }

        // Match: same feature index and function number
        if rFeat == featureIndex && (rFunc & 0xF0) == ((function & 0x0F) << 4) {
            return data.count > 3 ? Array(data[3...]) : []
        }

        throw HIDPPError(message: "Response mismatch: expected feat=\(featureIndex) func=\(function), " +
              "got feat=\(rFeat) func=\(rFunc >> 4)")
    }

    func resolveFeature(_ featureID: UInt16) throws -> UInt8 {
        let resp = try request(featureIndex: 0, function: 0,
                               params: [UInt8(featureID >> 8), UInt8(featureID & 0xFF)])
        guard resp[0] != 0 else {
            throw HIDPPError(message: "Feature 0x\(String(featureID, radix: 16)) not supported")
        }
        log("Feature 0x\(String(featureID, radix: 16)) → index \(resp[0])")
        return resp[0]
    }
}

// MARK: - Device discovery

func findDevice() throws -> (IOHIDDevice, String) {
    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: LOGITECH_VID] as CFDictionary)
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

    guard let devs = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else {
        throw HIDPPError(message: "No HID devices found")
    }

    for pid in MX_MASTER_3_PIDS {
        var best: IOHIDDevice?
        for d in devs {
            let p = IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? Int32 ?? 0
            guard p == pid else { continue }
            let page = IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsagePageKey as CFString) as? Int32 ?? 0
            if page >= 0xFF00 || best == nil { best = d }
        }
        if let d = best {
            let conn = pid == 0xB023 ? "Bluetooth" : pid == 0x4082 ? "Bolt" : "Unifying"
            return (d, conn)
        }
    }
    throw HIDPPError(message: "MX Master 3 not found. Is it connected?")
}

/// Try to resolve SmartShift feature, probing device indices and feature IDs.
func resolveSmartShift(_ hidpp: HIDPPDevice) throws -> UInt8 {
    // Try both SmartShift feature IDs
    for feat in [FEATURE_SMARTSHIFT_3G, FEATURE_SMARTSHIFT] {
        do {
            let idx = try hidpp.resolveFeature(feat)
            log("SmartShift feature 0x\(String(feat, radix: 16)) → index \(idx)")
            return idx
        } catch {
            log("Feature 0x\(String(feat, radix: 16)): \(error)")
        }
    }
    throw HIDPPError(message: "SmartShift feature not found (tried 0x2110 and 0x2111)")
}

func openDevice() throws -> (HIDPPDevice, UInt8) {
    let (dev, conn) = try findDevice()
    let name = IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String ?? "MX Master 3"

    // For BLE, try multiple device indices: 0xFF (broadcast), 0x01 (first device)
    let indicesToTry: [UInt8] = conn == "Bluetooth" ? [0xFF, 0x01, 0x00] : [0x01]

    for idx in indicesToTry {
        log("Trying \(name) via \(conn) devIndex=0x\(String(idx, radix: 16))...")
        let hidpp = HIDPPDevice(device: dev, devIndex: idx)
        try hidpp.open()

        // Probe: try to resolve any SmartShift feature
        do {
            let ssIdx = try resolveSmartShift(hidpp)
            log("Success with devIndex=0x\(String(idx, radix: 16)), SmartShift index=\(ssIdx)")
            return (hidpp, ssIdx)
        } catch {
            log("devIndex 0x\(String(idx, radix: 16)) failed: \(error)")
            hidpp.close()
        }
    }
    throw HIDPPError(message: "Could not communicate with MX Master 3 on any device index")
}

// MARK: - Commands

func cmdStatus() throws {
    let (dev, conn) = try findDevice()
    let name = IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String ?? "MX Master 3"
    let (hidpp, ssIdx) = try openDevice()
    defer { hidpp.close() }

    let resp = try hidpp.request(featureIndex: ssIdx, function: 0)
    let wm = resp[0], ad = resp[1]

    print("Device:     \(name)")
    print("Connection: \(conn)")
    print("Wheel mode: \(wm == MODE_RATCHET ? "Ratchet" : wm == MODE_FREESPIN ? "Free spin" : "Unknown(\(wm))")")
    print("SmartShift: \(ad == AUTO_DISENGAGE_ALWAYS ? "Disabled (always engaged)" : ad == 0 ? "Default" : "Threshold \(ad)")")
}

func cmdSet(mode: UInt8, disengage: UInt8, label: String) throws {
    let (hidpp, ssIdx) = try openDevice()
    defer { hidpp.close() }
    let _ = try hidpp.request(featureIndex: ssIdx, function: 1, params: [mode, disengage, 0])
    print("Set: \(label)")
}

func cmdWatch(interval: Int) throws {
    print("Watching MX Master 3 — enforcing ratchet every \(interval)s (Ctrl-C to stop)")
    while true {
        do {
            let (hidpp, ssIdx) = try openDevice()
            defer { hidpp.close() }
            let resp = try hidpp.request(featureIndex: ssIdx, function: 0)
            if resp[0] != MODE_RATCHET || resp[1] != AUTO_DISENGAGE_ALWAYS {
                let _ = try hidpp.request(featureIndex: ssIdx, function: 1,
                                          params: [MODE_RATCHET, AUTO_DISENGAGE_ALWAYS, 0])
                let was = resp[0] == MODE_FREESPIN ? "Free spin" : "mode \(resp[0])"
                print("[\(ts())] Re-applied ratchet (was: \(was))")
            }
        } catch let e as HIDPPError where !e.message.contains("not found") {
            fputs("[\(ts())] Warning: \(e)\n", stderr)
        } catch is HIDPPError {
            log("Device not found, retrying...")
        }
        Thread.sleep(forTimeInterval: Double(interval))
    }
}

// MARK: - Main

let args = CommandLine.arguments.filter { $0 != "-v" }

do {
    switch args.count > 1 ? args[1] : nil {
    case "status":  try cmdStatus()
    case "ratchet": try cmdSet(mode: MODE_RATCHET, disengage: AUTO_DISENGAGE_ALWAYS,
                               label: "Ratchet mode (SmartShift disabled)")
    case "freespin": try cmdSet(mode: MODE_FREESPIN, disengage: 0, label: "Free spin mode")
    case "watch":
        let iv = args.count > 3 && args[2] == "--interval" ? Int(args[3]) ?? 30 : 30
        try cmdWatch(interval: iv)
    default:
        let name = (args.first! as NSString).lastPathComponent
        print("""
        Usage: \(name) [-v] <command>

        Commands:
          status              Show current wheel mode
          ratchet             Force ratchet mode (disable SmartShift)
          freespin            Force free spin mode
          watch [--interval N] Poll and re-apply ratchet (default: 30s)

        Options:
          -v    Verbose (show HID++ packets on stderr)

        Requires sudo for BLE HID access on macOS.
        """)
        exit(args.count > 1 ? 1 : 0)
    }
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
