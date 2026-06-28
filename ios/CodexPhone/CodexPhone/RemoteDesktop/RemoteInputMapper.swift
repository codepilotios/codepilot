import CoreGraphics
import Foundation

struct RemoteInputMapper {
    private(set) var sessionID: String
    private var nextSequence: UInt64 = 1

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    mutating func tap(at point: CGPoint, in size: CGSize) -> RemoteInputEvent {
        pointer(kind: .pointer, point: point, size: size)
    }

    mutating func drag(to point: CGPoint, in size: CGSize) -> RemoteInputEvent {
        pointer(kind: .pointer, point: point, size: size)
    }

    mutating func moveRelative(delta: CGSize, sensitivity: CGFloat = 1.35) -> RemoteInputEvent {
        make(
            kind: .pointer,
            deltaX: Double(delta.width * sensitivity),
            deltaY: Double(delta.height * sensitivity)
        )
    }

    mutating func buttonDown(at point: CGPoint, in size: CGSize, button: Int = 0) -> RemoteInputEvent {
        pointer(kind: .buttonDown, point: point, size: size, button: button)
    }

    mutating func buttonUp(at point: CGPoint, in size: CGSize, button: Int = 0) -> RemoteInputEvent {
        pointer(kind: .buttonUp, point: point, size: size, button: button)
    }

    mutating func buttonDown(button: Int = 0) -> RemoteInputEvent {
        make(kind: .buttonDown, button: button)
    }

    mutating func buttonUp(button: Int = 0) -> RemoteInputEvent {
        make(kind: .buttonUp, button: button)
    }

    mutating func scroll(delta: CGSize) -> RemoteInputEvent {
        make(kind: .scroll, deltaX: delta.width, deltaY: delta.height)
    }

    mutating func keyDown(_ keyCode: UInt16) -> RemoteInputEvent {
        make(kind: .keyDown, keyCode: keyCode)
    }

    mutating func keyUp(_ keyCode: UInt16) -> RemoteInputEvent {
        make(kind: .keyUp, keyCode: keyCode)
    }

    mutating func text(_ text: String) -> RemoteInputEvent {
        make(kind: .text, text: text)
    }

    private mutating func pointer(
        kind: RemoteInputKind,
        point: CGPoint,
        size: CGSize,
        button: Int? = nil
    ) -> RemoteInputEvent {
        make(
            kind: kind,
            x: normalized(point.x, size.width),
            y: normalized(point.y, size.height),
            button: button
        )
    }

    private mutating func make(
        kind: RemoteInputKind,
        x: Double? = nil,
        y: Double? = nil,
        button: Int? = nil,
        keyCode: UInt16? = nil,
        text: String? = nil,
        deltaX: Double? = nil,
        deltaY: Double? = nil
    ) -> RemoteInputEvent {
        defer { nextSequence += 1 }
        return RemoteInputEvent(
            sessionId: sessionID,
            sequence: nextSequence,
            kind: kind,
            x: x,
            y: y,
            button: button,
            keyCode: keyCode,
            text: text,
            deltaX: deltaX,
            deltaY: deltaY
        )
    }

    private func normalized(_ value: CGFloat, _ dimension: CGFloat) -> Double {
        guard dimension > 0 else { return 0 }
        return min(1, max(0, Double(value / dimension)))
    }
}
