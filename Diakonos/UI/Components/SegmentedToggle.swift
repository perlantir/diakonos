import SwiftUI

struct SegmentedToggle<Value: Hashable & Identifiable>: View {
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    @State private var hovering: Value? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.id) { option in
                segment(for: option)
            }
        }
        .padding(3)
        .background(trackBackground)
    }

    @ViewBuilder
    private func segment(for option: Value) -> some View {
        let isSelected = option == selection
        let isHover = hovering == option

        Button {
            selection = option
        } label: {
            Text(label(option))
                .font(Typography.text(Typography.Size.sm, weight: .medium))
                .foregroundStyle(segmentForeground(selected: isSelected))
                .padding(.horizontal, DesignTokens.Spacing.s3)
                .padding(.vertical, DesignTokens.Spacing.s1 + 2)
                .frame(minWidth: 86)
                .background(segmentBackground(selected: isSelected, hovering: isHover))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 ? option : nil }
    }

    private func segmentForeground(selected: Bool) -> Color {
        selected ? .white : DesignTokens.Palette.textSecondary
    }

    @ViewBuilder
    private func segmentBackground(selected: Bool, hovering: Bool) -> some View {
        let radius = DesignTokens.Radius.sm - 2
        if selected {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(DesignTokens.Palette.accentPrimary)
        } else if hovering {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(DesignTokens.Palette.bgElevated)
        } else {
            Color.clear
        }
    }

    private var trackBackground: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
            .fill(DesignTokens.Palette.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                    .stroke(DesignTokens.Palette.borderDefault, lineWidth: 1)
            )
    }
}
