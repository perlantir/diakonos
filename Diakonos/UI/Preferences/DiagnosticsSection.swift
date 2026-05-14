import SwiftUI

struct DiagnosticsSection: View {
    @ObservedObject var log = DiagnosticsLog.shared
    @State private var doctorReports: [ContextDoctor.Report] = []
    @State private var diagnosing = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s3) {
            // v1.7 Part B: Context Doctor.
            HStack {
                Text("Context Doctor")
                    .font(Typography.text(Typography.Size.md, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                Spacer()
                Button(diagnosing ? "Checking…" : "Check Context") { runDoctor() }
                    .buttonStyle(.borderedProminent)
                    .disabled(diagnosing)
            }
            .padding(.horizontal, DesignTokens.Spacing.s5)
            .padding(.top, DesignTokens.Spacing.s5)

            if !doctorReports.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(doctorReports.indices, id: \.self) { idx in
                            doctorReportView(doctorReports[idx])
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.s5)
                }
                .frame(maxHeight: 240)
            }

            Divider().padding(.vertical, DesignTokens.Spacing.s2)

            HStack {
                Text("ChatBridge events")
                    .font(Typography.text(Typography.Size.md, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                Spacer()
                Button("Clear") { log.clear() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, DesignTokens.Spacing.s5)

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

    // MARK: - Context Doctor rendering

    private func runDoctor() {
        diagnosing = true
        defer { diagnosing = false }
        let prefs = Preferences()
        let roots = [prefs.claudeCodeResolvedCwd, prefs.codexResolvedCwd]
        var reports: [ContextDoctor.Report] = []
        var seen: Set<String> = []
        for r in roots {
            if seen.contains(r) { continue }
            seen.insert(r)
            reports.append(ContextDoctor.diagnose(projectRoot: r))
        }
        doctorReports = reports
    }

    @ViewBuilder
    private func doctorReportView(_ report: ContextDoctor.Report) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.projectRoot.path)
                .font(Typography.mono(Typography.Size.xs, weight: .semibold))
                .foregroundStyle(DesignTokens.Palette.textSecondary)
            Text("context_hash \(report.contextHash.prefix(12))…")
                .font(Typography.mono(Typography.Size.xs))
                .foregroundStyle(DesignTokens.Palette.textMuted)
            ForEach(report.findings) { f in
                HStack(alignment: .top, spacing: 6) {
                    Text(symbol(for: f.severity))
                        .frame(width: 14)
                        .foregroundStyle(color(for: f.severity))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.title)
                            .font(Typography.text(Typography.Size.sm, weight: .semibold))
                            .foregroundStyle(DesignTokens.Palette.textPrimary)
                        Text(f.detail)
                            .font(Typography.text(Typography.Size.xs))
                            .foregroundStyle(DesignTokens.Palette.textSecondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignTokens.Palette.bgElevated)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(DesignTokens.Palette.borderSoft, lineWidth: 1))
        )
    }

    private func symbol(for s: ContextDoctor.Finding.Severity) -> String {
        switch s {
        case .ok:      return "✓"
        case .warning: return "⚠︎"
        case .error:   return "✗"
        }
    }
    private func color(for s: ContextDoctor.Finding.Severity) -> Color {
        switch s {
        case .ok:      return DesignTokens.Palette.statusHealthy
        case .warning: return Color(hex: 0xF59E0B)
        case .error:   return DesignTokens.Palette.statusError
        }
    }
}
