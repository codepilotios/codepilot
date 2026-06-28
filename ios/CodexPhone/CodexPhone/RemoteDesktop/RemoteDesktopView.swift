import SwiftUI
import UIKit

struct RemoteDesktopView: View {
    private enum InteractionMode {
        case control
        case pan
    }

    @Environment(\.dismiss) private var dismiss
    @FocusState private var keyboardFocused: Bool
    @StateObject private var peer = RemotePeerConnection()
    @AppStorage("gatewayURL") private var gatewayURL = ""
    @AppStorage("gatewayToken") private var gatewayToken = ""
    @State private var session = RemoteDesktopSessionState(leaseID: "preview")
    @State private var mapper = RemoteInputMapper(sessionID: "preview")
    @State private var frameImage: UIImage?
    @State private var frameError: String?
    @State private var permissionWarning: String?
    @State private var frameTask: Task<Void, Never>?
    @State private var inputTask: Task<Void, Never>?
    @State private var interactionMode: InteractionMode = .control
    @State private var zoomScale: CGFloat = 1
    @State private var gestureZoomScale: CGFloat = 1
    @State private var viewport = RemoteViewport()
    @State private var keyboardText = ""
    @State private var lastDragTranslation: CGSize = .zero
    @State private var pendingPointerDelta: CGSize = .zero
    @State private var lastPointerSendAt = Date.distantPast

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(Color(.secondarySystemBackground))
                    .overlay {
                        if let videoTrack = peer.videoTrack {
                            RemoteVideoView(track: videoTrack)
                                .scaleEffect(effectiveZoom)
                                .offset(viewportOffset(container: proxy.size))
                                .background(Color.black)
                        } else if let frameImage {
                            Image(uiImage: frameImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .scaleEffect(effectiveZoom)
                                .offset(viewportOffset(container: proxy.size))
                                .background(Color.black)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "desktopcomputer")
                                    .font(.system(size: 54, weight: .semibold))
                                Text(title)
                                    .font(.headline)
                                Text(frameError ?? "Waiting for video from the Mac.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let delta = CGSize(
                                    width: value.translation.width - lastDragTranslation.width,
                                    height: value.translation.height - lastDragTranslation.height
                                )
                                lastDragTranslation = value.translation
                                pendingPointerDelta.width += delta.width
                                pendingPointerDelta.height += delta.height
                                predictCursor(delta: delta)
                                flushPointerDeltaIfNeeded()
                            }
                            .onEnded { value in
                                flushPointerDelta(force: true)
                                lastDragTranslation = .zero
                                if value.translation == .zero {
                                    send(mapper.buttonDown())
                                    send(mapper.buttonUp())
                                }
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { gestureZoomScale = $0 }
                            .onEnded { value in
                                zoomScale = min(4, max(1, zoomScale * value))
                                viewport.zoom = zoomScale
                                gestureZoomScale = 1
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeOut(duration: 0.18)) {
                            zoomScale = zoomScale > 1 ? 1 : 2
                            viewport.zoom = zoomScale
                        }
                    }

                if let frameImage {
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 1.5, x: 0, y: 1)
                        .position(cursorPosition(container: proxy.size, image: frameImage.size))
                        .allowsHitTesting(false)
                }

