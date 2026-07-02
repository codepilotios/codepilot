import Foundation

final class RemoteDesktopAuditLog {
    typealias Clock = () -> Date

    private let fileURL: URL
    private let clock: Clock
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil, clock: @escaping Clock = Date.init) throws {
        self.fileURL = fileURL ?? Self.defaultAuditLogURL()
        self.clock = clock
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder.dateDecodingStrategy = .iso8601
        try Self.ensureStorage(for: self.fileURL)
    }

    func append(_ event: RemoteDesktopAuditEvent) throws {
        lock.lock()
        defer { lock.unlock() }

        try Self.validate(event)
        try Self.ensureStorage(for: fileURL)
        var stamped = event
        if stamped.timestamp == .distantPast {
            stamped = RemoteDesktopAuditEvent(
                id: event.id,
                timestamp: clock(),
                kind: event.kind,
                deviceId: event.deviceId,
                sessionId: event.sessionId,
                leaseId: event.leaseId,
                sequence: event.sequence,
                reason: event.reason
            )
        }

        let line = try encoder.encode(stamped)
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.write(contentsOf: Data([0x0A]))
        try Self.ensureFilePermissions(fileURL)
    }

    func loadAll() throws -> [RemoteDesktopAuditEvent] {
        lock.lock()
        defer { lock.unlock() }

        let contents = try Data(contentsOf: fileURL)
        guard !contents.isEmpty else {
            return []
        }

        let segments = contents.split(separator: UInt8(0x0A), omittingEmptySubsequences: false)
        let hasTrailingNewline = contents.last == UInt8(0x0A)
        var events: [RemoteDesktopAuditEvent] = []

        for (index, segment) in segments.enumerated() {
            if segment.isEmpty {
                continue
            }
            do {
                events.append(try decoder.decode(RemoteDesktopAuditEvent.self, from: Data(segment)))
            } catch {
                let isLastSegment = index == segments.count - 1
                guard isLastSegment, !hasTrailingNewline else {
                    throw error
                }
                break
            }
        }

        return events
    }

    private static func defaultAuditLogURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codepilot/remote-desktop/audit.jsonl")
    }

    private static func ensureStorage(for fileURL: URL) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try ensureDirectoryPermissions(directoryURL)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: [.posixPermissions: 0o600])
        }
        try ensureFilePermissions(fileURL)
    }

    private static func ensureDirectoryPermissions(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private static func ensureFilePermissions(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func validate(_ event: RemoteDesktopAuditEvent) throws {
        let identifiers = [
            event.id,
            event.deviceId,
            event.sessionId,
            event.leaseId
        ].compactMap { $0 }

        guard identifiers.allSatisfy({ isAllowedIdentifier($0) }) else {
            throw RemoteDesktopSecurityError.prohibitedAuditContent
        }
    }

    private static func isAllowedIdentifier(_ value: String) -> Bool {
        let normalized = value.lowercased()
        let prohibitedMarkers = [
            "screen content",
            "screencontent",
            "keystroke",
            "clipboard value",
            "clipboardvalue",
            "bearer",
            "private key",
            "privatekey",
            "turn secret",
            "turnsecret",
            "file contents",
            "filecontents",
            "password",
            "secret",
            "token"
        ]

        guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return false
        }
        return !prohibitedMarkers.contains(where: { normalized.contains($0) })
    }
}
