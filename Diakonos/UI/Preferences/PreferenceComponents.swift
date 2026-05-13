import SwiftUI

/// Section card wrapper used on every Preferences page.
struct PreferencesSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.text(Typography.Size.md, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.text(Typography.Size.sm))
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s3) {
                content()
            }
            .padding(DesignTokens.Spacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .fill(DesignTokens.Palette.bgSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                            .stroke(DesignTokens.Palette.borderSoft, lineWidth: 1)
                    )
            )
        }
    }
}

/// Row with a label on the left and arbitrary control on the right.
struct PreferenceRow<Content: View>: View {
    let label: String
    var detail: String? = nil
    @ViewBuilder let trailing: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Typography.text(Typography.Size.sm, weight: .medium))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                if let detail {
                    Text(detail)
                        .font(Typography.text(Typography.Size.xs))
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                }
            }
            Spacer(minLength: DesignTokens.Spacing.s4)
            trailing()
        }
    }
}

/// Bordered secret-style text field (used for API keys).
struct SecretField: View {
    let placeholder: String
    @Binding var value: String

    var body: some View {
        SecureField(placeholder, text: $value)
            .textFieldStyle(.plain)
            .font(Typography.mono(Typography.Size.sm))
            .padding(.horizontal, DesignTokens.Spacing.s3)
            .padding(.vertical, 6)
            .frame(minWidth: 260)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm - 2, style: .continuous)
                    .fill(DesignTokens.Palette.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm - 2, style: .continuous)
                            .stroke(DesignTokens.Palette.borderDefault, lineWidth: 1)
                    )
            )
    }
}

/// Accent-color chip row used in General → Appearance.
struct AccentChipRow: View {
    private let chips: [Color] = [
        Color(hex: 0x2F6BFF), Color(hex: 0x8B5CF6), Color(hex: 0x22C55E),
        Color(hex: 0xF59E0B), Color(hex: 0xEF4444), Color(hex: 0xEC4899),
        Color(hex: 0x06B6D4)
    ]
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s2) {
            ForEach(chips.indices, id: \.self) { i in
                let isAccent = i == 0
                ZStack {
                    Circle()
                        .fill(chips[i])
                        .frame(width: 22, height: 22)
                    if isAccent {
                        Circle()
                            .strokeBorder(DesignTokens.Palette.textPrimary, lineWidth: 2)
                            .frame(width: 26, height: 26)
                    }
                }
            }
        }
    }
}
