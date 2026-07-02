import SwiftUI
import UIKit

struct RemotePairingView: View {
    @Environment(\.dismiss) private var dismiss
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
                    NavigationLink {
                        RemoteDesktopView()
                    } label: {
                        Label("Start Session", systemImage: "play.rectangle")
                    }
                    .disabled(statusText == "Not paired")

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
            } else if status.capabilities?.relayAvailable == true {
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
