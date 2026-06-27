import CoreGraphics
import Foundation
import ScreenCaptureKit

protocol ScreenCaptureServicing: AnyObject {
    func displays() async throws -> [RemoteDisplay]
    func stop()
}

final class ScreenCaptureService: ScreenCaptureServicing {
    private var activeDisplayID: CGDirectDisplayID?

    @available(macOS 12.3, *)
    func displays() async throws -> [RemoteDisplay] {
        let content = try await SCShareableContent.current
        return content.displays.map { display in
            RemoteDisplay(
                id: display.displayID,
                name: display.displayID == CGMainDisplayID() ? "Main Display" : "Display \(display.displayID)",
                pixelWidth: display.width,
                pixelHeight: display.height,
                scale: 1,
                rotation: 0
            )
        }
    }

    func selectDisplay(_ displayID: CGDirectDisplayID) {
        activeDisplayID = displayID
    }

    func stop() {
        activeDisplayID = nil
    }
}
