import AppKit
import CoreGraphics
import Foundation

final class RemoteFrameCaptureService {
    enum CaptureError: Error {
        case unavailable
        case encodingFailed
    }

    func captureMainDisplayJPEG(maxPixelWidth: Int = 1600, quality: CGFloat = 0.62) throws -> Data {
        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else {
            throw CaptureError.unavailable
        }

        let sourceSize = CGSize(width: image.width, height: image.height)
        let outputSize: CGSize
        if sourceSize.width > CGFloat(maxPixelWidth) {
            let scale = CGFloat(maxPixelWidth) / sourceSize.width
            outputSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        } else {
            outputSize = sourceSize
        }
        return try jpegData(from: image, size: outputSize, quality: quality)
    }

    private func jpegData(from image: CGImage, size: CGSize, quality: CGFloat) throws -> Data {
        let output = NSImage(size: size)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .medium
        NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
            .draw(in: NSRect(origin: .zero, size: size))
        drawCursor(in: size)
        output.unlockFocus()

        guard let tiff = output.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            throw CaptureError.encodingFailed
        }
        return data
    }

    private func drawCursor(in outputSize: CGSize) {
        guard let mouseLocation = CGEvent(source: nil)?.location else { return }
        let displayBounds = CGDisplayBounds(CGMainDisplayID())
        guard displayBounds.contains(mouseLocation) else { return }

        let scaleX = outputSize.width / displayBounds.width
        let scaleY = outputSize.height / displayBounds.height
        let cursor = NSCursor.arrow
        let cursorSize = CGSize(
            width: max(18, cursor.image.size.width * scaleX),
            height: max(18, cursor.image.size.height * scaleY)
        )
        let x = (mouseLocation.x - displayBounds.minX) * scaleX - cursor.hotSpot.x * scaleX
        let yFromTop = (mouseLocation.y - displayBounds.minY) * scaleY - cursor.hotSpot.y * scaleY
        let rect = NSRect(
            x: x,
            y: outputSize.height - yFromTop - cursorSize.height,
            width: cursorSize.width,
            height: cursorSize.height
        )
        cursor.image.draw(in: rect)
    }
}
