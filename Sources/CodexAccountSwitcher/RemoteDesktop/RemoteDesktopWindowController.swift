import AppKit
import Foundation

final class RemoteDesktopWindowController: NSWindowController {
    private let coordinator: RemoteDesktopCoordinator
    private let contentStack = NSStackView()

    init(coordinator: RemoteDesktopCoordinator) {
        self.coordinator = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CodePilot Remote Desktop"
        super.init(window: window)
        buildContent()
        refresh()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        coordinator.refreshStatus()
        refresh()
        super.showWindow(sender)
    }

    private func buildContent() {
        guard let window else { return }
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = contentStack
        window.contentView = scrollView

        NSLayoutConstraint.activate([
            contentStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor, constant: -36)
        ])
    }

    private func refresh() {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let snapshot = coordinator.snapshot
        addSection("Permissions", rows: [
            "Screen Recording: \(snapshot.screenRecordingGranted ? "Granted" : "Missing")",
            "Accessibility: \(snapshot.accessibilityGranted ? "Granted" : "Missing")",
            "Mac unlocked: \(snapshot.macUnlocked ? "Yes" : "No")",
            "Screen Recording lets the iPhone view this Mac. Accessibility enables pointer and keyboard control."
        ])
        var permissionActions: [(String, Selector)] = []
        if !snapshot.screenRecordingGranted {
            permissionActions.append(("Allow Screen Recording", #selector(requestScreenRecordingPermission)))
        }
        if !snapshot.accessibilityGranted {
            permissionActions.append(("Allow Accessibility", #selector(requestAccessibilityPermission)))
        }
        if !permissionActions.isEmpty {
            addButtonRow(permissionActions)
        }

        if let pending = snapshot.pendingPairing {
            addSection("Pending Pairing", rows: [
                "Device: \(pending.name)",
                "Status: \(pending.approvalToken == nil ? "Waiting for iPhone proof" : "Ready for Mac approval")",
                "Code: \(pending.challenge.code)",
                "Expires: \(Self.dateFormatter.string(from: pending.challenge.expiresAt))",
                "Key: \(pending.keyFingerprint)"
            ])
            addButtonRow([
                ("Approve", #selector(approvePendingPairing)),
                ("Reject", #selector(rejectPendingPairing))
            ])
        } else {
            addSection("Pending Pairing", rows: ["None"])
        }

        let trustedRows = snapshot.trustedDevices.isEmpty
            ? ["No trusted devices"]
            : snapshot.trustedDevices.map { device in
                let status = device.revokedAt == nil ? "Trusted" : "Revoked"
                return "\(device.name) (\(device.id)) - \(status)"
            }
        addSection("Trusted Devices", rows: trustedRows)
        addTrustedDeviceActions(snapshot.trustedDevices)

        if let active = snapshot.activeSession {
            addSection("Active Controller", rows: [
                "Device: \(active.deviceID)",
                "Lease: \(active.leaseID)",
                "Started: \(Self.dateFormatter.string(from: active.startedAt))"
            ])
            addButtonRow([("Emergency Disconnect", #selector(emergencyDisconnect))])
        } else {
            addSection("Active Controller", rows: ["None"])
        }

        let auditRows = snapshot.auditEvents.suffix(12).map { event in
            "\(Self.dateFormatter.string(from: event.timestamp))  \(event.kind.rawValue)"
        }
        addSection("Audit", rows: auditRows.isEmpty ? ["No audit events"] : auditRows)
    }

    private func addSection(_ title: String, rows: [String]) {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 13)
        contentStack.addArrangedSubview(titleLabel)

        for row in rows {
            let label = NSTextField(labelWithString: row)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            contentStack.addArrangedSubview(label)
        }
    }

    private func addButtonRow(_ buttons: [(String, Selector)]) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        for (title, action) in buttons {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            row.addArrangedSubview(button)
        }
        contentStack.addArrangedSubview(row)
    }

    private func addTrustedDeviceActions(_ devices: [TrustedRemoteDevice]) {
        let activeDevices = devices.filter { $0.revokedAt == nil }
        guard !activeDevices.isEmpty else { return }

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        for device in activeDevices {
            let button = NSButton(title: "Revoke \(device.name)", target: self, action: #selector(revokeDevice(_:)))
            button.bezelStyle = .rounded
            button.identifier = NSUserInterfaceItemIdentifier(device.id)
            row.addArrangedSubview(button)
        }
        contentStack.addArrangedSubview(row)
    }

    @objc private func approvePendingPairing() {
        try? coordinator.approvePendingPairing()
        refresh()
    }

    @objc private func requestScreenRecordingPermission() {
        coordinator.requestScreenRecordingPermission()
        refresh()
    }

    @objc private func requestAccessibilityPermission() {
        coordinator.requestAccessibilityPermission()
        refresh()
    }

    @objc private func rejectPendingPairing() {
        coordinator.rejectPendingPairing()
        refresh()
    }

    @objc private func emergencyDisconnect() {
        coordinator.emergencyDisconnect()
        refresh()
    }

    @objc private func revokeDevice(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        try? coordinator.revokeDevice(id: id)
        refresh()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}
