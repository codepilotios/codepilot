import Foundation
import XCTest
@testable import CodexPhone

final class RemoteDesktopTests: XCTestCase {
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

    func testSoftwareIdentitySignsAndVerifiesFixture() throws {
        let identity = SoftwareRemoteDeviceIdentity(deviceID: "device-1")
        let message = Data("challenge-code".utf8)
        let signature = try identity.sign(message)

        XCTAssertEqual(identity.deviceID, "device-1")
        XCTAssertFalse(identity.publicKeyRawRepresentation.isEmpty)
        XCTAssertTrue(try identity.verify(signature: signature, message: message))
        XCTAssertFalse(try identity.verify(signature: signature, message: Data("other".utf8)))
    }

    func testRemoteDesktopAPIMapsRevokedDeviceAndPairingExpiry() async throws {
        let revokedAPI = RemoteDesktopAPI(
            baseURL: URL(string: "https://gateway.example")!,
            token: "token"
        ) { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            let data = #"{"error":"untrusted_device"}"#.data(using: .utf8)!
            return (data, HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!)
        }

        do {
            _ = try await revokedAPI.startSession(deviceID: "device-1", nonce: "nonce", signature: Data([1]))
            XCTFail("Expected revoked device failure")
        } catch RemoteDesktopAPIError.server(let status, let code) {
            XCTAssertEqual(status, 403)
            XCTAssertEqual(code, "untrusted_device")
        }

        let expiredAPI = RemoteDesktopAPI(
            baseURL: URL(string: "https://gateway.example")!,
            token: "token"
        ) { request in
            let data = #"{"error":"pairing_expired"}"#.data(using: .utf8)!
            return (data, HTTPURLResponse(url: request.url!, statusCode: 410, httpVersion: nil, headerFields: nil)!)
        }

        do {
            _ = try await expiredAPI.completePairing(challengeID: "challenge-1", deviceID: "device-1", signature: Data([1]))
            XCTFail("Expected expired pairing failure")
        } catch RemoteDesktopAPIError.server(let status, let code) {
            XCTAssertEqual(status, 410)
            XCTAssertEqual(code, "pairing_expired")
        }
    }

