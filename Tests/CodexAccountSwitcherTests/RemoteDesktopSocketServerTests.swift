import Darwin
import Foundation
import XCTest
@testable import CodexAccountSwitcher

final class RemoteDesktopSocketServerTests: XCTestCase {
    func testDispatchesRequestAndReturnsResponse() throws {
        let socketURL = try makeSocketURL()
        let received = LockedValue<HostRPCRequest?>(nil)
        let server = try makeServer(socketURL: socketURL) { request in
            received.set(request)
            return HostRPCResponse(
                id: request.id,
                status: 200,
                payload: Data(#"{"ok":true}"#.utf8),
                errorCode: nil
            )
        }
        defer { server.stop() }

        let response = try call(socketURL: socketURL, request: HostRPCRequest(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            method: "status",
            payload: Data(#"{"detail":"ready"}"#.utf8)
        ))

        let request = try XCTUnwrap(received.value)
        XCTAssertEqual(request.method, "status")
        XCTAssertEqual(request.payload, Data(#"{"detail":"ready"}"#.utf8))
        XCTAssertEqual(response.id, request.id)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.payload, Data(#"{"ok":true}"#.utf8))
        XCTAssertNil(response.errorCode)
    }

    func testRejectsMalformedAndOversizedRequestsWithoutStoppingServer() throws {
        let socketURL = try makeSocketURL()
        let server = try makeServer(socketURL: socketURL, maxRequestBytes: 256) { request in
            HostRPCResponse(id: request.id, status: 200, payload: nil, errorCode: nil)
        }
        defer { server.stop() }

        let malformedResponse = try sendRawLine("{\"method\":\"status\"\n", to: socketURL)
        XCTAssertEqual(malformedResponse.status, 400)
        XCTAssertEqual(malformedResponse.errorCode, "invalid_json")
        XCTAssertNil(malformedResponse.payload)

        let unsupportedRequest = try JSONEncoder().encode(HostRPCRequest(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            method: "status.debug",
            payload: nil
        )) + Data([0x0A])
        let unsupportedResponse = try sendLine(unsupportedRequest, to: socketURL)
        XCTAssertEqual(unsupportedResponse.status, 404)
        XCTAssertEqual(unsupportedResponse.errorCode, "unsupported_method")
        XCTAssertNil(unsupportedResponse.payload)

        let oversizedRequest = String(repeating: "x", count: 512)
        let oversizedResponse = try sendRawLine(oversizedRequest + "\n", to: socketURL)
        XCTAssertEqual(oversizedResponse.status, 413)
        XCTAssertEqual(oversizedResponse.errorCode, "request_too_large")
        XCTAssertNil(oversizedResponse.payload)

        let response = try call(socketURL: socketURL, request: HostRPCRequest(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            method: "status",
            payload: nil
        ))

        XCTAssertEqual(response.status, 200)
        XCTAssertNil(response.errorCode)
    }

    func testSocketPathAndParentDirectoryAreOwnerOnly() throws {
        let socketURL = try makeSocketURL()
        let server = try makeServer(socketURL: socketURL) { request in
            HostRPCResponse(id: request.id, status: 200, payload: nil, errorCode: nil)
        }
        defer { server.stop() }

        let directoryPermissions = try permissions(at: socketURL.deletingLastPathComponent())
        let socketPermissions = try permissions(at: socketURL)

        XCTAssertEqual(directoryPermissions, 0o700)
        XCTAssertEqual(socketPermissions, 0o600)
    }

    private func makeServer(
        socketURL: URL,
        maxRequestBytes: Int = 1_048_576,
        handler: @escaping (HostRPCRequest) -> HostRPCResponse
    ) throws -> RemoteDesktopSocketServer {
        let server = RemoteDesktopSocketServer(socketURL: socketURL, maxRequestBytes: maxRequestBytes, handler: handler)
        try server.start()
        addTeardownBlock { server.stop() }
        return server
    }

    private func makeSocketURL() throws -> URL {
        let base = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("codex-rds-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("remote-desktop.sock")
    }

    private func call(socketURL: URL, request: HostRPCRequest) throws -> HostRPCResponse {
        let data = try JSONEncoder().encode(request) + Data([0x0A])
        return try sendLine(data, to: socketURL)
    }

    private func sendRawLine(_ line: String, to socketURL: URL) throws -> HostRPCResponse {
        try sendLine(Data(line.utf8), to: socketURL)
    }

    private func sendLine(_ line: Data, to socketURL: URL) throws -> HostRPCResponse {
        let fd = try connectToSocket(socketURL)
        defer { close(fd) }

        try writeAll(fd: fd, data: line)

        let responseData = try readResponseLine(fd: fd)
        return try JSONDecoder().decode(HostRPCResponse.self, from: responseData)
    }

    private func connectToSocket(_ socketURL: URL) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOTSUP) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = Array(socketURL.path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENAMETOOLONG), userInfo: nil)
        }

        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            _ = pathBytes.withUnsafeBytes { source in
                memcpy(buffer.baseAddress, source.baseAddress, pathBytes.count)
            }
        }

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .ENOTCONN)
        }

        return fd
    }

    private func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL), userInfo: nil)
            }
            var offset = 0
            while offset < data.count {
                let written = Darwin.write(fd, base.advanced(by: offset), data.count - offset)
                if written < 0 {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                offset += written
            }
        }
    }

    private func readResponseLine(fd: Int32) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var response = Data()
        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count < 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if count == 0 {
                break
            }
            response.append(contentsOf: buffer.prefix(count))
            if response.contains(0x0A) {
                break
            }
        }
        guard let newlineIndex = response.firstIndex(of: 0x0A) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EPROTO), userInfo: nil)
        }
        return response.prefix(upTo: newlineIndex)
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber).map { $0.intValue } ?? -1
    }
}

private final class LockedValue<Value> {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        self.storage = value
    }

    func set(_ newValue: Value) {
        lock.lock()
        storage = newValue
        lock.unlock()
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
