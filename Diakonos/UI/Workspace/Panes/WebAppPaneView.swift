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
            ChatBridge.shared.register(sandbox: sandbox)
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

    // MARK: - Keyboard forwarding

    override func keyDown(with event: NSEvent) {
        guard let sandbox = coordinator?.sandbox else { return }
        let port = sandbox.kind.cdpPort
        // Map special keys; printable characters go through dispatchType.
        if let (name, mods) = mapSpecialKey(event: event) {
            Task { await CDPInput.dispatchKey(port: port, name: name, modifiers: mods) }
            return
        }
        let chars = event.characters ?? ""
        if !chars.isEmpty {
            Task { await CDPInput.dispatchType(port: port, text: chars) }
        }
    }

    private func mapSpecialKey(event: NSEvent) -> (String, [String])? {
        var mods: [String] = []
        let f = event.modifierFlags
        if f.contains(.command) { mods.append("super") }
        if f.contains(.option)  { mods.append("alt") }
        if f.contains(.control) { mods.append("ctrl") }
        if f.contains(.shift)   { mods.append("shift") }
        let name: String?
        switch Int(event.keyCode) {
        case 36: name = "Return"
        case 53: name = "Escape"
        case 51: name = "BackSpace"
        case 117: name = "Delete"
        case 48: name = "Tab"
        case 123: name = "Left"
        case 124: name = "Right"
        case 125: name = "Down"
        case 126: name = "Up"
        case 116: name = "Page_Up"
        case 121: name = "Page_Down"
        case 115: name = "Home"
        case 119: name = "End"
        default:
            // Only route through dispatchKey for control combos (Cmd+/Ctrl+/Opt+).
            // Plain shifted characters (Shift+2 → @) go through dispatchType so
            // Chromium gets the right printable char.
            let controlMods = f.contains(.command) || f.contains(.control) || f.contains(.option)
            if controlMods, let c = event.charactersIgnoringModifiers, !c.isEmpty {
                name = c
            } else { name = nil }
        }
        guard let n = name else { return nil }
        return (n, mods)
    }
}
