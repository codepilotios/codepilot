import Foundation
import XCTest
@testable import CodexAccountSwitcher

final class RemoteDesktopModelsTests: XCTestCase {
    func testCanonicalRemoteInputEventDecodes() throws {
        let fixture = #"{"sessionId":"s1","sequence":4,"kind":"pointer","x":0.25,"y":0.75,"button":0,"keyCode":null,"text":null,"deltaX":null,"deltaY":null}"#.data(using: .utf8)!

        let event = try JSONDecoder().decode(RemoteInputEvent.self, from: fixture)

        XCTAssertEqual(event.sessionId, "s1")
        XCTAssertEqual(event.sequence, 4)
        XCTAssertEqual(event.kind, .pointer)
        XCTAssertEqual(event.x, 0.25)
        XCTAssertEqual(event.y, 0.75)
        XCTAssertEqual(event.button, 0)
        XCTAssertNil(event.keyCode)
        XCTAssertNil(event.text)
        XCTAssertNil(event.deltaX)
        XCTAssertNil(event.deltaY)
    }

    func testEveryWireModelRoundTrips() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let device = TrustedRemoteDevice(
            id: "device-1",
            name: "iPhone",
            publicKeyRawRepresentation: Data([1, 2, 3, 4]),
            approvedAt: date,
            revokedAt: nil
        )
        let auditEvent = RemoteAuditEvent(
            id: "audit-1",
            timestamp: date,
            kind: "session.started",
            deviceId: device.id,
            sessionId: "session-1"
        )
        let auditRecord = RemoteDesktopAuditEvent(
            id: "audit-record-1",
            timestamp: date,
            kind: .leaseGranted,
            deviceId: device.id,
            sessionId: "session-1",
            leaseId: "lease-1",
            sequence: 11,
            reason: .busy
        )

        try assertRoundTrip(RemoteInputKind.keyDown)
        try assertRoundTrip(RemoteInputEvent(
            sessionId: "session-1",
            sequence: 9,
            kind: .scroll,
            x: 0.25,
            y: 0.75,
            button: nil,
            keyCode: nil,
            text: nil,
            deltaX: 1.5,
            deltaY: -2.5
        ))
        try assertRoundTrip(RemoteDisplay(
            id: 42,
            name: "Studio Display",
            pixelWidth: 5120,
            pixelHeight: 2880,
            scale: 2,
            rotation: 0
        ))
        try assertRoundTrip(RemotePairingChallenge(
            id: "challenge-1",
            code: "123456",
            macName: "Office Mac",
            expiresAt: date
        ))
        try assertRoundTrip(device)
        try assertRoundTrip(RemoteDesktopLease(
            id: "lease-1",
            deviceId: device.id,
            expiresAt: date
        ))
        try assertRoundTrip(RemoteSessionDescription(type: "offer", sdp: "v=0"))
        try assertRoundTrip(RemoteICECandidate(
            candidate: "candidate:1 1 UDP 1 192.0.2.1 5000 typ host",
            sdpMid: "0",
            sdpMLineIndex: 0
        ))
        try assertRoundTrip(RemoteClipboardDirection.send)
        try assertRoundTrip(RemoteClipboardRequest(
            sessionId: "session-1",
            direction: .send,
            text: "hello"
        ))
        try assertRoundTrip(auditEvent)
        try assertRoundTrip(RemoteAuditEventResponse(
            events: [auditEvent],
            nextCursor: "cursor-2"
        ))
        try assertRoundTrip(auditRecord)
    }

    func testDateAndDataUseStableWireRepresentations() throws {
        let device = TrustedRemoteDevice(
            id: "device-1",
            name: "iPhone",
            publicKeyRawRepresentation: Data([1, 2, 3, 4]),
            approvedAt: Date(timeIntervalSince1970: 1_700_000_000),
            revokedAt: nil
        )

        let data = try wireEncoder().encode(device)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["approvedAt"] as? String, "2023-11-14T22:13:20Z")
        XCTAssertEqual(json["publicKeyRawRepresentation"] as? String, "AQIDBA==")
        XCTAssertEqual(try wireDecoder().decode(TrustedRemoteDevice.self, from: data), device)
    }

    private func assertRoundTrip<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let encoded = try wireEncoder().encode(value)
        let decoded = try wireDecoder().decode(T.self, from: encoded)
        XCTAssertEqual(decoded, value, file: file, line: line)
    }

    private func wireEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        return encoder
    }

    private func wireDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        return decoder
    }
}
