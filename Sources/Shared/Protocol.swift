import Foundation

public let socketPath = "/var/run/mxratchet.sock"
public let prefsPath = "/etc/mxratchet.json"

public struct MXRequest: Codable, Sendable {
    public let action: String
    public let params: [String: Int]?

    public init(action: String, params: [String: Int]? = nil) {
        self.action = action
        self.params = params
    }
}

public struct MXResponse: Codable, Sendable {
    public let ok: Bool
    public let error: String?
    public let data: MouseState?

    public init(ok: Bool, error: String? = nil, data: MouseState? = nil) {
        self.ok = ok
        self.error = error
        self.data = data
    }
}

public struct MouseState: Codable, Sendable {
    public let batteryLevel: Int
    public let batteryCharging: Bool
    public let wheelMode: Int
    public let autoDisengage: Int
    public let dpi: Int
    public let dpiList: [Int]?

    public init(
        batteryLevel: Int,
        batteryCharging: Bool,
        wheelMode: Int,
        autoDisengage: Int,
        dpi: Int,
        dpiList: [Int]? = nil
    ) {
        self.batteryLevel = batteryLevel
        self.batteryCharging = batteryCharging
        self.wheelMode = wheelMode
        self.autoDisengage = autoDisengage
        self.dpi = dpi
        self.dpiList = dpiList
    }
}

public struct UserPreferences: Codable, Sendable {
    public var wheelMode: Int?
    public var autoDisengage: Int?
    public var dpi: Int?
    public var thumbWheelInverted: Int?
    public var hiResScroll: Int?
    public var scrollInverted: Int?

    public init(
        wheelMode: Int? = nil,
        autoDisengage: Int? = nil,
        dpi: Int? = nil,
        thumbWheelInverted: Int? = nil,
        hiResScroll: Int? = nil,
        scrollInverted: Int? = nil
    ) {
        self.wheelMode = wheelMode
        self.autoDisengage = autoDisengage
        self.dpi = dpi
        self.thumbWheelInverted = thumbWheelInverted
        self.hiResScroll = hiResScroll
        self.scrollInverted = scrollInverted
    }
}