                VStack {
                    if let permissionWarning {
                        Label(permissionWarning, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(.orange, in: RoundedRectangle(cornerRadius: 7))
                            .padding(.top, 12)
                    }
                    Spacer()
                    RemoteControlBar(
                        latencyText: peer.latencyText,
                        isPanMode: interactionMode == .pan,
                        onKeyboard: { keyboardFocused = true },
                        onClipboard: { pasteClipboard() },
                        onMode: {
                            interactionMode = interactionMode == .control ? .pan : .control
                        },
                        onDisconnect: {
                            session.disconnect()
                            peer.disconnect()
                            dismiss()
                        }
                    )
                    .padding(.bottom, 22)
                }

                TextField("", text: $keyboardText)
                    .focused($keyboardFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .onChange(of: keyboardText) { oldValue, newValue in
                        streamKeyboardChange(from: oldValue, to: newValue)
                    }
            }
            .ignoresSafeArea(edges: .bottom)
            .onAppear {
                mapper = RemoteInputMapper(sessionID: UUID().uuidString)
                peer.connect()
                session.connected()
                startFrameLoop()
                startWebRTC()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                session.enterBackground()
                peer.suspend()
                stopFrameLoop()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                session.enterForeground()
                if !session.shouldRequireNewLease() {
                    peer.connect()
                    startFrameLoop()
                    startWebRTC()
                }
            }
            .onReceive(peer.$videoTrack) { track in
                if track != nil {
                    stopFrameLoop()
                }
            }
            .onDisappear {
                stopFrameLoop()
                inputTask?.cancel()
            }
        }
        .navigationTitle("Remote Desktop")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Text("Typing live on Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { keyboardFocused = false }
            }
        }
    }

    private func startFrameLoop() {
        stopFrameLoop()
        guard let baseURL = URL(string: gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              !gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            frameError = "Gateway is not configured."
            return
        }
        let api = RemoteDesktopAPI(baseURL: baseURL, token: gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines))
        frameTask = Task {
            if let status = try? await api.status() {
                await MainActor.run {
                    if status.screenRecordingGranted == false {
                        permissionWarning = "Allow Screen Recording for CodePilot on the Mac."
                    } else if status.accessibilityGranted == false {
                        permissionWarning = "Allow Accessibility for CodePilot on the Mac to enable control."
                    } else {
                        permissionWarning = nil
                    }
                }
            }
            while !Task.isCancelled {
                do {
                    let data = try await api.frame()
                    if let image = UIImage(data: data) {
                        await MainActor.run {
                            frameImage = image
                            frameError = nil
                            session.connected()
                        }
                    }
                    try await Task.sleep(nanoseconds: 140_000_000)
                } catch {
                    await MainActor.run {
                        frameError = "Video unavailable: \(Self.errorText(error))"
                    }
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }
            }
        }
    }

    private func startWebRTC() {
        guard let baseURL = URL(string: gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              !gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let api = RemoteDesktopAPI(baseURL: baseURL, token: gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines))
        Task {
            do {
                try await peer.connect(api: api)
            } catch {
                await MainActor.run {
                    frameError = "WebRTC reconnecting: \(Self.errorText(error))"
                }
            }
        }
    }

    private func stopFrameLoop() {
        frameTask?.cancel()
        frameTask = nil
    }

    private func send(_ event: RemoteInputEvent) {
        session.enqueueInput(event)
        guard let baseURL = URL(string: gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              !gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let api = RemoteDesktopAPI(baseURL: baseURL, token: gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines))
        let previous = inputTask
        inputTask = Task {
            _ = await previous?.result
            guard !Task.isCancelled else { return }
            do {
                let acknowledgement = try await api.sendInput(event)
                if let cursor = acknowledgement.cursor {
                    await MainActor.run {
                        viewport.cursor = CGPoint(x: cursor.x, y: cursor.y)
                    }
                }
            } catch {
                await MainActor.run {
                    frameError = "Control unavailable: \(Self.errorText(error))"
                }
            }
        }
    }

    private func pasteClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            frameError = "The iPhone clipboard has no text."
            return
        }
        send(mapper.text(text))
    }

    private func flushPointerDeltaIfNeeded() {
        guard Date().timeIntervalSince(lastPointerSendAt) >= 0.05 else { return }
        flushPointerDelta(force: false)
    }

    private func flushPointerDelta(force: Bool) {
        guard force || Date().timeIntervalSince(lastPointerSendAt) >= 0.05 else { return }
        guard pendingPointerDelta != .zero else { return }
        let delta = pendingPointerDelta
        pendingPointerDelta = .zero
        lastPointerSendAt = Date()
        send(mapper.moveRelative(delta: delta))
    }

    private func streamKeyboardChange(from oldValue: String, to newValue: String) {
        if newValue.hasPrefix(oldValue) {
            let added = String(newValue.dropFirst(oldValue.count))
            if !added.isEmpty { send(mapper.text(added)) }
            return
        }

        let removedCount: Int
        if oldValue.hasPrefix(newValue) {
            removedCount = oldValue.count - newValue.count
        } else {
            removedCount = oldValue.count
        }
        for _ in 0..<removedCount {
            send(mapper.keyDown(51))
            send(mapper.keyUp(51))
        }
        if !oldValue.hasPrefix(newValue), !newValue.isEmpty {
            send(mapper.text(newValue))
        }
    }

    private var effectiveZoom: CGFloat {
        min(4, max(1, zoomScale * gestureZoomScale))
    }

    private func viewportOffset(container: CGSize) -> CGSize {
        guard let frameImage else { return .zero }
        var current = viewport
        current.zoom = effectiveZoom
        return current.offset(container: container, image: frameImage.size)
    }

    private func cursorPosition(container: CGSize, image: CGSize) -> CGPoint {
        var current = viewport
        current.zoom = effectiveZoom
        return current.cursorPosition(container: container, image: image)
    }

    private func predictCursor(delta: CGSize) {
        guard let frameImage, frameImage.size.width > 0, frameImage.size.height > 0 else { return }
        viewport.cursor = CGPoint(
            x: min(1, max(0, viewport.cursor.x + delta.width * 1.35 / frameImage.size.width)),
            y: min(1, max(0, viewport.cursor.y + delta.height * 1.35 / frameImage.size.height))
        )
    }

    private static func errorText(_ error: Error) -> String {
        if case RemoteDesktopAPIError.server(_, let code) = error {
            return code
        }
        return error.localizedDescription
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
