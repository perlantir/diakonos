import SwiftUI
import AppKit

/// Generic web-app pane shared by `.claudeChat` and `.chatgptChat`.
/// Renders a sandboxed non-headless Chromium instance whose screenshots come
/// from CDP `Page.captureScreenshot`. The Chromium is positioned off-screen
/// on display :100 so it doesn't visually overlap the Browser pane; CDP
/// captures content regardless of focus. Each kind owns its `--user-data-dir`
/// for login persistence.
struct WebAppPaneView: View {
    let kind: ChatPaneSandbox.Kind
    var focusPosition: PaneSlotPosition? = nil

    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var layout: WorkspaceLayout
    @StateObject private var sandbox: ChatPaneSandbox
    @State private var hasFocus = false

    init(kind: ChatPaneSandbox.Kind, focusPosition: PaneSlotPosition? = nil) {
        self.kind = kind
        self.focusPosition = focusPosition
        self._sandbox = StateObject(wrappedValue: ChatPaneSandbox(kind: kind))
    }

    var body: some View {
        Group {
            switch sandbox.state {
            case .running where sandbox.latestImage != nil:
                ChatScreenView(
                    sandbox: sandbox,
                    focused: $hasFocus,
                    focusPosition: focusPosition,
                    focusRingColor: NSColor(preferences.accentColor)
                )
            case .running:
                placeholder(message: "Waiting for first frame…")
            default:
                placeholder(message: sandbox.statusMessage.isEmpty ? "Sandbox initializing…" : sandbox.statusMessage)
            }
        }
        .onAppear {
            sandbox.start()
            // v1.7 Part B: register with both mode + postback providers
            // so live header-chip toggles take effect immediately
            // (mid-conversation), and provide slotID so ChatBridge can
            // call back to flip the slot to .manual on Stop/max-turns.
            let pos = focusPosition
            let slotID = pos.flatMap { layout.slot(at: $0)?.id } ?? UUID()
            ChatBridge.shared.register(
                sandbox: sandbox,
                slotID: slotID,
                modeProvider: { [layout, pos] in
                    guard let p = pos, let slot = layout.slot(at: p) else { return .soloChat }
                    return slot.resolvedMode
                },
                postbackProvider: { [layout, pos] in
                    guard let p = pos, let slot = layout.slot(at: p) else { return .manual }
                    return slot.resolvedPostback
                }
            )
        }
        .onDisappear {
            ChatBridge.shared.unregister(sandbox: sandbox)
        }
    }

    @ViewBuilder
    private func placeholder(message: String) -> some View {
        InitializingPaneBody(
            iconSystemName: kind == .claudeChat ? "bubble.left.fill" : "bubble.left.and.bubble.right.fill",
            accent: preferences.accentColor,
            title: kind.displayName,
            message: message
        )
    }
}

/// AppKit hosting view for chat panes. Paints the latest CDP screenshot,
/// captures mouse + keyboard, forwards via CDP Input.dispatchMouseEvent /
/// dispatchKeyEvent through the cuabot /bash channel.
struct ChatScreenView: NSViewRepresentable {
    @ObservedObject var sandbox: ChatPaneSandbox
    @Binding var focused: Bool
    var focusPosition: PaneSlotPosition?
    var focusRingColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator(sandbox: sandbox, focused: $focused)
    }

    func makeNSView(context: Context) -> ChatScreenNSView {
        let v = ChatScreenNSView()
        v.coordinator = context.coordinator
        v.focusRingColor = focusRingColor
        if let pos = focusPosition {
            PaneFocusRegistry.shared.register(v, at: pos)
        }
        return v
    }

    func updateNSView(_ nsView: ChatScreenNSView, context: Context) {
        if let pos = focusPosition {
            PaneFocusRegistry.shared.register(nsView, at: pos)
        }
        nsView.focusRingColor = focusRingColor
        nsView.imageBoxNeedsRedraw(sandbox.latestImage)
    }

    @MainActor
    final class Coordinator {
        let sandbox: ChatPaneSandbox
        @Binding var focused: Bool
        init(sandbox: ChatPaneSandbox, focused: Binding<Bool>) {
            self.sandbox = sandbox
            self._focused = focused
        }
    }
}

