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
        output.unlockFocus()

        guard let tiff = output.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            throw CaptureError.encodingFailed
        }
        return data
    }

}
