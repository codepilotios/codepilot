import CoreMedia
import Foundation
import LiveKitWebRTC

final class WebRTCFrameAdapter {
    private let capturer: LKRTCVideoCapturer
    private weak var delegate: LKRTCVideoCapturerDelegate?

    init(delegate: LKRTCVideoCapturerDelegate) {
        self.delegate = delegate
        self.capturer = LKRTCVideoCapturer(delegate: delegate)
    }

    func consume(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let buffer = LKRTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timeStampNs = Int64(CMTimeGetSeconds(timestamp) * 1_000_000_000)
        let frame = LKRTCVideoFrame(buffer: buffer, rotation: ._0, timeStampNs: timeStampNs)
        delegate?.capturer(capturer, didCapture: frame)
    }
}
