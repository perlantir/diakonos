import SwiftUI

struct DiagnosticsSection: View {
    @ObservedObject var log = DiagnosticsLog.shared

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s3) {
            HStack {
                Text("ChatBridge events")
                    .font(Typography.text(Typography.Size.md, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                Spacer()
                Button("Clear") { log.clear() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, DesignTokens.Spacing.s5)
            .padding(.top, DesignTokens.Spacing.s5)

            if log.entries.isEmpty {
                VStack {
                    Spacer()
                    Text("No events yet. Type `Code: <prompt>` in a Claude Chat or ChatGPT pane to start a routing thread.")
                        .font(Typography.text(Typography.Size.sm))
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(log.entries.reversed()) { entry in
                            row(entry)
                        }
                    }
                }
            }
        }
    }

    private func row(_ entry: DiagnosticsLog.Entry) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.s3) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(Typography.mono(Typography.Size.xs))
                .foregroundStyle(DesignTokens.Palette.textMuted)
                .frame(width: 64, alignment: .leading)
            Text(entry.kind.rawValue.uppercased())
                .font(Typography.mono(Typography.Size.xs, weight: .semibold))
                .foregroundStyle(color(for: entry.kind))
                .frame(width: 70, alignment: .leading)
            Text(entry.detail)
                .font(Typography.text(Typography.Size.xs))
                .foregroundStyle(DesignTokens.Palette.textPrimary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.s5)
        .padding(.vertical, 4)
    }

    private func color(for kind: DiagnosticsLog.Entry.Kind) -> Color {
        switch kind {
        case .triggerDetected:    return DesignTokens.Palette.accentPrimary
        case .routedToAgent:      return Color(hex: 0x8B5CF6)
        case .responseFromAgent:  return DesignTokens.Palette.statusHealthy
        case .postedToChat:       return DesignTokens.Palette.statusHealthy
        case .selectorMissing:    return DesignTokens.Palette.statusError
        case .error:              return DesignTokens.Palette.statusError
        case .info:               return DesignTokens.Palette.textSecondary
        }
    }
}
