import Darwin
import Foundation

final class RemoteDesktopSocketServer {
    static let defaultSocketURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codepilot/remote-desktop/host.sock")

    private static let supportedMethods: Set<String> = [
        "status",
        "pairing.start",
        "pairing.complete",
        "devices.list",
        "devices.revoke",
        "session.nonce",
        "session.start",
        "session.signal",
        "session.end",
        "session.display",
        "session.clipboard",
        "audit.list"
    ]

    private enum LineReadResult {
        case line(Data)
        case oversized
        case closed
    }

    private let socketURL: URL
    private let maxRequestBytes: Int
    private let handler: (HostRPCRequest) -> HostRPCResponse
    private let stateLock = NSLock()
    private var listenFD: Int32 = -1
    private var running = false

    init(
        socketURL: URL = RemoteDesktopSocketServer.defaultSocketURL,
        maxRequestBytes: Int = 1_048_576,
        handler: @escaping (HostRPCRequest) -> HostRPCResponse
    ) {
        self.socketURL = socketURL
        self.maxRequestBytes = max(1, maxRequestBytes)
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() throws {
        stateLock.lock()
        defer { stateLock.unlock() }

        if running {
            return
        }

        try prepareSocketDirectory()
        try removeStaleSocketIfNeeded()
        let fd = try createListener()
        listenFD = fd
        running = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        stateLock.lock()
        let fd = listenFD
        listenFD = -1
        let shouldUnlink = running
        running = false
        stateLock.unlock()

        if fd >= 0 {
            close(fd)
        }
        if shouldUnlink {
            unlink(socketURL.path)
        }
    }

    private func acceptLoop() {
        while isRunning {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                if !isRunning || errno == EBADF || errno == EINVAL {
                    break
                }
                if errno == EINTR {
                    continue
                }
                continue
            }

            configureClientSocket(clientFD)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleClient(clientFD)
            }
        }
    }

    private var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running
    }

    private func handleClient(_ clientFD: Int32) {
        defer { close(clientFD) }

        do {
            switch try readRequestLine(from: clientFD) {
            case .closed:
                return
            case .oversized:
                try writeResponse(HostRPCResponse(
                    id: UUID(),
                    status: 413,
                    payload: Data(),
                    errorCode: "request_too_large"
                ), to: clientFD)
            case .line(let data):
                let decoder = JSONDecoder()
                do {
                    let request = try decoder.decode(HostRPCRequest.self, from: data)
                    guard Self.supportedMethods.contains(request.method) else {
                        try writeResponse(HostRPCResponse(
                            id: request.id,
                            status: 404,
                            payload: Data(),
                            errorCode: "unsupported_method"
                        ), to: clientFD)
                        return
                    }

                    let response = handler(request)
                    try writeResponse(HostRPCResponse(
                        id: request.id,
                        status: response.status,
                        payload: response.payload,
                        errorCode: response.errorCode
                    ), to: clientFD)
                } catch {
                    try writeResponse(HostRPCResponse(
                        id: UUID(),
                        status: 400,
                        payload: Data(),
                        errorCode: "invalid_json"
                    ), to: clientFD)
                }
            }
        } catch {
            return
        }
    }

    private func readRequestLine(from fd: Int32) throws -> LineReadResult {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var data = Data()
        var oversized = false

        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if count == 0 {
                return data.isEmpty ? .closed : (oversized ? .oversized : .line(data))
            }

            for byte in buffer.prefix(count) {
                if byte == 0x0A {
                    return oversized ? .oversized : .line(data)
                }
                if oversized {
                    continue
                }
                if data.count < maxRequestBytes {
                    data.append(byte)
                } else {
                    oversized = true
                }
            }
        }
    }

    private func writeResponse(_ response: HostRPCResponse, to fd: Int32) throws {
        let encoded = try JSONEncoder().encode(response) + Data([0x0A])
        try encoded.withUnsafeBytes { buffer in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else {
                throw POSIXError(.EINVAL)
            }
            var offset = 0
            while offset < encoded.count {
                let written = send(fd, base.advanced(by: offset), encoded.count - offset, 0)
                if written < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                offset += written
            }
        }
    }

    private func configureClientSocket(_ clientFD: Int32) {
        var one: Int32 = 1
        _ = setsockopt(
            clientFD,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &one,
            socklen_t(MemoryLayout.size(ofValue: one))
        )

        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        _ = setsockopt(
            clientFD,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout.size(ofValue: timeout))
        )
    }

    private func prepareSocketDirectory() throws {
        let directoryURL = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
    }

    private func removeStaleSocketIfNeeded() throws {
        var fileInfo = stat()
        let result = lstat(socketURL.path, &fileInfo)
        if result != 0 {
            return
        }

        if (fileInfo.st_mode & S_IFMT) != S_IFSOCK {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTSOCK), userInfo: nil)
        }

        switch try probeSocketState() {
        case .live:
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EADDRINUSE), userInfo: nil)
        case .stale:
            if unlink(socketURL.path) != 0 && errno != ENOENT {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        case .ambiguous(let error):
            throw error
        }
    }

    private enum SocketState {
        case live
        case stale
        case ambiguous(Error)
    }

    private func probeSocketState() throws -> SocketState {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketURL.path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            return .ambiguous(NSError(domain: NSPOSIXErrorDomain, code: Int(ENAMETOOLONG), userInfo: nil))
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            if let base = buffer.baseAddress {
                pathBytes.withUnsafeBytes { source in
                    if let sourceBase = source.baseAddress {
                        memcpy(base, sourceBase, pathBytes.count)
                    }
                }
            }
        }

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result == 0 {
            return .live
        }

        let code = errno
        switch code {
        case ECONNREFUSED, ENOENT:
            return .stale
        default:
            return .ambiguous(POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO))
        }
    }

    private func createListener() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketURL.path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENAMETOOLONG), userInfo: nil)
        }

        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            if let base = buffer.baseAddress {
                pathBytes.withUnsafeBytes { source in
                    if let sourceBase = source.baseAddress {
                        memcpy(base, sourceBase, pathBytes.count)
                    }
                }
            }
        }

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }

        guard Darwin.listen(fd, 4) == 0 else {
            let code = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: socketURL.path
        )

        return fd
    }
}
