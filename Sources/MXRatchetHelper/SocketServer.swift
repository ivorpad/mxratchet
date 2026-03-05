import Foundation
import Shared

class SocketServer {
    let path: String
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?
    var onRequest: ((MXRequest) -> MXResponse)?

    init(path: String) {
        self.path = path
    }

    func start() throws {
        // Remove stale socket
        unlink(path)

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            throw HIDPPError(message: "socket() failed: errno \(errno)")
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let sunPathMaxLen = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            path.withCString { cstr in
                _ = memcpy(UnsafeMutableRawPointer(ptr), cstr, min(strlen(cstr) + 1, sunPathMaxLen))
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(listenFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let err = errno
            Darwin.close(listenFD)
            throw HIDPPError(message: "bind(\(path)) failed: errno \(err)")
        }

        // Allow non-root users (the menu bar app) to connect
        chmod(path, 0o666)

        guard listen(listenFD, 5) == 0 else {
            let err = errno
            Darwin.close(listenFD)
            throw HIDPPError(message: "listen() failed: errno \(err)")
        }

        source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: .global())
        source?.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source?.resume()
    }

    private func acceptConnection() {
        let clientFD = accept(listenFD, nil, nil)
        guard clientFD >= 0 else { return }

        DispatchQueue.global().async { [weak self] in
            self?.handleClient(clientFD)
        }
    }

    private func handleClient(_ fd: Int32) {
        defer { Darwin.close(fd) }

        // Read until newline
        var buffer = Data()
        var byte: UInt8 = 0
        while recv(fd, &byte, 1, 0) == 1 {
            if byte == UInt8(ascii: "\n") { break }
            buffer.append(byte)
            if buffer.count > 8192 { break } // sanity limit
        }

        guard !buffer.isEmpty else { return }

        let response: MXResponse
        do {
            let request = try JSONDecoder().decode(MXRequest.self, from: buffer)
            response = onRequest?(request) ?? MXResponse(ok: false, error: "No handler")
        } catch {
            response = MXResponse(ok: false, error: "Invalid request: \(error.localizedDescription)")
        }

        guard let data = try? JSONEncoder().encode(response) else { return }
        var payload = data
        payload.append(UInt8(ascii: "\n"))
        payload.withUnsafeBytes { ptr in
            _ = Darwin.send(fd, ptr.baseAddress!, ptr.count, 0)
        }
    }

    func stop() {
        source?.cancel()
        source = nil
        if listenFD >= 0 {
            Darwin.close(listenFD)
            listenFD = -1
        }
        unlink(path)
    }
}
