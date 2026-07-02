import Foundation
import XCTest
@testable import CodexAccountSwitcher

final class RemoteDesktopAuditLogTests: XCTestCase {
    func testAuditLogRejectsUnsafeIdentifiersBeforeWriting() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = rootURL.appendingPathComponent("audit.jsonl")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let log = try RemoteDesktopAuditLog(fileURL: fileURL, clock: { Date(timeIntervalSince1970: 1_700_000_123) })
        let unsafeEvent = RemoteDesktopAuditEvent(
            id: "event-bearing-bearer-secret",
            timestamp: Date(timeIntervalSince1970: 1_700_000_123),
            kind: .leaseGranted,
            deviceId: "device-1",
            sessionId: "session-1",
            leaseId: "lease-1",
            sequence: 7,
            reason: .busy
        )

        XCTAssertThrowsError(try log.append(unsafeEvent)) { error in
            XCTAssertEqual(error as? RemoteDesktopSecurityError, .prohibitedAuditContent)
        }
        XCTAssertEqual((try Data(contentsOf: fileURL)).count, 0)
    }

    func testAuditLogIgnoresTruncatedTrailingRecord() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = rootURL.appendingPathComponent("audit.jsonl")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let validEvent = RemoteDesktopAuditEvent(
            id: "event-1",
            timestamp: Date(timeIntervalSince1970: 1_700_000_123),
            kind: .leaseGranted,
            deviceId: "device-1",
            sessionId: "session-1",
            leaseId: "lease-1",
            sequence: 7,
            reason: .busy
        )
        let truncatedTail = #"{"id":"event-2","timestamp":"2024-01-01T00:00:00Z","kind":"leaseGranted","deviceId":"device-1""#
        let log = try RemoteDesktopAuditLog(fileURL: fileURL)
        try log.append(validEvent)
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: truncatedTail.data(using: .utf8)!)

        let decoded = try log.loadAll()

        XCTAssertEqual(decoded, [validEvent])
    }

    func testAuditLogThrowsWhenUnderlyingFileReadFails() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = rootURL.appendingPathComponent("audit.jsonl")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let log = try RemoteDesktopAuditLog(fileURL: fileURL)
        try FileManager.default.removeItem(at: fileURL)

        XCTAssertThrowsError(try log.loadAll())
    }

    func testAuditLogUsesOwnerOnlyPermissionsAndRedactsSensitiveShapes() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = rootURL.appendingPathComponent("audit.jsonl")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let timestamp = Date(timeIntervalSince1970: 1_700_000_123)
        let log = try RemoteDesktopAuditLog(fileURL: fileURL, clock: { timestamp })
        let event = RemoteDesktopAuditEvent(
            id: "event-1",
            timestamp: timestamp,
            kind: .leaseGranted,
            deviceId: "device-1",
            sessionId: "session-1",
            leaseId: "lease-1",
            sequence: 7,
            reason: .busy
        )

        try log.append(event)

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains(#""kind":"leaseGranted""#))
        for forbidden in ["screenContent", "keystroke", "clipboardValue", "bearerToken", "privateKey", "turnSecret", "fileContents"] {
            XCTAssertFalse(contents.contains(forbidden), "Found prohibited content: \(forbidden)")
        }

        let decoded = try log.loadAll()
        XCTAssertEqual(decoded, [event])

        let directoryPermissions = try posixPermissions(for: rootURL)
        let filePermissions = try posixPermissions(for: fileURL)
        XCTAssertEqual(directoryPermissions, 0o700)
        XCTAssertEqual(filePermissions, 0o600)

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL), options: [])
        let record = try XCTUnwrap(json as? [String: Any])
        XCTAssertEqual(Set(record.keys), ["deviceId", "id", "kind", "leaseId", "reason", "sequence", "sessionId", "timestamp"])
    }

    private func posixPermissions(for url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
