import Foundation

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

final class MacPeerConnection {
    private(set) var state: MacPeerConnectionState = .idle
    private var activeLeaseID: String?
    private var lastRemoteSignalSequence: UInt64 = 0
    private var pendingLocalSignals: [MacPeerSignal] = []

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
        if let activeLeaseID {
            state = .failed(leaseID: activeLeaseID)
        } else {
            state = .idle
        }
        activeLeaseID = nil
        pendingLocalSignals.removeAll()
        lastRemoteSignalSequence = 0
    }
}
