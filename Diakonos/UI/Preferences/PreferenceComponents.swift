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

/// Accent-color chip row — stateful in v1.3. Picks one of seven preset hexes;
/// writes the chosen hex to `preferences.accentColorHex` and the rest of the
/// app reads `preferences.accentColor` to resolve it at runtime.
struct AccentChipRow: View {
    @ObservedObject var preferences: Preferences

    private let chips: [String] = [
        "#2F6BFF", "#8B5CF6", "#22C55E",
        "#F59E0B", "#EF4444", "#EC4899",
        "#06B6D4"
    ]

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.s2) {
            ForEach(chips, id: \.self) { hex in
                let isSelected = preferences.accentColorHex.uppercased() == hex.uppercased()
                Button {
                    preferences.accentColorHex = hex
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hexString: hex) ?? .gray)
                            .frame(width: 22, height: 22)
                        if isSelected {
                            Circle()
                                .strokeBorder(DesignTokens.Palette.textPrimary, lineWidth: 2)
                                .frame(width: 26, height: 26)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
