import SwiftUI

struct AboutSection: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s5) {

                VStack(alignment: .center, spacing: DesignTokens.Spacing.s3) {
                    DiakonosIcon(size: 96)
                    Text("Diakonos")
                        .font(Typography.display(Typography.Size.xxl, weight: .semibold))
                        .foregroundStyle(DesignTokens.Palette.textPrimary)
                    Text("Sandboxed AI agent workspace")
                        .font(Typography.text(Typography.Size.md))
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                    Text("v0.1.0 · MIT License")
                        .font(Typography.mono(Typography.Size.xs))
                        .foregroundStyle(DesignTokens.Palette.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.s6)

                PreferencesSection(title: "Credits") {
                    PreferenceRow(label: "cua") {
                        Text("trycua/cua").font(Typography.mono(Typography.Size.sm))
                            .foregroundStyle(DesignTokens.Palette.textSecondary)
                    }
                    PreferenceRow(label: "SwiftTerm") {
                        Text("migueldeicaza/SwiftTerm").font(Typography.mono(Typography.Size.sm))
                            .foregroundStyle(DesignTokens.Palette.textSecondary)
                    }
                    PreferenceRow(label: "Built by") {
                        Text("Nick / perlantir").font(Typography.text(Typography.Size.sm))
                            .foregroundStyle(DesignTokens.Palette.textSecondary)
                    }
                }
            }
            .padding(DesignTokens.Spacing.s5)
        }
    }
}
