import SwiftUI

/// Settings tab "Role Cards". Lists every role-card ID with its latest
/// version; selecting one opens the markdown body in an editable
/// `TextEditor`. Save auto-bumps the patch version and writes a new
/// file. Older versions stay on disk — sessions pinned to them keep
/// working.
struct RoleCardsSection: View {
    @StateObject private var store = RoleCardStore.shared
    @State private var selectedID: String? = nil
    @State private var draftBody: String = ""
    @State private var dirty: Bool = false

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 320)
            editor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if selectedID == nil {
                selectedID = BuiltInRoleCardID.allCases.first?.rawValue
                loadDraft()
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Role cards")
                .font(Typography.text(Typography.Size.md, weight: .semibold))
                .foregroundStyle(DesignTokens.Palette.textPrimary)
                .padding(.horizontal, DesignTokens.Spacing.s4)
                .padding(.top, DesignTokens.Spacing.s4)
                .padding(.bottom, DesignTokens.Spacing.s2)
            Text("Markdown role prompts injected into routed prompts. Save creates a new version (e.g. 1.0.1).")
                .font(Typography.text(Typography.Size.xs))
                .foregroundStyle(DesignTokens.Palette.textMuted)
                .padding(.horizontal, DesignTokens.Spacing.s4)
                .padding(.bottom, DesignTokens.Spacing.s3)
            Divider()
            List(selection: $selectedID) {
                ForEach(BuiltInRoleCardID.allCases, id: \.rawValue) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.displayName)
                                .font(Typography.text(Typography.Size.sm, weight: .medium))
                            Text(versionLabel(for: entry.rawValue))
                                .font(Typography.mono(Typography.Size.xs))
                                .foregroundStyle(DesignTokens.Palette.textMuted)
                        }
                        Spacer()
                    }
                    .tag(entry.rawValue)
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedID) { _, _ in loadDraft() }
        }
    }

    @ViewBuilder
    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let id = selectedID {
                HStack {
                    Text(id)
                        .font(Typography.mono(Typography.Size.sm, weight: .semibold))
                    Spacer()
                    Text(versionLabel(for: id))
                        .font(Typography.mono(Typography.Size.xs))
                        .foregroundStyle(DesignTokens.Palette.textMuted)
                    Button("Save (bumps patch)") {
                        save()
                    }
                    .disabled(!dirty)
                }
                .padding(.horizontal, DesignTokens.Spacing.s4)
                .padding(.top, DesignTokens.Spacing.s4)
                .padding(.bottom, DesignTokens.Spacing.s3)
                Divider()
                TextEditor(text: $draftBody)
                    .font(Typography.mono(Typography.Size.sm))
                    .onChange(of: draftBody) { _, _ in dirty = true }
                    .padding(.horizontal, DesignTokens.Spacing.s4)
                    .padding(.bottom, DesignTokens.Spacing.s3)
            } else {
                Spacer()
                Text("Select a role card on the left.")
                    .foregroundStyle(DesignTokens.Palette.textMuted)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
    }

    private func versionLabel(for id: String) -> String {
        if let c = store.latestVersion(forId: id) { return "v\(c.version.string)" }
        return "—"
    }

    private func loadDraft() {
        guard let id = selectedID else { draftBody = ""; dirty = false; return }
        draftBody = store.latestVersion(forId: id)?.body ?? ""
        dirty = false
    }

    private func save() {
        guard let id = selectedID else { return }
        _ = store.save(id: id, body: draftBody)
        dirty = false
    }
}
