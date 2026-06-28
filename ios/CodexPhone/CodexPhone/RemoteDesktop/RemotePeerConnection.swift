import Foundation
import WebRTC

final class RemotePeerConnection: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var latencyText = "--"

    func connect() {
        isConnected = true
        latencyText = "direct"
    }

    func suspend() {
        isConnected = false
        latencyText = "suspended"
    }

    func disconnect() {
        isConnected = false
        latencyText = "--"
    }
}
