import SwiftUI

struct RemoteControlBar: View {
    let latencyText: String
    let isPanMode: Bool
    let onKeyboard: () -> Void
    let onClipboard: () -> Void
    let onMode: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Button(action: onKeyboard) {
                Image(systemName: "keyboard")
            }
            Button(action: onClipboard) {
                Image(systemName: "doc.on.clipboard")
            }
            Button(action: onMode) {
                Image(systemName: isPanMode ? "hand.draw.fill" : "cursorarrow.motionlines")
            }
            .tint(isPanMode ? .accentColor : nil)
            Text(latencyText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 58)
            Button(role: .destructive, action: onDisconnect) {
                Image(systemName: "xmark.circle.fill")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}
