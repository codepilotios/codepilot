import SwiftUI
import UIKit

struct RemotePairingView: View {
    @AppStorage("gatewayURL") private var gatewayURL = ""
    @AppStorage("gatewayToken") private var gatewayToken = ""
    @State private var statusText = "Not paired"
    @State private var isLoading = false
    @State private var manualCode = ""
    @State private var identity = SoftwareRemoteDeviceIdentity(deviceID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString)

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac") {
                    Text(statusText)
                    TextField("Pairing code", text: $manualCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Device") {
                    LabeledContent("Device ID", value: identity.deviceID)
                    LabeledContent("Public key", value: identity.publicKeyRawRepresentation.base64EncodedString())
                        .textSelection(.enabled)
                }

                Section {
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
            if status.capabilities?.relayAvailable == true {
                statusText = "Host reachable, relay available"
            } else {
                statusText = "Host reachable, local/STUN only"
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
            _ = try await api.completePairing(
                challengeID: challenge.id,
                deviceID: identity.deviceID,
                signature: signature
            )
            statusText = "Paired with \(challenge.macName)"
        } catch RemoteDesktopAPIError.server(_, let code) {
            statusText = code
        } catch {
            statusText = "Pairing failed"
        }
    }

    private func api() -> RemoteDesktopAPI? {
        guard let url = URL(string: gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              !gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return RemoteDesktopAPI(baseURL: url, token: gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