    func testRemoteDesktopAPISendsInputEvent() async throws {
        let event = RemoteInputEvent(
            sessionId: "gateway-session",
            sequence: 3,
            kind: .pointer,
            x: 0.25,
            y: 0.75,
            button: nil,
            keyCode: nil,
            text: nil,
            deltaX: nil,
            deltaY: nil
        )
        let api = RemoteDesktopAPI(
            baseURL: URL(string: "https://gateway.example")!,
            token: "token"
        ) { request in
            XCTAssertEqual(request.url?.path, "/api/remote/input")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            XCTAssertEqual(try JSONDecoder().decode(RemoteInputEvent.self, from: request.httpBody!), event)
            return (
                #"{"ok":true}"#.data(using: .utf8)!,
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }

        let acknowledgement = try await api.sendInput(event)
        XCTAssertTrue(acknowledgement.ok)
    }

    func testRemoteDesktopStatusDecodesDisplayFrameAndCursor() throws {
        let data = #"{"ok":true,"displayFrame":{"width":2560,"height":1440},"cursor":{"x":0.25,"y":0.75}}"#.data(using: .utf8)!

        let status = try JSONDecoder().decode(RemoteDesktopHostStatus.self, from: data)

        XCTAssertEqual(status.displayFrame, RemoteDisplayFrame(width: 2560, height: 1440))
        XCTAssertEqual(status.cursor, RemoteCursorPosition(x: 0.25, y: 0.75))
    }

    func testRemotePeerCursorUpdateDecodes() throws {
        let data = #"{"cursor":{"x":0.4,"y":0.6}}"#.data(using: .utf8)!

        let update = try JSONDecoder().decode(RemotePeerCursorUpdate.self, from: data)

        XCTAssertEqual(update, RemotePeerCursorUpdate(cursor: .init(x: 0.4, y: 0.6)))
    }

    func testRemoteInputMapperCreatesMonotonicNormalizedEvents() {
        var mapper = RemoteInputMapper(sessionID: "lease-1")

        let tap = mapper.tap(at: CGPoint(x: 50, y: 25), in: CGSize(width: 100, height: 100))
        let drag = mapper.drag(to: CGPoint(x: 25, y: 75), in: CGSize(width: 100, height: 100))
        let scroll = mapper.scroll(delta: CGSize(width: 3, height: -4))

        XCTAssertEqual(tap.sequence, 1)
        XCTAssertEqual(tap.kind, .pointer)
        XCTAssertEqual(tap.x, 0.5)
        XCTAssertEqual(tap.y, 0.25)
        XCTAssertEqual(drag.sequence, 2)
        XCTAssertEqual(drag.x, 0.25)
        XCTAssertEqual(drag.y, 0.75)
        XCTAssertEqual(scroll.sequence, 3)
        XCTAssertEqual(scroll.kind, .scroll)
        XCTAssertEqual(scroll.deltaX, 3)
        XCTAssertEqual(scroll.deltaY, -4)
    }

    func testRemoteDesktopSessionBackgroundGraceAndDisconnectCleanup() {
        var session = RemoteDesktopSessionState(leaseID: "lease-1", now: Date(timeIntervalSince1970: 100))

        session.connected(now: Date(timeIntervalSince1970: 101))
        session.updateTransportPath(.direct)
        XCTAssertEqual(session.transportPath, .direct)
        session.enterBackground(now: Date(timeIntervalSince1970: 110))
        XCTAssertEqual(session.phase, .suspended)
        XCTAssertFalse(session.shouldRequireNewLease(now: Date(timeIntervalSince1970: 130)))
        XCTAssertTrue(session.shouldRequireNewLease(now: Date(timeIntervalSince1970: 141)))

        session.enterForeground(now: Date(timeIntervalSince1970: 130))
        XCTAssertEqual(session.phase, .reconnecting)
        session.updateTransportPath(.relayed)
        XCTAssertEqual(session.transportPath, .relayed)

        session.disconnect()
        XCTAssertEqual(session.phase, .disconnected)
        XCTAssertEqual(session.transportPath, .unknown)
        XCTAssertTrue(session.pendingInputs.isEmpty)
    }

    func testViewportCentersCursorAndClampsAtDisplayEdges() {
        let container = CGSize(width: 100, height: 100)
        let image = CGSize(width: 100, height: 100)

        var viewport = RemoteViewport(zoom: 2, cursor: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(viewport.offset(container: container, image: image), .zero)
        XCTAssertEqual(viewport.cursorPosition(container: container, image: image), CGPoint(x: 50, y: 50))

        viewport.cursor = CGPoint(x: 0.75, y: 0.5)
        XCTAssertEqual(viewport.offset(container: container, image: image), CGSize(width: -50, height: 0))
        XCTAssertEqual(viewport.cursorPosition(container: container, image: image), CGPoint(x: 50, y: 50))

        viewport.cursor = CGPoint(x: 1, y: 1)
        XCTAssertEqual(viewport.offset(container: container, image: image), CGSize(width: -50, height: -50))
        XCTAssertEqual(viewport.cursorPosition(container: container, image: image), CGPoint(x: 100, y: 100))
    }

    func testViewportPointerPredictionUsesMacDisplayCoordinateSpace() {
        var viewport = RemoteViewport(cursor: CGPoint(x: 0.5, y: 0.5))

        viewport.applyPointerDelta(
            CGSize(width: 100, height: -50),
            coordinateSize: CGSize(width: 1_000, height: 500),
            sensitivity: 1
        )

        XCTAssertEqual(viewport.cursor.x, 0.6, accuracy: 0.0001)
        XCTAssertEqual(viewport.cursor.y, 0.4, accuracy: 0.0001)
    }

    func testViewportConvertsScreenDeltaToRemoteDeltaUsingZoomAndRotationLayout() {
        let image = CGSize(width: 1_920, height: 1_080)

        let portrait = RemoteViewport(zoom: 1).remoteDelta(
            forScreenDelta: CGSize(width: 10, height: 10),
            container: CGSize(width: 390, height: 844),
            image: image
        )
        XCTAssertEqual(portrait.width, 49.2308, accuracy: 0.0001)
        XCTAssertEqual(portrait.height, 49.2308, accuracy: 0.0001)

        let landscapeZoomed = RemoteViewport(zoom: 2).remoteDelta(
            forScreenDelta: CGSize(width: 10, height: 10),
            container: CGSize(width: 844, height: 390),
            image: image
        )
        XCTAssertEqual(landscapeZoomed.width, 13.8462, accuracy: 0.0001)
        XCTAssertEqual(landscapeZoomed.height, 13.8462, accuracy: 0.0001)
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
