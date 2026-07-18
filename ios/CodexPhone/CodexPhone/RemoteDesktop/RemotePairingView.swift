import SwiftUI
import UIKit

struct RemotePairingView: View {
    let gatewayURL: String
    let gatewayToken: String
    @Environment(\.dismiss) private var dismiss
    @State private var statusText = "Not paired"
    @State private var isLoading = false
    @State private var identity = SoftwareRemoteDeviceIdentity(deviceID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString)

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac") {
                    Text(statusText)
                    Text("Start Pairing signs a one-time challenge from the Mac gateway using this device key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Device") {
                    LabeledContent("Device ID", value: identity.deviceID)
                    LabeledContent("Public key", value: identity.publicKeyRawRepresentation.base64EncodedString())
                        .textSelection(.enabled)
                }

                Section {
                    NavigationLink {
                        RemoteDesktopView(gatewayURL: gatewayURL, gatewayToken: gatewayToken)
                    } label: {
                        Label("Start Session", systemImage: "play.rectangle")
                    }
                    .disabled(!canStartRemoteDesktop(statusText: statusText))

                    Button {
                        Task { await refreshStatus() }
                    } label: {
                        Label("Refresh Status", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)

                    Button {
                        Task { await startPairing() }
                    } label: {
                        Label("Start Pairing", systemImage: "desktopcomputer")
                    }
                    .disabled(isLoading || gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Remote Desktop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
            .task {
                await refreshStatus()
            }
        }
    }

    private func refreshStatus() async {
        guard let api = api() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let status = try await api.status()
            if status.screenRecordingGranted == false || status.accessibilityGranted == false {
                let missing = [
                    status.screenRecordingGranted == false ? "Screen Recording" : nil,
                    status.accessibilityGranted == false ? "Accessibility" : nil
                ].compactMap { $0 }.joined(separator: " and ")
                statusText = "Allow \(missing) for CodePilot on the Mac"
            } else if (status.trustedDeviceCount ?? 0) > 0 {
                statusText = "Paired with this Mac"
            } else if status.capabilities?.relayAvailable == true {
                statusText = "Not paired"
            } else {
                statusText = "Not paired"
            }
        } catch {
            statusText = remotePairingRecoveryMessage(error)
        }
    }

    private func startPairing() async {
        guard let api = api() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let challenge = try await api.startPairing(
                deviceID: identity.deviceID,
                name: UIDevice.current.name,
                publicKey: identity.publicKeyRawRepresentation
            )
            let signature = try identity.sign(Data(challenge.code.utf8))
            let approval = try await api.completePairing(
                challengeID: challenge.id,
                deviceID: identity.deviceID,
                signature: signature
            )
            statusText = "Paired with \(challenge.macName)"
        } catch {
            statusText = remotePairingRecoveryMessage(error)
        }
    }

    private func api() -> RemoteDesktopAPI? {
        guard let url = GatewayEndpoint.baseURL(from: gatewayURL),
              !gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return RemoteDesktopAPI(baseURL: url, token: gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

func remotePairingRecoveryMessage(_ error: Error) -> String {
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet:
            return "This iPhone is offline. Reconnect, then retry Remote Desktop."
        case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .timedOut:
            return "Could not reach Remote Desktop. Confirm the Mac, gateway, and tunnel are online, then retry."
        default:
            break
        }
    }

    guard let apiError = error as? RemoteDesktopAPIError else {
        return "Remote Desktop failed. Confirm CodePilot is open on the Mac, then retry."
    }

    switch apiError {
    case .invalidURL:
        return "Open Settings and enter the gateway URL from the Mac setup screen."
    case .invalidResponse:
        return "The Mac returned an unreadable response. Restart the gateway, then retry."
    case .server(_, let code) where code == "pairing_expired":
        return "Pairing expired. Start pairing again."
    case .server(_, let code) where code == "invalid_signature":
        return "Pairing could not verify this iPhone. Start pairing again."
    case .server(_, let code) where code == "screen_recording_required":
        return "Allow Screen Recording for CodePilot on the Mac, restart CodePilot, then retry."
    case .server(_, let code) where code == "accessibility_required":
        return "Allow Accessibility for CodePilot on the Mac, restart CodePilot, then retry."
    case .server(_, let code) where code == "host_unavailable" || code == "timeout":
        return "Remote Desktop is unavailable on the Mac. Confirm CodePilot is open, then retry."
    case .server(let status, _) where status == 401 || status == 403:
        return "Remote Desktop access was denied. Copy the current iOS connection token from the Mac setup screen, then retry."
    case .server:
        return "Remote Desktop failed on the Mac. Open Remote Desktop in CodePilot on the Mac, then retry."
    }
}
