import Foundation

// MARK: - Feature IDs

let FEATURE_SMARTSHIFT: UInt16 = 0x2110
let FEATURE_SMARTSHIFT_3G: UInt16 = 0x2111
let FEATURE_BATTERY_STATUS: UInt16 = 0x1000
let FEATURE_UNIFIED_BATTERY: UInt16 = 0x1004
let FEATURE_BATTERY_VOLTAGE: UInt16 = 0x1010
let FEATURE_ADJUSTABLE_DPI: UInt16 = 0x2201
let FEATURE_REPROG_CONTROLS: UInt16 = 0x1B04
let FEATURE_THUMBWHEEL: UInt16 = 0x2150
let FEATURE_HIRES_WHEEL: UInt16 = 0x2121

let MODE_FREESPIN: UInt8 = 1
let MODE_RATCHET: UInt8 = 2
let AUTO_DISENGAGE_ALWAYS: UInt8 = 0xFF

// MARK: - SmartShift

extension HIDPPDevice {
    func resolveSmartShift() throws -> UInt8 {
        for feat in [FEATURE_SMARTSHIFT_3G, FEATURE_SMARTSHIFT] {
            do {
                let idx = try resolveFeature(feat)
                hidppLog("SmartShift feature 0x\(String(feat, radix: 16)) → index \(idx)")
                return idx
            } catch {
                hidppLog("Feature 0x\(String(feat, radix: 16)): \(error)")
            }
        }
        throw HIDPPError(message: "SmartShift feature not found (tried 0x2110 and 0x2111)")
    }

    func getSmartShiftStatus() throws -> (mode: Int, autoDisengage: Int) {
        let idx = try resolveSmartShift()
        let resp = try request(featureIndex: idx, function: 0)
        return (Int(resp[0]), Int(resp[1]))
    }

    func setSmartShift(mode: UInt8, autoDisengage: UInt8) throws {
        let idx = try resolveSmartShift()
        try request(featureIndex: idx, function: 1, params: [mode, autoDisengage, 0])
    }
}

// MARK: - Battery

extension HIDPPDevice {
    func getBatteryStatus() throws -> (level: Int, charging: Bool) {
        // Try BatteryStatus (0x1000) first
        if let result = try? getBatteryVia1000() { return result }
        // Try UnifiedBattery (0x1004)
        if let result = try? getBatteryVia1004() { return result }
        // Try BatteryVoltage (0x1010)
        if let result = try? getBatteryVia1010() { return result }

        throw HIDPPError(message: "No battery feature supported (tried 0x1000, 0x1004, 0x1010)")
    }

    private func getBatteryVia1000() throws -> (level: Int, charging: Bool) {
        let idx = try resolveFeature(FEATURE_BATTERY_STATUS)
        let resp = try request(featureIndex: idx, function: 0)
        // resp[0] = battery level (0-100)
        // resp[2] = status: 0=discharging, 1=recharging, 2=charge almost done, 3=charge complete
        let level = Int(resp[0])
        let charging = resp.count > 2 && resp[2] >= 1 && resp[2] <= 2
        return (level, charging)
    }

    private func getBatteryVia1004() throws -> (level: Int, charging: Bool) {
        let idx = try resolveFeature(FEATURE_UNIFIED_BATTERY)
        let resp = try request(featureIndex: idx, function: 0)
        // resp[0] = state of charge (0-100)
        // resp[2] = status flags: bit 1=charging, bit 2=wireless charging
        let level = Int(resp[0])
        let charging = resp.count > 2 && (resp[2] & 0x06) != 0
        return (level, charging)
    }

    private func getBatteryVia1010() throws -> (level: Int, charging: Bool) {
        let idx = try resolveFeature(FEATURE_BATTERY_VOLTAGE)
        let resp = try request(featureIndex: idx, function: 0)
        // resp[0..1] = voltage in mV (big-endian)
        // resp[2] = flags: bit 7=charging
        let voltage = Int(resp[0]) << 8 | Int(resp[1])
        let level = max(0, min(100, (voltage - 3500) * 100 / 700))
        let charging = resp.count > 2 && (resp[2] & 0x80) != 0
        return (level, charging)
    }
}

// MARK: - DPI

extension HIDPPDevice {
    func getDPI() throws -> Int {
        let idx = try resolveFeature(FEATURE_ADJUSTABLE_DPI)
        // getSensorDpi(sensorIdx=0): returns [sensorIdx, dpiMSB, dpiLSB, ...]
        let resp = try request(featureIndex: idx, function: 1, params: [0])
        return Int(resp[1]) << 8 | Int(resp[2])
    }

