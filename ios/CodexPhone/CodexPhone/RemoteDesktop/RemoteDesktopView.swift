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
    @State private var webRTCTask: Task<Void, Never>?
    @State private var inputTask: Task<Void, Never>?
    @State private var interactionMode: InteractionMode = .control
    @State private var zoomScale: CGFloat = 1
    @State private var gestureZoomScale: CGFloat = 1
    @State private var viewport = RemoteViewport()
    @State private var cursorCoordinateSize: CGSize?
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
                                let remoteDelta = remotePointerDelta(forScreenDelta: delta, container: proxy.size)
                                pendingPointerDelta.width += remoteDelta.width
                                pendingPointerDelta.height += remoteDelta.height
                                predictCursor(remoteDelta: remoteDelta)
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

                if peer.videoTrack == nil, let imageSize = remoteImageSize {
                    Image(systemName: "cursorarrow")
                        .font(.system(size: cursorSymbolSize(), weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 1.5, x: 0, y: 1)
                        .position(cursorOverlayPosition(container: proxy.size, image: imageSize))
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
            .onReceive(peer.$remoteCursor) { cursor in
                guard let cursor else { return }
                viewport.cursor = cursor
            }
            .onDisappear {
                stopFrameLoop()
                stopWebRTC()
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
                    if let displayFrame = status.displayFrame, displayFrame.width > 0, displayFrame.height > 0 {
                        cursorCoordinateSize = CGSize(width: displayFrame.width, height: displayFrame.height)
                    }
                    if let cursor = status.cursor {
                        viewport.cursor = CGPoint(x: cursor.x, y: cursor.y)
                    }
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
        stopWebRTC()
        guard let baseURL = URL(string: gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              !gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let api = RemoteDesktopAPI(baseURL: baseURL, token: gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines))
        webRTCTask = Task {
            while !Task.isCancelled {
                do {
                    try await peer.connect(api: api)
                    await MainActor.run {
                        frameError = nil
                    }
                    return
                } catch {
                    await MainActor.run {
                        frameError = "WebRTC reconnecting: \(Self.errorText(error))"
                    }
                    try? await Task.sleep(nanoseconds: 1_250_000_000)
                }
            }
        }
    }

    private func stopWebRTC() {
        webRTCTask?.cancel()
        webRTCTask = nil
    }

    private func stopFrameLoop() {
        frameTask?.cancel()
        frameTask = nil
    }

    private func send(_ event: RemoteInputEvent) {
        session.enqueueInput(event)
        if peer.sendInput(event) {
            return
        }
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
                        if event.kind != .pointer || event.deltaX == nil || event.deltaY == nil {
                            viewport.cursor = CGPoint(x: cursor.x, y: cursor.y)
                        }
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
        guard Date().timeIntervalSince(lastPointerSendAt) >= pointerFlushInterval else { return }
        flushPointerDelta(force: false)
    }

    private func flushPointerDelta(force: Bool) {
        guard force || Date().timeIntervalSince(lastPointerSendAt) >= pointerFlushInterval else { return }
        guard pendingPointerDelta != .zero else { return }
        let delta = pendingPointerDelta
        pendingPointerDelta = .zero
        lastPointerSendAt = Date()
        send(mapper.moveRelative(delta: delta, sensitivity: 1))
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

    private var pointerFlushInterval: TimeInterval {
        peer.isInputReady ? (1.0 / 60.0) : 0.05
    }

    private func viewportOffset(container: CGSize) -> CGSize {
        guard let imageSize = remoteImageSize else { return .zero }
        var current = viewport
        current.zoom = effectiveZoom
        return current.offset(container: container, image: imageSize)
    }

    private func cursorPosition(container: CGSize, image: CGSize) -> CGPoint {
        var current = viewport
        current.zoom = effectiveZoom
        return current.cursorPosition(container: container, image: image)
    }

    private func cursorSymbolSize() -> CGFloat {
        var current = viewport
        current.zoom = effectiveZoom
        return current.cursorSymbolSize()
    }

    private func cursorOverlayPosition(container: CGSize, image: CGSize) -> CGPoint {
        var current = viewport
        current.zoom = effectiveZoom
        let hotspot = current.cursorPosition(container: container, image: image)
        let offset = current.cursorHotspotOffset(symbolSize: current.cursorSymbolSize())
        return CGPoint(x: hotspot.x + offset.width, y: hotspot.y + offset.height)
    }

    private func predictCursor(remoteDelta: CGSize) {
        guard let coordinateSize = cursorCoordinateSize ?? frameImage?.size else { return }
        viewport.applyPointerDelta(remoteDelta, coordinateSize: coordinateSize, sensitivity: 1)
    }

    private var remoteImageSize: CGSize? {
        if let cursorCoordinateSize, cursorCoordinateSize.width > 0, cursorCoordinateSize.height > 0 {
            return cursorCoordinateSize
        }
        return frameImage?.size
    }

    private func remotePointerDelta(forScreenDelta delta: CGSize, container: CGSize) -> CGSize {
        guard let imageSize = remoteImageSize else { return delta }
        var current = viewport
        current.zoom = effectiveZoom
        return current.remoteDelta(forScreenDelta: delta, container: container, image: imageSize)
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
