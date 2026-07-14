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
                }

                Section("Device") {
                    LabeledContent("Device ID", value: identity.deviceID)
                    LabeledContent("Public key", value: identity.publicKeyRawRepresentation.base64EncodedString())
                        .textSelection(.enabled)
                }

                Section {
                    NavigationLink {
                        RemoteDesktopView(identity: identity, gatewayURL: gatewayURL, gatewayToken: gatewayToken)
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
            statusText = "Host unavailable"
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
            statusText = approval.status == "pending_mac_approval"
                ? "Waiting for approval on \(approval.macName)"
                : "Pairing pending"
        } catch RemoteDesktopAPIError.server(_, let code) {
            statusText = code
        } catch {
            statusText = "Pairing failed"
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

func canStartRemoteDesktop(statusText: String) -> Bool {
    statusText.hasPrefix("Paired with ")
}
