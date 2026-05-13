import SwiftUI

enum PreferenceTab: String, CaseIterable, Identifiable, Hashable {
    case general, panes, shortcuts, about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general:   return "General"
        case .panes:     return "Panes"
        case .shortcuts: return "Shortcuts"
        case .about:     return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general:   return "gearshape"
        case .panes:     return "square.grid.2x2"
        case .shortcuts: return "command"
        case .about:     return "info.circle"
        }
    }
}

struct PreferencesWindow: View {
    @ObservedObject var preferences: Preferences
    @State private var selection: PreferenceTab = .general

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            detailContent
                .frame(minWidth: 520, minHeight: 460)
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(DesignTokens.Palette.bgApp)
    }

    private var sidebar: some View {
        List(PreferenceTab.allCases, selection: $selection) { tab in
            HStack(spacing: DesignTokens.Spacing.s2) {
                Image(systemName: tab.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(
                        selection == tab
                            ? preferences.accentColor
                            : DesignTokens.Palette.textSecondary
                    )
                Text(tab.label)
                    .font(Typography.text(Typography.Size.sm,
                                          weight: selection == tab ? .semibold : .regular))
            }
            .tag(tab)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .general:   GeneralSection(preferences: preferences)
        case .panes:     PanesSection(preferences: preferences)
        case .shortcuts: ShortcutsSection()
        case .about:     AboutSection()
        }
    }
}
