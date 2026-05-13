import SwiftUI
import WebKit
import AppKit

/// Browser pane: WKWebView with a URL bar (back / forward / address field / reload).
/// Per D6, v1 uses WKWebView; v0.3 will reconsider sandboxed Chromium video streaming.
struct BrowserPaneView: View {
    @State private var addressInput: String = "https://www.apple.com"
    @State private var currentURL: URL? = URL(string: "https://www.apple.com")
    @StateObject private var bridge = WebViewBridge()

    var body: some View {
        VStack(spacing: 0) {
            urlBar
            BrowserWebView(bridge: bridge)
                .onAppear {
                    if let url = currentURL {
                        bridge.load(url: url)
                    }
                }
        }
    }

    private var urlBar: some View {
        HStack(spacing: DesignTokens.Spacing.s2) {
            Button { bridge.goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        bridge.canGoBack
                            ? DesignTokens.Palette.textPrimary
                            : DesignTokens.Palette.textMuted
                    )
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(!bridge.canGoBack)

            Button { bridge.goForward() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        bridge.canGoForward
                            ? DesignTokens.Palette.textPrimary
                            : DesignTokens.Palette.textMuted
                    )
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(!bridge.canGoForward)

            TextField("URL", text: $addressInput, onCommit: navigate)
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

            Button { bridge.reload() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
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

    private func navigate() {
        let trimmed = addressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let urlString: String
        if trimmed.contains("://") {
            urlString = trimmed
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            urlString = "https://\(trimmed)"
        } else {
            // Treat as search query.
            let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            urlString = "https://duckduckgo.com/?q=\(q)"
        }
        guard let url = URL(string: urlString) else { return }
        currentURL = url
        bridge.load(url: url)
    }
}

@MainActor
final class WebViewBridge: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var canGoBack = false
    @Published var canGoForward = false

    weak var webView: WKWebView?

    func load(url: URL) {
        webView?.load(URLRequest(url: url))
    }

    func goBack()   { webView?.goBack();    refreshNav() }
    func goForward(){ webView?.goForward(); refreshNav() }
    func reload()   { webView?.reload() }

    func attach(_ view: WKWebView) {
        webView = view
        view.navigationDelegate = self
        refreshNav()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshNav()
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        refreshNav()
    }

    private func refreshNav() {
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
    }
}

struct BrowserWebView: NSViewRepresentable {
    @ObservedObject var bridge: WebViewBridge

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        bridge.attach(view)
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) { }
}
