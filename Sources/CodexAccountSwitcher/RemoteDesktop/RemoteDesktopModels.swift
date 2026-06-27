import Foundation

enum RemoteInputKind: String, Codable {
    case pointer
    case buttonDown
    case buttonUp
    case scroll
    case keyDown
    case keyUp
    case text
}

struct RemoteInputEvent: Codable, Equatable {
    let sessionId: String
    let sequence: UInt64
    let kind: RemoteInputKind
    let x: Double?
    let y: Double?
    let button: Int?
    let keyCode: UInt16?
    let text: String?
    let deltaX: Double?
    let deltaY: Double?
}

struct RemoteDisplay: Codable, Equatable, Identifiable {
    let id: UInt32
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: Double
    let rotation: Double
}

struct RemotePairingChallenge: Codable, Equatable, Identifiable {
    let id: String
    let code: String
    let macName: String
    let expiresAt: Date
}

struct TrustedRemoteDevice: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    let publicKeyRawRepresentation: Data
    let approvedAt: Date
    var revokedAt: Date?
}

struct RemoteDesktopLease: Codable, Equatable, Identifiable {
    let id: String
    let deviceId: String
    let expiresAt: Date
}

struct RemoteSessionDescription: Codable, Equatable {
    let type: String
    let sdp: String
}

struct RemoteICECandidate: Codable, Equatable {
    let candidate: String
    let sdpMid: String?
    let sdpMLineIndex: Int32?
}

enum RemoteClipboardDirection: String, Codable {
    case send
    case receive
}

struct RemoteClipboardRequest: Codable, Equatable {
    let sessionId: String
    let direction: RemoteClipboardDirection
    let text: String?
}

struct RemoteAuditEvent: Codable, Equatable, Identifiable {
    let id: String
    let timestamp: Date
    let kind: String
    let deviceId: String?
    let sessionId: String?
}

struct RemoteAuditEventResponse: Codable, Equatable {
    let events: [RemoteAuditEvent]
    let nextCursor: String?
}

enum RemoteDesktopAuditEventKind: String, Codable {
    case pairingChallengeIssued
    case pairingChallengeVerified
    case pairingApproved
    case deviceRevoked
    case nonceIssued
    case nonceConsumed
    case leaseGranted
    case leaseRenewed
    case leaseEnded
    case sequenceAccepted
    case sequenceRejected
    case controllerBusy
    case clipboardRequested
    case displayChanged
}

enum RemoteDesktopAuditReason: String, Codable {
    case expired
    case used
    case invalidSignature
    case revoked
    case busy
    case replay
    case unauthorized
    case leaseExpired
}

struct RemoteDesktopAuditEvent: Codable, Equatable, Identifiable {
    let id: String
    let timestamp: Date
    let kind: RemoteDesktopAuditEventKind
    let deviceId: String?
    let sessionId: String?
    let leaseId: String?
    let sequence: UInt64?
    let reason: RemoteDesktopAuditReason?
}

struct HostRPCRequest: Codable, Equatable {
    let id: UUID
    let method: String
    let payload: Data
}

struct HostRPCResponse: Codable, Equatable {
    let id: UUID
    let status: Int
    let payload: Data
    let errorCode: String?
}
