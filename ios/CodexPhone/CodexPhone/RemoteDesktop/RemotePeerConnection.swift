import Foundation
import WebRTC

enum RemotePeerError: Error {
    case peerCreationFailed
    case offerCreationFailed
    case missingLocalDescription
    case missingAnswer
}

final class RemotePeerConnection: NSObject, ObservableObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate {
    @Published private(set) var isConnected = false
    @Published private(set) var isInputReady = false
    @Published private(set) var latencyText = "--"
    @Published private(set) var videoTrack: RTCVideoTrack?

    private let factory = RTCPeerConnectionFactory()
    private var peerConnection: RTCPeerConnection?
    private var inputDataChannel: RTCDataChannel?
    private var sessionID = ""

    @MainActor
    func connect(api: RemoteDesktopAPI) async throws {
        disconnect()
        sessionID = UUID().uuidString
        latencyText = "connecting"

        let status = try await api.status()
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.continualGatheringPolicy = .gatherContinually
        configuration.iceServers = (status.iceServers ?? []).map { server in
            RTCIceServer(
                urlStrings: server.urls,
                username: server.username,
                credential: server.credential
            )
        }
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue],
            optionalConstraints: nil
        )
        guard let peer = factory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: self
        ) else {
            throw RemotePeerError.peerCreationFailed
        }
        peerConnection = peer
        let dataConfiguration = RTCDataChannelConfiguration()
        dataConfiguration.isOrdered = false
        dataConfiguration.maxRetransmits = 0
        if let dataChannel = peer.dataChannel(forLabel: "codepilot-input", configuration: dataConfiguration) {
            dataChannel.delegate = self
            inputDataChannel = dataChannel
        }

        let offer = try await createOffer(on: peer, constraints: constraints)
        try await setLocalDescription(offer, on: peer)
        try await Task.sleep(nanoseconds: 750_000_000)
        guard let local = peer.localDescription else { throw RemotePeerError.missingLocalDescription }
        let signals = try await api.sendSignal(
            sessionID: sessionID,
            sequence: 1,
            kind: .offer,
            payload: Data(local.sdp.utf8)
        )
        guard let answerSignal = signals.first(where: { $0.kind == .answer }),
              let answerSDP = String(data: answerSignal.payload, encoding: .utf8) else {
            throw RemotePeerError.missingAnswer
        }
        try await setRemoteDescription(
            RTCSessionDescription(type: .answer, sdp: answerSDP),
            on: peer
        )
    }

    func connect() {
        latencyText = "connecting"
    }

    func suspend() {
        isConnected = false
        isInputReady = false
        latencyText = "suspended"
    }

    func disconnect() {
        inputDataChannel?.delegate = nil
        inputDataChannel?.close()
        inputDataChannel = nil
        peerConnection?.close()
        peerConnection = nil
        videoTrack = nil
        isConnected = false
        isInputReady = false
        latencyText = "--"
    }

    func sendInput(_ event: RemoteInputEvent) -> Bool {
        guard let inputDataChannel, inputDataChannel.readyState == .open else {
            return false
        }
        do {
            let data = try JSONEncoder().encode(event)
            return inputDataChannel.sendData(RTCDataBuffer(data: data, isBinary: false))
        } catch {
            return false
        }
    }

    private func createOffer(
        on peer: RTCPeerConnection,
        constraints: RTCMediaConstraints
    ) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { continuation in
            peer.offer(for: constraints) { description, error in
                if let error { continuation.resume(throwing: error) }
                else if let description { continuation.resume(returning: description) }
                else { continuation.resume(throwing: RemotePeerError.offerCreationFailed) }
            }
        }
    }

    private func setLocalDescription(_ description: RTCSessionDescription, on peer: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peer.setLocalDescription(description) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func setRemoteDescription(_ description: RTCSessionDescription, on peer: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peer.setRemoteDescription(description) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        DispatchQueue.main.async {
            self.isInputReady = dataChannel.readyState == .open
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        DispatchQueue.main.async {
            self.isConnected = newState == .connected
            self.latencyText = newState == .connected ? "WebRTC" : String(describing: newState)
        }
    }

    func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd rtpReceiver: RTCRtpReceiver,
        streams: [RTCMediaStream]
    ) {
        guard let track = rtpReceiver.track as? RTCVideoTrack else { return }
        DispatchQueue.main.async {
            self.videoTrack = track
        }
    }
}
