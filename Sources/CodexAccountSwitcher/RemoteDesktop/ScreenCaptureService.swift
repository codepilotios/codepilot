import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

protocol ScreenCaptureServicing: AnyObject {
    func displays() async throws -> [RemoteDisplay]
    func start(displayID: CGDirectDisplayID, frameHandler: @escaping (CMSampleBuffer) -> Void) async throws
    func stop()
}

final class ScreenCaptureService: NSObject, ScreenCaptureServicing, SCStreamOutput, SCStreamDelegate {
    private var activeDisplayID: CGDirectDisplayID?
    private var stream: SCStream?
    private var frameHandler: ((CMSampleBuffer) -> Void)?
    private let captureQueue = DispatchQueue(label: "io.codepilot.remote-desktop.capture", qos: .userInteractive)

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

    @available(macOS 12.3, *)
    func start(
        displayID: CGDirectDisplayID = CGMainDisplayID(),
        frameHandler: @escaping (CMSampleBuffer) -> Void
    ) async throws {
        stop()
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureError.displayUnavailable
        }

        let scale = min(1, 1920.0 / Double(display.width))
        let configuration = SCStreamConfiguration()
        configuration.width = max(2, Int(Double(display.width) * scale) & ~1)
        configuration.height = max(2, Int(Double(display.height) * scale) & ~1)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        self.activeDisplayID = displayID
        self.frameHandler = frameHandler
        self.stream = stream
        try await stream.startCapture()
    }

    func stop() {
        let stream = self.stream
        self.stream = nil
        frameHandler = nil
        activeDisplayID = nil
        if let stream {
            Task { try? await stream.stopCapture() }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        frameHandler?(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        stop()
    }
}

enum ScreenCaptureError: Error {
    case displayUnavailable
}