    func setDPI(_ dpi: Int) throws {
        let idx = try resolveFeature(FEATURE_ADJUSTABLE_DPI)
        // setSensorDpi(sensorIdx=0, dpiMSB, dpiLSB)
        try request(featureIndex: idx, function: 2,
                    params: [0, UInt8(dpi >> 8), UInt8(dpi & 0xFF)])
    }

    func getDPIList() throws -> [Int] {
        let idx = try resolveFeature(FEATURE_ADJUSTABLE_DPI)
        // getSensorDpiList(sensorIdx=0)
        let resp = try request(featureIndex: idx, function: 3, params: [0])

        // Parse DPI entries from response (starting at byte 1, byte 0 = sensorIdx echo)
        var discreteValues: [Int] = []
        var stepValue: Int?
        var i = 1
        while i + 1 < resp.count {
            let raw = Int(resp[i]) << 8 | Int(resp[i + 1])
            if raw == 0 { break }
            if raw & 0x8000 != 0 {
                stepValue = raw & 0x7FFF
            } else {
                discreteValues.append(raw)
            }
            i += 2
        }

        // Range-based: [minDPI, maxDPI] + step → generate list
        if let step = stepValue, step > 0, discreteValues.count >= 2 {
            let minDPI = discreteValues[0]
            let maxDPI = discreteValues[1]
            var list: [Int] = []
            var d = minDPI
            while d <= maxDPI {
                list.append(d)
                d += step
            }
            return list
        }

        // Discrete values
        if !discreteValues.isEmpty {
            return discreteValues
        }

        // Fallback: common MX Master 3 DPI values
        return [200, 400, 800, 1000, 1200, 1600, 2000, 2400, 3200, 4000]
    }
}

// MARK: - ReprogControlsV4 (Button Diversion)

extension HIDPPDevice {
    func divertButton(cid: UInt16) throws {
        let idx = try resolveFeature(FEATURE_REPROG_CONTROLS)
        // setCidReporting fn3: (cidMSB, cidLSB, flags)
        // flags: bit0=temp divert(T), bit2=raw XY(R), bit4=update(U)
        // T=1, R=1, U=1 → 0x15
        try request(featureIndex: idx, function: 3,
                    params: [UInt8(cid >> 8), UInt8(cid & 0xFF), 0x15])
        hidppLog("Diverted button CID 0x\(String(cid, radix: 16))")
    }

    func undivertButton(cid: UInt16) throws {
        let idx = try resolveFeature(FEATURE_REPROG_CONTROLS)
        // Clear T and R, set U: 0x10
        try request(featureIndex: idx, function: 3,
                    params: [UInt8(cid >> 8), UInt8(cid & 0xFF), 0x10])
        hidppLog("Undiverted button CID 0x\(String(cid, radix: 16))")
    }
}

// MARK: - Thumb Wheel

extension HIDPPDevice {
    func getThumbwheelInfo() throws -> (nativeRes: Int, divertedRes: Int) {
        let idx = try resolveFeature(FEATURE_THUMBWHEEL)
        let resp = try request(featureIndex: idx, function: 0)
        let native = Int(resp[0]) << 8 | Int(resp[1])
        let diverted = Int(resp[2]) << 8 | Int(resp[3])
        return (native, diverted)
    }

    func setThumbwheelMode(diverted: Bool, inverted: Bool) throws {
        let idx = try resolveFeature(FEATURE_THUMBWHEEL)
        var flags: UInt8 = 0
        if diverted { flags |= 0x01 }
        if inverted { flags |= 0x02 }
        try request(featureIndex: idx, function: 2, params: [flags])
    }
}

// MARK: - Hi-Res Scroll Wheel

extension HIDPPDevice {
    func getHiResWheelInfo() throws -> (hiRes: Bool, inverted: Bool) {
        let idx = try resolveFeature(FEATURE_HIRES_WHEEL)
        let resp = try request(featureIndex: idx, function: 0)
        let hiRes = (resp[0] & 0x02) != 0
        let inverted = (resp[0] & 0x04) != 0
        return (hiRes, inverted)
    }

    func setHiResWheel(hiRes: Bool, inverted: Bool) throws {
        let idx = try resolveFeature(FEATURE_HIRES_WHEEL)
        var flags: UInt8 = 0
        if hiRes { flags |= 0x02 }
        if inverted { flags |= 0x04 }
        try request(featureIndex: idx, function: 1, params: [flags])
    }
}
