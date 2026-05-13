import SwiftUI
import WebKit
import AppKit

/// Browser pane — sandboxed Chromium streamed via cuabot's Xpra HTML5 client.
///
/// v1.1 Approach A:
///   - `WKWebView` loaded at `http://localhost:10000/` (the cuabot container's
///     Xpra WebSocket server, confirmed by its `Server: Xpra-WebSocket-Server`
///     header).
///   - URL bar drives Chromium *inside* the sandbox via cuabot's `POST /bash`
///     endpoint (`chromium --no-sandbox <url>` on `DISPLAY=:100`).
///   - Back / Forward / Reload use xdotool keystroke injection inside the
///     container (cuabot does not expose dedicated nav primitives).
struct BrowserPaneView: View {
    @StateObject private var sandbox = BrowserSandbox()
    @State private var addressInput: String = ""
    @State private var browserHomeURL: String = "https://duckduckgo.com"

    var body: some View {
        VStack(spacing: 0) {
            urlBar
            content
        }
        .onAppear {
            sandbox.start()
            // Default home; user can edit via Preferences → Panes → Browser pane.
            browserHomeURL = UserDefaults.standard.string(forKey: "browserHomeURL") ?? "https://duckduckgo.com"
            addressInput = browserHomeURL
            Task { await navigateOnce() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch sandbox.state {
        case .running:
            XpraWebView(url: sandbox.xpraURL)
        case .initializing, .warning:
            InitializingPaneBody(kind: .browser,
                                 message: sandbox.statusMessage.isEmpty ? "Sandbox initializing…" : sandbox.statusMessage)
        case .error:
            InitializingPaneBody(kind: .browser,
                                 message: sandbox.statusMessage)
                .overlay(alignment: .bottom) {
                    Text("The Browser pane needs Docker + npx. Other panes work fine without them.")
                        .font(Typography.text(Typography.Size.xs))
                        .foregroundStyle(DesignTokens.Palette.textMuted)
                        .padding(.bottom, DesignTokens.Spacing.s4)
                }
        case .stopped:
            InitializingPaneBody(kind: .browser, message: "Sandbox stopped")
        }
    }

    private var urlBar: some View {
        HStack(spacing: DesignTokens.Spacing.s2) {
            Button { Task { await sandbox.goBack() } } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(sandbox.state != .running)

            Button { Task { await sandbox.goForward() } } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(sandbox.state != .running)

            TextField("URL or search", text: $addressInput, onCommit: { Task { await navigateOnce() } })
                .textFieldStyle(.plain)
                .font(Typography.text(Typography.Size.sm))
                .padding(.horizontal, DesignTokens.Spacing.s3)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm - 2, style: .continuous)
                        .fill(DesignTokens.Palette.bgElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm - 2, style: .continuous)
                                .stroke(DesignTokens.Palette.borderDefault, lineWidth: 1)
                        )
                )

            Button { Task { await sandbox.reloadCurrent() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(sandbox.state != .running)

            // Sandbox state dot (the only place this lives in v1.1).
            Circle()
                .fill(sandbox.state.indicatorColor)
                .frame(width: 6, height: 6)
                .help(sandbox.statusMessage)
        }
        .padding(.horizontal, DesignTokens.Spacing.s3)
        .padding(.vertical, DesignTokens.Spacing.s2)
        .background(
            DesignTokens.Palette.bgElevated
                .overlay(alignment: .bottom) {
                    Rectangle().fill(DesignTokens.Palette.borderSoft).frame(height: 1)
                }
        )
    }

    private func navigateOnce() async {
        // Wait for sandbox.state to flip to .running before sending; called from
        // multiple entry points so a no-op early-return is fine.
        var attempts = 0
        while sandbox.state != .running, attempts < 90 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            attempts += 1
        }
        await sandbox.navigate(to: addressInput)
    }
}

/// Embeds the Xpra HTML5 client in a WKWebView. The web client owns its own
/// keyboard/mouse forwarding; we just provide the viewport.
struct XpraWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Allow autoplay of media (Xpra streams may use HTML5 audio).
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }
}