final class ChatScreenNSView: NSView {
    var coordinator: ChatScreenView.Coordinator?
    var focusRingColor: NSColor = NSColor.systemBlue
    private var currentImage: NSImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { focusChanged(true); return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { focusChanged(false); return super.resignFirstResponder() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func focusChanged(_ value: Bool) {
        DispatchQueue.main.async { [weak self] in self?.coordinator?.focused = value }
        needsDisplay = true
    }

    func imageBoxNeedsRedraw(_ image: NSImage?) {
        currentImage = image
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        if let img = currentImage {
            let target = aspectFitRect(forImage: img.size, in: bounds)
            img.draw(in: target, from: .zero, operation: .copy, fraction: 1.0,
                     respectFlipped: true, hints: [.interpolation: NSImageInterpolation.medium])
        }
        if coordinator?.focused == true {
            focusRingColor.setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func aspectFitRect(forImage size: CGSize, in container: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return container }
        let scale = min(container.width / size.width, container.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: container.minX + (container.width - w) / 2,
                      y: container.minY + (container.height - h) / 2,
                      width: w, height: h)
    }

    private func translate(_ point: CGPoint) -> (CGPoint, CGSize)? {
        guard let img = currentImage, img.size.width > 0, img.size.height > 0 else { return nil }
        let imgRect = aspectFitRect(forImage: img.size, in: bounds)
        guard imgRect.contains(point) else { return nil }
        return (CGPoint(x: point.x - imgRect.minX,
                       y: imgRect.height - (point.y - imgRect.minY)),
                imgRect.size)
    }

    // MARK: - Mouse forwarding (to CDP via cuabot /bash)

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let sandbox = coordinator?.sandbox else { return }
        let local = convert(event.locationInWindow, from: nil)
        guard let (lp, size) = translate(local), let img = currentImage else { return }
        let nx = Int((lp.x / size.width * img.size.width).rounded())
        let ny = Int((lp.y / size.height * img.size.height).rounded())
        Task { await CDPInput.click(port: sandbox.kind.cdpPort, x: nx, y: ny, button: "left") }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let sandbox = coordinator?.sandbox else { return }
        let local = convert(event.locationInWindow, from: nil)
        guard let (lp, size) = translate(local), let img = currentImage else { return }
        let nx = Int((lp.x / size.width * img.size.width).rounded())
        let ny = Int((lp.y / size.height * img.size.height).rounded())
        Task { await CDPInput.click(port: sandbox.kind.cdpPort, x: nx, y: ny, button: "right") }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let sandbox = coordinator?.sandbox else { return }
        let local = convert(event.locationInWindow, from: nil)
        guard let (lp, size) = translate(local), let img = currentImage else { return }
        let nx = Int((lp.x / size.width * img.size.width).rounded())
        let ny = Int((lp.y / size.height * img.size.height).rounded())
        let dy = Int(-event.scrollingDeltaY * 4)
        Task { await CDPInput.scroll(port: sandbox.kind.cdpPort, x: nx, y: ny, dy: dy) }
    }

    // MARK: - Keyboard forwarding (v1.6 unified pipeline)
    //
    // Single source of truth: `KeyboardEventTranslator`. It classifies the
    // NSEvent into a typing / chord / clipboard route. We just dispatch.
    // The translator's policy:
    //   - Shift / Option are TYPING modifiers (Shift+2 → "@", Opt+e → "´")
    //   - Cmd / Ctrl are COMMAND modifiers (Cmd+V → chord/clipboard)
    //   - Named specials (arrows, F-keys, Enter, etc.) → dispatchKey
    //   - Cmd+V → ClipboardBridge.paste (Mac → sandbox)
    //   - Cmd+C/X → ClipboardBridge.copyFromBrowser (sandbox → Mac) + forward chord

    override func keyDown(with event: NSEvent) {
        guard let sandbox = coordinator?.sandbox else { return }
        let port = sandbox.kind.cdpPort
        switch KeyboardEventTranslator.classify(event) {
        case .type(let text):
            Task { await CDPInput.dispatchType(port: port, text: text) }
        case .key(let name, let mods):
            Task { await CDPInput.dispatchKey(port: port, name: name, modifiers: mods) }
        case .clipboardPaste:
            Task { @MainActor in
                await ClipboardBridge.paste(toPort: port)
            }
        case .clipboardCopy:
            Task { @MainActor in
                // Scrape the sandbox's selection text into NSPasteboard first,
                // then forward the Cmd+C chord so the page's native copy
                // handler (which may attach richer mime types) still fires.
                await ClipboardBridge.copyFromBrowser(port: port)
                await CDPInput.dispatchKey(port: port, name: "c", modifiers: ["super"])
            }
        case .clipboardCut:
            Task { @MainActor in
                await ClipboardBridge.copyFromBrowser(port: port)
                // Cmd+X chord — Chromium's native handler performs the cut
                // on its side after we've captured the text.
                await CDPInput.dispatchKey(port: port, name: "x", modifiers: ["super"])
            }
        case .ignore:
            break
        }
    }
}
