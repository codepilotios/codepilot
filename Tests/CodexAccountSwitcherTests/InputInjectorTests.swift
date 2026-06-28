import CoreGraphics
import Foundation
import XCTest
@testable import CodexAccountSwitcher

final class InputInjectorTests: XCTestCase {
    func testMapsNormalizedPointToNegativeOriginDisplay() {
        let frame = CGRect(x: -1920, y: 0, width: 1920, height: 1080)

        XCTAssertEqual(
            DisplayCoordinateMapper.map(x: 0.5, y: 0.5, into: frame),
            CGPoint(x: -960, y: 540)
        )
    }

    func testClampsNormalizedCoordinatesToDisplayBounds() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 50)

        XCTAssertEqual(DisplayCoordinateMapper.map(x: -1, y: 2, into: frame), CGPoint(x: 10, y: 70))
    }

    func testRejectsInputWhenMacLockedOrLeaseInvalid() throws {
        let validator = FakeRemoteInputLeaseValidator()
        let sink = RecordingRemoteInputSink()
        let injector = RemoteInputInjector(validator: validator, sink: sink)
        let event = RemoteInputEvent(
            sessionId: "lease-1",
            sequence: 1,
            kind: .pointer,
            x: 0.5,
            y: 0.5,
            button: nil,
            keyCode: nil,
            text: nil,
            deltaX: nil,
            deltaY: nil
        )

        validator.isMacUnlocked = false
        XCTAssertThrowsError(try injector.handle(event, displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100)))
        XCTAssertTrue(sink.events.isEmpty)

        validator.isMacUnlocked = true
        validator.accepted = false
        XCTAssertThrowsError(try injector.handle(event, displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100)))
        XCTAssertTrue(sink.events.isEmpty)
    }

    func testRejectsStaleSequenceBeforePostingEvents() throws {
        let validator = FakeRemoteInputLeaseValidator()
        let sink = RecordingRemoteInputSink()
        let injector = RemoteInputInjector(validator: validator, sink: sink)
        let first = RemoteInputEvent(
            sessionId: "lease-1",
            sequence: 1,
            kind: .pointer,
            x: 0.25,
            y: 0.25,
            button: nil,
            keyCode: nil,
            text: nil,
            deltaX: nil,
            deltaY: nil
        )
        let replay = RemoteInputEvent(
            sessionId: "lease-1",
            sequence: 1,
            kind: .scroll,
            x: nil,
            y: nil,
            button: nil,
            keyCode: nil,
            text: nil,
            deltaX: 1,
            deltaY: 1
        )

        try injector.handle(first, displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertThrowsError(try injector.handle(replay, displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100)))

        XCTAssertEqual(sink.events.count, 1)
    }

    func testReleasesPressedStateOnDisconnect() throws {
        let sink = RecordingRemoteInputSink()
        let injector = RemoteInputInjector(validator: FakeRemoteInputLeaseValidator(), sink: sink)
        let keyDown = RemoteInputEvent(
            sessionId: "lease-1",
            sequence: 1,
            kind: .keyDown,
            x: nil,
            y: nil,
            button: nil,
            keyCode: 55,
            text: nil,
            deltaX: nil,
            deltaY: nil
        )
        let buttonDown = RemoteInputEvent(
            sessionId: "lease-1",
            sequence: 2,
            kind: .buttonDown,
            x: 0.5,
            y: 0.5,
            button: 0,
            keyCode: nil,
            text: nil,
            deltaX: nil,
            deltaY: nil
        )

        try injector.handle(keyDown, displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
        try injector.handle(buttonDown, displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
        injector.releaseAll()

        XCTAssertTrue(sink.events.contains(.keyUp(55)))
        XCTAssertTrue(sink.events.contains(.buttonUp(0, CGPoint(x: 50, y: 50))))
    }

    func testPointerWithDeltasMovesRelativeToCurrentCursor() throws {
        let sink = RecordingRemoteInputSink()
        sink.pointerPosition = CGPoint(x: 400, y: 300)
        let injector = RemoteInputInjector(validator: FakeRemoteInputLeaseValidator(), sink: sink)
        let event = RemoteInputEvent(
            sessionId: "lease-relative",
            sequence: 1,
            kind: .pointer,
            x: nil,
            y: nil,
            button: nil,
            keyCode: nil,
            text: nil,
            deltaX: 24,
            deltaY: -12
        )

        try injector.handle(event, displayFrame: CGRect(x: 0, y: 0, width: 1000, height: 800))

        XCTAssertEqual(sink.events, [.pointer(CGPoint(x: 424, y: 288))])
    }
}

final class FakeRemoteInputLeaseValidator: RemoteInputLeaseValidating {
    var isMacUnlocked = true
    var accepted = true
    private var lastSequence: UInt64 = 0

    func validateInput(sessionID: String, sequence: UInt64) throws {
        guard isMacUnlocked else { throw RemoteDesktopSecurityError.leaseExpired }
        guard accepted else { throw RemoteDesktopSecurityError.leaseUnknown }
        guard sequence > lastSequence else { throw RemoteDesktopSecurityError.sequenceReplay }
        lastSequence = sequence
    }
}

final class RecordingRemoteInputSink: RemoteInputPosting {
    enum Event: Equatable {
        case pointer(CGPoint)
        case buttonDown(Int, CGPoint)
        case buttonUp(Int, CGPoint)
        case scroll(Double, Double)
        case keyDown(UInt16)
        case keyUp(UInt16)
        case text(String)
    }

    var events: [Event] = []
    var pointerPosition: CGPoint = .zero

    func currentPointerPosition() -> CGPoint { pointerPosition }
    func movePointer(to point: CGPoint) {
        pointerPosition = point
        events.append(.pointer(point))
    }
    func buttonDown(_ button: Int, at point: CGPoint) { events.append(.buttonDown(button, point)) }
    func buttonUp(_ button: Int, at point: CGPoint) { events.append(.buttonUp(button, point)) }
    func scroll(deltaX: Double, deltaY: Double) { events.append(.scroll(deltaX, deltaY)) }
    func keyDown(_ keyCode: UInt16) { events.append(.keyDown(keyCode)) }
    func keyUp(_ keyCode: UInt16) { events.append(.keyUp(keyCode)) }
    func text(_ text: String) { events.append(.text(text)) }
}
