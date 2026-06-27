import Foundation

enum RemoteDesktopSessionPhase: Equatable {
    case connecting
    case connected
    case reconnecting
    case suspended
    case failed(String)
    case disconnected
}

enum RemoteDesktopTransportPath: Equatable {
    case unknown
    case direct
    case relayed
}

struct RemoteDesktopSessionState: Equatable {
    let leaseID: String
    private(set) var phase: RemoteDesktopSessionPhase
    private(set) var transportPath: RemoteDesktopTransportPath
    private(set) var pendingInputs: [RemoteInputEvent]
    private var backgroundedAt: Date?
    private let backgroundGrace: TimeInterval

    init(leaseID: String, now: Date = Date(), backgroundGrace: TimeInterval = 30) {
        self.leaseID = leaseID
        self.phase = .connecting
        self.transportPath = .unknown
        self.pendingInputs = []
        self.backgroundedAt = nil
        self.backgroundGrace = backgroundGrace
    }

    mutating func connected(now: Date = Date()) {
        phase = .connected
        backgroundedAt = nil
    }

    mutating func enterBackground(now: Date = Date()) {
        phase = .suspended
        backgroundedAt = now
        pendingInputs.removeAll()
    }

    mutating func enterForeground(now: Date = Date()) {
        guard !shouldRequireNewLease(now: now) else {
            phase = .disconnected
            pendingInputs.removeAll()
            return
        }
        phase = .reconnecting
    }

    func shouldRequireNewLease(now: Date = Date()) -> Bool {
        guard let backgroundedAt else { return false }
        return now.timeIntervalSince(backgroundedAt) > backgroundGrace
    }

    mutating func enqueueInput(_ event: RemoteInputEvent) {
        guard phase == .connected else { return }
        pendingInputs.append(event)
    }

    mutating func updateTransportPath(_ path: RemoteDesktopTransportPath) {
        transportPath = path
    }

    mutating func disconnect() {
        phase = .disconnected
        transportPath = .unknown
        pendingInputs.removeAll()
        backgroundedAt = nil
    }
}
