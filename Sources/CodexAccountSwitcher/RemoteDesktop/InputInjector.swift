import CoreGraphics
import Foundation

enum DisplayCoordinateMapper {
    static func map(x: Double, y: Double, into frame: CGRect) -> CGPoint {
        let clampedX = min(1, max(0, x))
        let clampedY = min(1, max(0, y))
        return CGPoint(
            x: frame.minX + frame.width * clampedX,
            y: frame.minY + frame.height * clampedY
        )
    }
}

protocol RemoteInputLeaseValidating: AnyObject {
    func validateInput(sessionID: String, sequence: UInt64) throws
}

protocol RemoteInputPosting: AnyObject {
    func currentPointerPosition() -> CGPoint
    func movePointer(to point: CGPoint)
    func buttonDown(_ button: Int, at point: CGPoint)
    func buttonUp(_ button: Int, at point: CGPoint)
    func scroll(deltaX: Double, deltaY: Double)
    func keyDown(_ keyCode: UInt16)
    func keyUp(_ keyCode: UInt16)
    func text(_ text: String)
}

final class RemoteInputInjector {
    private let validator: RemoteInputLeaseValidating
    private let sink: RemoteInputPosting
    private var pressedKeys = Set<UInt16>()
    private var pressedButtons: [Int: CGPoint] = [:]

    init(validator: RemoteInputLeaseValidating, sink: RemoteInputPosting = CGEventRemoteInputSink()) {
        self.validator = validator
        self.sink = sink
    }

    func handle(_ event: RemoteInputEvent, displayFrame: CGRect) throws {
        try validator.validateInput(sessionID: event.sessionId, sequence: event.sequence)

        switch event.kind {
        case .pointer:
            if let deltaX = event.deltaX, let deltaY = event.deltaY, event.x == nil, event.y == nil {
                let current = sink.currentPointerPosition()
                sink.movePointer(to: CGPoint(
                    x: min(displayFrame.maxX, max(displayFrame.minX, current.x + deltaX)),
                    y: min(displayFrame.maxY, max(displayFrame.minY, current.y + deltaY))
                ))
            } else {
                sink.movePointer(to: try point(for: event, displayFrame: displayFrame))
            }
        case .buttonDown:
            let button = event.button ?? 0
            let point = try pointOrCurrent(for: event, displayFrame: displayFrame)
            if event.x != nil || event.y != nil {
                sink.movePointer(to: point)
            }
            pressedButtons[button] = point
            sink.buttonDown(button, at: point)
        case .buttonUp:
            let button = event.button ?? 0
            let point = try pointOrCurrent(for: event, displayFrame: displayFrame)
            if event.x != nil || event.y != nil {
                sink.movePointer(to: point)
            }
            pressedButtons.removeValue(forKey: button)
            sink.buttonUp(button, at: point)
        case .scroll:
            sink.scroll(deltaX: event.deltaX ?? 0, deltaY: event.deltaY ?? 0)
        case .keyDown:
            guard let keyCode = event.keyCode else { throw RemoteDesktopSecurityError.invalidSignature }
            pressedKeys.insert(keyCode)
            sink.keyDown(keyCode)
        case .keyUp:
            guard let keyCode = event.keyCode else { throw RemoteDesktopSecurityError.invalidSignature }
            pressedKeys.remove(keyCode)
            sink.keyUp(keyCode)
        case .text:
            guard let text = event.text else { throw RemoteDesktopSecurityError.invalidSignature }
            sink.text(text)
        }
    }

    func releaseAll() {
        for key in pressedKeys.sorted() {
            sink.keyUp(key)
        }
        pressedKeys.removeAll()

        for button in pressedButtons.keys.sorted() {
            sink.buttonUp(button, at: pressedButtons[button] ?? .zero)
        }
        pressedButtons.removeAll()
    }

    private func point(for event: RemoteInputEvent, displayFrame: CGRect) throws -> CGPoint {
        guard let x = event.x, let y = event.y else {
            throw RemoteDesktopSecurityError.invalidSignature
        }
        return DisplayCoordinateMapper.map(x: x, y: y, into: displayFrame)
    }

    private func pointOrCurrent(for event: RemoteInputEvent, displayFrame: CGRect) throws -> CGPoint {
        if event.x == nil, event.y == nil {
            return sink.currentPointerPosition()
        }
        return try point(for: event, displayFrame: displayFrame)
    }
}

final class CGEventRemoteInputSink: RemoteInputPosting {
    func currentPointerPosition() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    func movePointer(to point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    func buttonDown(_ button: Int, at point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: mouseType(for: button, down: true), mouseCursorPosition: point, mouseButton: mouseButton(for: button))?
            .post(tap: .cghidEventTap)
    }

    func buttonUp(_ button: Int, at point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: mouseType(for: button, down: false), mouseCursorPosition: point, mouseButton: mouseButton(for: button))?
            .post(tap: .cghidEventTap)
    }

    func scroll(deltaX: Double, deltaY: Double) {
        CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(deltaY),
            wheel2: Int32(deltaX),
            wheel3: 0
        )?.post(tap: .cghidEventTap)
    }

    func keyDown(_ keyCode: UInt16) {
        CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)?
            .post(tap: .cghidEventTap)
    }

    func keyUp(_ keyCode: UInt16) {
        CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)?
            .post(tap: .cghidEventTap)
    }

    func text(_ text: String) {
        let utf16 = Array(text.utf16)
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        utf16.withUnsafeBufferPointer { buffer in
            event?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: buffer.baseAddress)
        }
        event?.post(tap: .cghidEventTap)
    }

    private func mouseButton(for button: Int) -> CGMouseButton {
        switch button {
        case 1: return .right
        case 2: return .center
        default: return .left
        }
    }

    private func mouseType(for button: Int, down: Bool) -> CGEventType {
        switch mouseButton(for: button) {
        case .right:
            return down ? .rightMouseDown : .rightMouseUp
        case .center:
            return down ? .otherMouseDown : .otherMouseUp
        default:
            return down ? .leftMouseDown : .leftMouseUp
        }
    }
}
