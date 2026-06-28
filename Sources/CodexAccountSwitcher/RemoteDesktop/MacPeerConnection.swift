import CoreGraphics
import Foundation
import LiveKitWebRTC

enum MacPeerConnectionState: Equatable {
    case idle
    case connecting(leaseID: String)
    case connected(leaseID: String)
    case disconnected(leaseID: String)
    case failed(leaseID: String)
}

struct MacPeerSignal: Codable, Equatable {
    enum Kind: String, Codable {
        case offer
        case answer
        case ice
    }

    let leaseID: String
    let sequence: UInt64
    let kind: Kind
    let payload: Data
}

enum MacPeerConnectionError: Error {
    case peerCreationFailed
    case sessionDescriptionFailed
}

final class MacPeerConnection: NSObject, LKRTCPeerConnectionDelegate {
    private(set) var state: MacPeerConnectionState = .idle
    private var activeLeaseID: String?
    private var lastRemoteSignalSequence: UInt64 = 0
    private var pendingLocalSignals: [MacPeerSignal] = []
    private let factory = LKRTCPeerConnectionFactory()
    private let captureService = ScreenCaptureService()
    private var peerConnection: LKRTCPeerConnection?
    private var videoSource: LKRTCVideoSource?
    private var videoTrack: LKRTCVideoTrack?
    private var frameAdapter: WebRTCFrameAdapter?

    func start(leaseID: String) {
        activeLeaseID = leaseID
        lastRemoteSignalSequence = 0
        pendingLocalSignals.removeAll()
        state = .connecting(leaseID: leaseID)
    }

    func markConnected() {
        guard let activeLeaseID else { return }
        state = .connected(leaseID: activeLeaseID)
    }

    func answer(offerSDP: String) async throws -> String {
        guard activeLeaseID != nil else { throw RemoteDesktopSecurityError.leaseUnknown }
        let configuration = LKRTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.continualGatheringPolicy = .gatherContinually
        let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peer = factory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: self
        ) else {
            throw MacPeerConnectionError.peerCreationFailed
        }
        peerConnection = peer

        let source = factory.videoSource(forScreenCast: true)
        let track = factory.videoTrack(with: source, trackId: "codepilot-screen")
        _ = peer.add(track, streamIds: ["codepilot-screen"])
        videoSource = source
        videoTrack = track
        let adapter = WebRTCFrameAdapter(delegate: source)
        frameAdapter = adapter
        try await captureService.start(displayID: CGMainDisplayID()) { [weak adapter] sampleBuffer in
            adapter?.consume(sampleBuffer)
        }

        let remote = LKRTCSessionDescription(type: .offer, sdp: offerSDP)
        try await setRemoteDescription(remote, on: peer)
        let answer = try await createAnswer(on: peer, constraints: constraints)
        try await setLocalDescription(answer, on: peer)
        try await Task.sleep(nanoseconds: 750_000_000)
        markConnected()
        return peer.localDescription?.sdp ?? answer.sdp
    }

    func acceptRemoteSignal(_ signal: MacPeerSignal) throws {
        guard signal.leaseID == activeLeaseID else {
            throw RemoteDesktopSecurityError.leaseUnknown
        }
        guard signal.sequence > lastRemoteSignalSequence else {
            throw RemoteDesktopSecurityError.sequenceReplay
        }
        lastRemoteSignalSequence = signal.sequence
    }

    func enqueueLocalSignal(kind: MacPeerSignal.Kind, payload: Data) throws {
        guard let activeLeaseID else {
            throw RemoteDesktopSecurityError.leaseUnknown
        }
        let sequence = UInt64(pendingLocalSignals.count + 1)
        pendingLocalSignals.append(MacPeerSignal(
            leaseID: activeLeaseID,
            sequence: sequence,
            kind: kind,
            payload: payload
        ))
    }

    func drainLocalSignals() -> [MacPeerSignal] {
        let signals = pendingLocalSignals
        pendingLocalSignals.removeAll()
        return signals
    }

    func disconnect() {
        captureService.stop()
        peerConnection?.close()
        peerConnection = nil
        frameAdapter = nil
        videoTrack = nil
        videoSource = nil
        if let activeLeaseID {
            state = .disconnected(leaseID: activeLeaseID)
        } else {
            state = .idle
        }
        activeLeaseID = nil
        pendingLocalSignals.removeAll()
        lastRemoteSignalSequence = 0
    }

    func fail() {
        captureService.stop()
        peerConnection?.close()
        peerConnection = nil
        frameAdapter = nil
        videoTrack = nil
        videoSource = nil
        if let activeLeaseID {
            state = .failed(leaseID: activeLeaseID)
        } else {
            state = .idle
        }
        activeLeaseID = nil
        pendingLocalSignals.removeAll()
        lastRemoteSignalSequence = 0
    }

    private func setRemoteDescription(_ description: LKRTCSessionDescription, on peer: LKRTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peer.setRemoteDescription(description) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func createAnswer(
        on peer: LKRTCPeerConnection,
        constraints: LKRTCMediaConstraints
    ) async throws -> LKRTCSessionDescription {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<LKRTCSessionDescription, Error>) in
            peer.answer(for: constraints) { description, error in
                if let error { continuation.resume(throwing: error) }
                else if let description { continuation.resume(returning: description) }
                else { continuation.resume(throwing: MacPeerConnectionError.sessionDescriptionFailed) }
            }
        }
    }

    private func setLocalDescription(_ description: LKRTCSessionDescription, on peer: LKRTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peer.setLocalDescription(description) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange stateChanged: LKRTCSignalingState) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove stream: LKRTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: LKRTCPeerConnection) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceConnectionState) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceGatheringState) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didGenerate candidate: LKRTCIceCandidate) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove candidates: [LKRTCIceCandidate]) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didOpen dataChannel: LKRTCDataChannel) {}
}
