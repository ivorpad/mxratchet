import Foundation
import IOKit
import IOKit.hid

// MARK: - Constants

let LOGITECH_VID: Int32 = 0x046D
let MX_MASTER_3_PIDS: [Int32] = [0xB023, 0x4082, 0xC548]

let REPORT_ID_LONG: CFIndex = 0x11
let LONG_PAYLOAD_SIZE = 19

let SW_ID: UInt8 = 0x02

// MARK: - Error

struct HIDPPError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

// MARK: - Logging

var hidppVerbose = false

func hidppLog(_ msg: String) {
    if hidppVerbose {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        fputs("[\(f.string(from: Date()))] \(msg)\n", stderr)
    }
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

// MARK: - HID++ Device

class HIDPPDevice {
    let device: IOHIDDevice
    let devIndex: UInt8
    let connectionType: String
    private var responseData: [UInt8] = []
    private var responseReady = false
    private let lock = NSCondition()
    private var reportBuffer: UnsafeMutablePointer<UInt8>?

    init(device: IOHIDDevice, devIndex: UInt8, connectionType: String = "Unknown") {
        self.device = device
        self.devIndex = devIndex
        self.connectionType = connectionType
    }

    func open() throws {
        let ret = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard ret == kIOReturnSuccess else {
            if UInt32(bitPattern: ret) == 0xE00002E2 {
                throw HIDPPError(message:
                    "Permission denied. The helper must run as root for BLE HID access.")
            }
            throw HIDPPError(message: "IOHIDDeviceOpen failed: \(ioReturnDesc(ret))")
        }

        let maxSize = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 64
        reportBuffer = .allocate(capacity: maxSize)

        IOHIDDeviceRegisterInputReportCallback(
            device, reportBuffer!, maxSize,
            { ctx, _, _, _, reportID, report, length in
                guard let ctx else { return }
                let self_ = Unmanaged<HIDPPDevice>.fromOpaque(ctx).takeUnretainedValue()
                let raw = Array(UnsafeBufferPointer(start: report, count: length))
                if hidppVerbose {
                    let hex = raw.map { String(format: "%02X", $0) }.joined(separator: " ")
                    fputs("  [cb] reportID=0x\(String(format: "%02X", reportID)) len=\(length) raw=\(hex)\n", stderr)
                }
                guard reportID == 0x10 || reportID == 0x11 else { return }

                var data = raw
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

    @discardableResult
    func request(featureIndex: UInt8, function: UInt8, params: [UInt8] = []) throws -> [UInt8] {
        let funcSwid = ((function & 0x0F) << 4) | (SW_ID & 0x0F)

        var payload = [UInt8](repeating: 0, count: LONG_PAYLOAD_SIZE + 1)
        payload[0] = 0x11
        payload[1] = devIndex
        payload[2] = featureIndex
        payload[3] = funcSwid
        for (i, p) in params.prefix(16).enumerated() {
            payload[4 + i] = p
        }

        hidppLog("TX: \(payload.map { String(format: "%02X", $0) }.joined(separator: " "))")

        let sendStrategies: [(IOHIDReportType, String)] = [
            (kIOHIDReportTypeOutput, "output"),
            (kIOHIDReportTypeFeature, "feature"),
        ]

        var sendOK = false
        for (reportType, name) in sendStrategies {
            let ret = IOHIDDeviceSetReport(device, reportType, REPORT_ID_LONG, payload, payload.count)
            if ret == kIOReturnSuccess {
                hidppLog("Sent via \(name) report")
                sendOK = true
                break
            }
            hidppLog("\(name) report failed: \(ioReturnDesc(ret))")
        }
        guard sendOK else {
            throw HIDPPError(message: "SetReport failed with all report types")
        }

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
            hidppLog("RX: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")

            do {
                return try parseResponse(data, featureIndex: featureIndex, function: function)
            } catch let e as HIDPPError where e.message.hasPrefix("Response mismatch") {
                hidppLog("Skipping notification: \(e.message)")
                continue
            }
        }
        throw HIDPPError(message: "No matching HID++ response after 20 attempts")
    }

    private func parseResponse(_ data: [UInt8], featureIndex: UInt8, function: UInt8) throws -> [UInt8] {
        let rFeat = data[1]
        let rFunc = data[2]

        if rFeat == 0xFF {
            // HID++ 2.0 error: [devIdx, 0xFF, origFeat, origFunc|SW, errCode, ...]
            let errCode = data.count > 4 ? data[4] : 0
            let origFeat = data.count > 2 ? data[2] : 0
            let names: [UInt8: String] = [
                0: "NoError", 1: "Unknown", 2: "InvalidArgument", 3: "OutOfRange",
                4: "HWError", 5: "LogitechInternal", 6: "InvalidFeatureIndex",
                7: "InvalidFunctionID", 8: "Busy", 9: "Unsupported",
            ]
            let hex = data.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
            throw HIDPPError(message: "HID++ error: \(names[errCode] ?? "code \(errCode)") (feat=\(origFeat), raw=\(hex))")
        }

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
        hidppLog("Feature 0x\(String(featureID, radix: 16)) → index \(resp[0])")
        return resp[0]
    }

    // MARK: - Device Discovery

    static func findDevice() throws -> (IOHIDDevice, String) {
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

    static func openDevice() throws -> HIDPPDevice {
        let (dev, conn) = try findDevice()
        let name = IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String ?? "MX Master 3"

        let indicesToTry: [UInt8] = conn == "Bluetooth" ? [0xFF, 0x01, 0x00] : [0x01]

        for idx in indicesToTry {
            hidppLog("Trying \(name) via \(conn) devIndex=0x\(String(idx, radix: 16))...")
            let hidpp = HIDPPDevice(device: dev, devIndex: idx, connectionType: conn)
            try hidpp.open()

            do {
                let _ = try hidpp.resolveSmartShift()
                hidppLog("Success with devIndex=0x\(String(idx, radix: 16))")
                return hidpp
            } catch {
                hidppLog("devIndex 0x\(String(idx, radix: 16)) failed: \(error)")
                hidpp.close()
            }
        }
        throw HIDPPError(message: "Could not communicate with MX Master 3 on any device index")
    }
}
