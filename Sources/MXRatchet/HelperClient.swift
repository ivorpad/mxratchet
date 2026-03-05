import Foundation
import Shared

actor HelperClient {
    func sendRequest(_ request: MXRequest) async throws -> MXResponse {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw HelperError.connectionFailed("socket() failed: errno \(errno)")
        }
        defer { Darwin.close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let sunPathMaxLen = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cstr in
                _ = memcpy(UnsafeMutableRawPointer(ptr), cstr, min(strlen(cstr) + 1, sunPathMaxLen))
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw HelperError.connectionFailed("connect() failed: errno \(errno)")
        }

        // Send JSON request + newline
        var data = try JSONEncoder().encode(request)
        data.append(UInt8(ascii: "\n"))
        let sent = data.withUnsafeBytes { ptr in
            Darwin.send(fd, ptr.baseAddress!, ptr.count, 0)
        }
        guard sent == data.count else {
            throw HelperError.sendFailed
        }

        // Read response until newline
        var responseData = Data()
        var byte: UInt8 = 0
        while Darwin.recv(fd, &byte, 1, 0) == 1 {
            if byte == UInt8(ascii: "\n") { break }
            responseData.append(byte)
            if responseData.count > 8192 { break }
        }

        guard !responseData.isEmpty else {
            throw HelperError.emptyResponse
        }

        return try JSONDecoder().decode(MXResponse.self, from: responseData)
    }

    func getStatus(includeDPIList: Bool = false) async throws -> MXResponse {
        try await sendRequest(MXRequest(
            action: "getStatus",
            params: includeDPIList ? ["includeDPIList": 1] : nil
        ))
    }

    func setWheelMode(_ mode: Int, autoDisengage: Int? = nil) async throws -> MXResponse {
        var params = ["mode": mode]
        if let ad = autoDisengage { params["autoDisengage"] = ad }
        return try await sendRequest(MXRequest(action: "setWheelMode", params: params))
    }

    func setDPI(_ dpi: Int) async throws -> MXResponse {
        try await sendRequest(MXRequest(action: "setDPI", params: ["dpi": dpi]))
    }

    func divertButton(cid: Int) async throws -> MXResponse {
        try await sendRequest(MXRequest(action: "divertButton", params: ["cid": cid]))
    }

    func undivertButton(cid: Int) async throws -> MXResponse {
        try await sendRequest(MXRequest(action: "undivertButton", params: ["cid": cid]))
    }

    func setThumbWheel(diverted: Bool = false, inverted: Bool) async throws -> MXResponse {
        try await sendRequest(MXRequest(action: "setThumbWheel", params: [
            "diverted": diverted ? 1 : 0,
            "inverted": inverted ? 1 : 0,
        ]))
    }

    func setHiResScroll(hiRes: Bool, inverted: Bool) async throws -> MXResponse {
        try await sendRequest(MXRequest(action: "setHiResScroll", params: [
            "hiRes": hiRes ? 1 : 0,
            "inverted": inverted ? 1 : 0,
        ]))
    }
}

enum HelperError: Error, LocalizedError {
    case connectionFailed(String)
    case sendFailed
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Helper not running: \(msg)"
        case .sendFailed: return "Failed to send request to helper"
        case .emptyResponse: return "No response from helper"
        }
    }
}
