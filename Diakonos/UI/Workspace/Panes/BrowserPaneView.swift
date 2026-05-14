import SwiftUI
import AppKit

/// Browser pane — sandboxed Chromium via Option Z (screenshot stream + click /
/// keyboard forwarding through cuabot's HTTP API).
///
/// Architecture:
///   - `SandboxStream` polls `POST /screenshot` at 10 fps and publishes the
///     latest JPEG as NSImage + native dimensions + scale factor.
///   - `SandboxScreenNSView` (AppKit) renders the image, captures mouse +
///     keyboard, and forwards to `SandboxInput`.
///   - `BrowserSandbox` (carried over from v1.1) owns cuabot lifecycle +
///     navigation (launch chromium with the URL).
///   - 3-dot menu actions arrive via Notification (Reload / Pop-out / Reset).
struct BrowserPaneView: View {
    var focusPosition: PaneSlotPosition? = nil

    @EnvironmentObject private var preferences: Preferences
    @StateObject private var sandbox = BrowserSandbox()
    @StateObject private var stream = SandboxStream()
    @StateObject private var input = SandboxInput()

    @State private var addressInput: String = ""
    @State private var displayedURL: String = ""
    @State private var hasFocus = false
    @State private var lastResizeBucket: String = ""

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                urlBar
                content
            }
            .onAppear {
                sandbox.start()
                addressInput = preferences.browserHomeURL
                Task { await loadInitial() }
            }
            .onDisappear {
                stream.stop()
            }
            .task(id: "\(bucketed(geo.size))|\(sandbox.state)") {
                // Debounce 200 ms on the bucketed view size, then ask Chromium
                // to resize itself to the current pane size so the screenshot
                // aspect-ratio matches the viewer.
                guard sandbox.state == .running else { return }
                let bucket = bucketed(geo.size)
                let resizeKey = "\(bucket)|\(sandbox.state)"
                guard resizeKey != lastResizeBucket else { return }
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard bucketed(geo.size) == bucket else { return }
                lastResizeBucket = resizeKey
                let w = Int(geo.size.width)
                let h = Int(max(geo.size.height - 40, 1)) // minus URL bar
                await sandbox.setWindowSize(width: w, height: h)
            }
            .onChange(of: sandbox.state) { _, new in
                if new == .running { stream.start() }
                else { stream.stop() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .diakonosBrowserReload)) { _ in
                Task { await sandbox.reloadCurrent() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .diakonosBrowserResetSandbox)) { _ in
                Task { await sandbox.resetSandbox() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .diakonosBrowserPopout)) { _ in
                Task {
                    await sandbox.openFloatingChromiumWindow()
                    XpraSuppressor.relaunch()
                }
            }
        }
    }

    /// Bucket the view size to 16px grid so we don't trigger resizes on every
    /// pixel during a divider drag.
    private func bucketed(_ size: CGSize) -> String {
        "\(Int(size.width / 16) * 16)x\(Int(size.height / 16) * 16)"
    }

    @ViewBuilder
    private var content: some View {
        switch sandbox.state {
        case .running where stream.latestImage != nil:
            SandboxScreenView(
                stream: stream,
                input: input,
                cdpPort: sandbox.cdpPort,
                focused: $hasFocus,
                focusPosition: focusPosition,
                focusRingColor: NSColor(preferences.accentColor)
            )
        case .running:
            InitializingPaneBody(
                iconSystemName: "globe",
                accent: preferences.accentColor,
                title: "Browser",
                message: "Waiting for the first sandbox frame…"
            )
        case .initializing, .warning:
            InitializingPaneBody(
                iconSystemName: "globe",
                accent: preferences.accentColor,
                title: "Browser",
                message: sandbox.statusMessage.isEmpty ? "Sandbox initializing…" : sandbox.statusMessage
            )
        case .error:
            InitializingPaneBody(
                iconSystemName: "globe",
                accent: preferences.accentColor,
                title: "Browser",
                message: sandbox.statusMessage
            )
            .overlay(alignment: .bottom) {
                Text("The Browser pane needs Docker + npx. Other panes work fine without them.")
                    .font(Typography.text(Typography.Size.xs))
                    .foregroundStyle(DesignTokens.Palette.textMuted)
                    .padding(.bottom, DesignTokens.Spacing.s4)
            }
        case .stopped:
            InitializingPaneBody(
                iconSystemName: "globe",
                accent: preferences.accentColor,
                title: "Browser",
                message: "Sandbox stopped"
            )
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

            TextField("URL or search",
                      text: Binding(
                        get: { displayedURL.isEmpty ? addressInput : displayedURL },
                        set: { addressInput = $0; displayedURL = "" }
                      ),
                      onCommit: { Task { await navigate() } })
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
        .task(id: sandbox.state) {
            guard sandbox.state == .running else { return }
            while !Task.isCancelled, sandbox.state == .running {
                let live = await sandbox.fetchCurrentURL()
                if let live, !live.isEmpty {
                    displayedURL = live
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func navigate() async {
        let urlText = addressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlText.isEmpty else { return }
        await sandbox.navigate(to: urlText)
        displayedURL = ""
    }

    private func loadInitial() async {
        var attempts = 0
        while sandbox.state != .running, attempts < 90 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            attempts += 1
        }
        guard sandbox.state == .running else { return }
        await sandbox.navigate(to: addressInput)
    }
}

/// AppKit hosting view for the screenshot stream. Captures mouse + keyboard
/// and forwards to `SandboxInput`.
struct SandboxScreenView: NSViewRepresentable {
    @ObservedObject var stream: SandboxStream
    @ObservedObject var input: SandboxInput
    /// CDP port for the Browser pane's Chromium (9222 inside the cuabot
    /// container). Keyboard events flow through `CDPInput` on this port —
    /// v1.6 unified the chat-pane and browser-pane keyboard pipelines.
    let cdpPort: Int
    @Binding var focused: Bool
    var focusPosition: PaneSlotPosition?
    var focusRingColor: NSColor = NSColor(srgbRed: 47/255, green: 107/255, blue: 1.0, alpha: 1.0)

    func makeCoordinator() -> Coordinator {
        Coordinator(stream: stream, input: input, cdpPort: cdpPort, focused: $focused)
    }

    func makeNSView(context: Context) -> SandboxScreenNSView {
        let view = SandboxScreenNSView()
        view.coordinator = context.coordinator
        view.focusRingColor = focusRingColor
        if let pos = focusPosition {
            PaneFocusRegistry.shared.register(view, at: pos)
        }
        return view
    }

    func updateNSView(_ nsView: SandboxScreenNSView, context: Context) {
        if let pos = focusPosition {
            PaneFocusRegistry.shared.register(nsView, at: pos)
        }
        nsView.focusRingColor = focusRingColor
        nsView.imageBoxNeedsRedraw(stream.latestImage)
    }

    final class Coordinator {
        let stream: SandboxStream
        let input: SandboxInput
        let cdpPort: Int
        @Binding var focused: Bool

        init(stream: SandboxStream, input: SandboxInput, cdpPort: Int, focused: Binding<Bool>) {
            self.stream = stream
            self.input = input
            self.cdpPort = cdpPort
            self._focused = focused
        }
    }
}

/// Pure AppKit view that paints the latest screenshot, captures mouse events
/// inside its bounds, and forwards keyboard while it's first responder.
final class SandboxScreenNSView: NSView {
    var coordinator: SandboxScreenView.Coordinator?
    var focusRingColor: NSColor = NSColor(srgbRed: 47/255, green: 107/255, blue: 1.0, alpha: 1.0)
    private var currentImage: NSImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { super.init(coder: coder); wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor }

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
            img.draw(in: target,
                     from: .zero,
                     operation: .copy,
                     fraction: 1.0,
                     respectFlipped: true,
                     hints: [.interpolation: NSImageInterpolation.medium])
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
        let w = size.width * scale
        let h = size.height * scale
        let x = container.minX + (container.width - w) / 2
        let y = container.minY + (container.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func localToImageRect() -> CGRect? {
        guard let img = currentImage, img.size.width > 0, img.size.height > 0 else { return nil }
        return aspectFitRect(forImage: img.size, in: bounds)
    }

    /// Translate a click in our local coords into local-image coords,
    /// flipping Y because AppKit's mouse Y origin is bottom-left.
    private func translate(_ point: CGPoint) -> (CGPoint, CGSize)? {
        guard let imgRect = localToImageRect() else { return nil }
        guard imgRect.contains(point) else { return nil }
        let lp = CGPoint(x: point.x - imgRect.minX,
                         y: imgRect.height - (point.y - imgRect.minY)) // flip Y
        return (lp, imgRect.size)
    }

    // MARK: - Mouse forwarding

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let coordinator = coordinator else { return }
        let local = convert(event.locationInWindow, from: nil)
        guard let (lp, size) = translate(local) else { return }
        Task { @MainActor in
            await coordinator.input.click(
                at: lp,
                localSize: size,
                nativeSize: coordinator.stream.nativeSize,
                scale: coordinator.stream.coordScale
            )
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let coordinator = coordinator else { return }
        let local = convert(event.locationInWindow, from: nil)
        guard let (lp, size) = translate(local) else { return }
        Task { @MainActor in
            await coordinator.input.click(
                at: lp,
                localSize: size,
                nativeSize: coordinator.stream.nativeSize,
                scale: coordinator.stream.coordScale,
                button: "right"
            )
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let coordinator = coordinator else { return }
        let local = convert(event.locationInWindow, from: nil)
        guard let (lp, size) = translate(local) else { return }
        let dx = -event.scrollingDeltaX
        let dy = -event.scrollingDeltaY
        Task { @MainActor in
            await coordinator.input.scroll(
                at: lp, localSize: size,
                nativeSize: coordinator.stream.nativeSize,
                scale: coordinator.stream.coordScale,
                dx: dx, dy: dy
            )
        }
    }

    // MARK: - Keyboard forwarding (v1.6 unified pipeline)
    //
    // Browser pane and chat panes share the same classifier
    // (`KeyboardEventTranslator`) and the same CDP backend (`CDPInput`).
    // The Browser pane targets port 9222 (foreground Chromium on :100);
    // chat panes target 9223/9224. v1.5 ran Browser keyboard through
    // xdotool inside the cuabot container, but xdotool wasn't reliably
    // present and the path drifted from the chat-pane pipeline. Unifying
    // on CDP closes both gaps.

    override func keyDown(with event: NSEvent) {
        guard let coordinator = coordinator else { return super.keyDown(with: event) }
        let port = coordinator.cdpPort
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
                await ClipboardBridge.copyFromBrowser(port: port)
                await CDPInput.dispatchKey(port: port, name: "c", modifiers: ["super"])
            }
        case .clipboardCut:
            Task { @MainActor in
                await ClipboardBridge.copyFromBrowser(port: port)
                await CDPInput.dispatchKey(port: port, name: "x", modifiers: ["super"])
            }
        case .ignore:
            break
        }
    }
}
