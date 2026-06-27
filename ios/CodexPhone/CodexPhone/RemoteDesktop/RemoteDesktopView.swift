import SwiftUI
import UIKit

struct RemoteDesktopView: View {
    @StateObject private var peer = RemotePeerConnection()
    @State private var session = RemoteDesktopSessionState(leaseID: "preview")
    @State private var mapper = RemoteInputMapper(sessionID: "preview")

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(Color(.secondarySystemBackground))
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 54, weight: .semibold))
                            Text(title)
                                .font(.headline)
                            Text("Remote video will appear here when the Mac peer is connected.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                session.enqueueInput(mapper.tap(at: value.location, in: proxy.size))
                            }
                    )

                VStack {
                    Spacer()
                    RemoteControlBar(
                        latencyText: peer.latencyText,
                        onKeyboard: {},
                        onClipboard: {},
                        onMode: {},
                        onDisconnect: {
                            session.disconnect()
                            peer.disconnect()
                        }
                    )
                    .padding(.bottom, 22)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .onAppear {
                peer.connect()
                session.connected()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                session.enterBackground()
                peer.suspend()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                session.enterForeground()
                if !session.shouldRequireNewLease() {
                    peer.connect()
                }
            }
        }
        .navigationTitle("Remote Desktop")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        switch session.phase {
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .reconnecting:
            return "Reconnecting"
        case .suspended:
            return "Suspended"
        case .failed(let message):
            return message
        case .disconnected:
            return "Disconnected"
        }
    }
}
