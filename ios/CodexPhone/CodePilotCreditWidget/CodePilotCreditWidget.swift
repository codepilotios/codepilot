import ActivityKit
import SwiftUI
import WidgetKit

@main
struct CodePilotCreditWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TotalCreditActivityAttributes.self) { context in
            CreditLockScreenView(state: context.state)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(URL(string: "codepilot://threads"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("CodePilot", systemImage: "bolt.fill")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.shortValue)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(context.state.tint)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: context.state.progress)
                            .tint(context.state.tint)
                        CreditDetailText(state: context.state)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(context.state.tint)
            } compactTrailing: {
                Text(context.state.shortValue)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                CreditMinimalView(state: context.state)
            }
            .widgetURL(URL(string: "codepilot://threads"))
        }
    }
}

private struct CreditMinimalView: View {
    let state: TotalCreditActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.kind == .available {
                Text("\(state.percent ?? 0)")
                    .font(.caption2.bold().monospacedDigit())
                    .minimumScaleFactor(0.7)
            } else {
                Image(systemName: state.systemImage)
            }
        }
        .foregroundStyle(state.tint)
    }
}

private struct CreditLockScreenView: View {
    let state: TotalCreditActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("CodePilot credit", systemImage: state.systemImage)
                    .font(.headline)
                Spacer(minLength: 12)
                Text(state.shortValue)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(state.tint)
            }

            ProgressView(value: state.progress)
                .tint(state.tint)

            HStack(spacing: 8) {
                CreditDetailText(state: state)
                Spacer(minLength: 8)
                HStack(spacing: 3) {
                    Text("Updated")
                    Text(Date(timeIntervalSince1970: TimeInterval(state.generatedAt)), style: .relative)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
    }
}

private struct CreditDetailText: View {
    let state: TotalCreditActivityAttributes.ContentState

    var body: some View {
        if state.kind == .refilling, let nextRefreshAt = state.nextRefreshAt {
            HStack(spacing: 3) {
                Text("\(state.refreshLabel ?? "Credit") refreshes")
                Text(Date(timeIntervalSince1970: TimeInterval(nextRefreshAt)), style: .relative)
            }
        } else {
            Text(state.detailText)
        }
    }
}

private extension TotalCreditActivityAttributes.ContentState {
    var shortValue: String {
        switch kind {
        case .available:
            return "\(percent ?? 0)%"
        case .refilling:
            return "Refilling"
        case .authenticationRequired:
            return "Sign in"
        case .unavailable:
            return "--"
        }
    }

    var detailText: String {
        switch kind {
        case .available:
            return "\(usableAccountCount) of \(reportedAccountCount) accounts usable"
        case .refilling:
            return "Waiting for credit"
        case .authenticationRequired:
            return "Authentication refresh needed"
        case .unavailable:
            return "Credit unavailable"
        }
    }

    var systemImage: String {
        switch kind {
        case .available: return "bolt.circle"
        case .refilling: return "clock.arrow.circlepath"
        case .authenticationRequired: return "key.fill"
        case .unavailable: return "bolt.slash"
        }
    }

    var tint: Color {
        switch kind {
        case .available where progress <= 0.10: return .red
        case .available where progress <= 0.30: return .orange
        case .available: return .green
        case .refilling: return .blue
        case .authenticationRequired: return .orange
        case .unavailable: return .secondary
        }
    }
}
