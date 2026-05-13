import Foundation
import AppKit
import SwiftUI

/// Latest screenshot of the cua sandbox display, suitable for an NSImageView /
/// `SwiftUI.Image(nsImage:)` consumer. Polls `POST /screenshot` at ~10 fps.
///
/// JSON shape: `{ "image": "<base64 JPEG>", "scale": 0.667 }`. Native screenshot
/// resolution is 1280×720 (cua's Xpra display). The `scale` factor maps
/// caller-supplied click coords to native pixels — input space is
/// (native_w * scale, native_h * scale). Stored here so `SandboxInput` can
/// use it for coord translation.
@MainActor
final class SandboxStream: ObservableObject {

    @Published private(set) var latestImage: NSImage? = nil
    @Published private(set) var nativeSize: CGSize = .zero
    @Published private(set) var coordScale: CGFloat = 1.0

    private var pollingTask: Task<Void, Never>?
    private let port: Int = 7842

    private var screenshotURL: URL {
        URL(string: "http://localhost:\(port)/screenshot")!
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            await self?.runPolling()
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func runPolling() async {
        var consecutiveErrors = 0

        while !Task.isCancelled {
            let started = Date()
            await pollOnce(consecutiveErrors: &consecutiveErrors)

            let target: TimeInterval = consecutiveErrors > 0 ? 0.5 : 0.1   // 10 fps; back off on errors
            let elapsed = Date().timeIntervalSince(started)
            let sleep = max(0.01, target - elapsed)
            try? await Task.sleep(nanoseconds: UInt64(sleep * 1_000_000_000))
        }
    }

    private func pollOnce(consecutiveErrors: inout Int) async {
        var req = URLRequest(url: screenshotURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        req.timeoutInterval = 2.0

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                consecutiveErrors += 1
                return
            }

            struct Payload: Decodable { let image: String; let scale: Double }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard let jpegData = Data(base64Encoded: payload.image),
                  let image = NSImage(data: jpegData) else {
                consecutiveErrors += 1
                return
            }

            consecutiveErrors = 0
            latestImage = image
            nativeSize = image.size
            coordScale = CGFloat(payload.scale)
        } catch {
            consecutiveErrors += 1
        }
    }
}

/// Wraps the cuabot HTTP API surface for input forwarding. Mouse coords are
/// translated from local SwiftUI view coords into cuabot's scaled input space.
@MainActor
final class SandboxInput: ObservableObject {

    private let port: Int = 7842
    private var baseURL: URL { URL(string: "http://localhost:\(port)")! }

    /// Forward a click. `localPoint` is in the local SwiftUI image-view
    /// coordinate space (with .topLeading origin); `localSize` is the rendered
    /// size of that view; `nativeSize` and `scale` come from `SandboxStream`.
    func click(at localPoint: CGPoint,
               localSize: CGSize,
               nativeSize: CGSize,
               scale: CGFloat,
               button: String? = nil) async {
        guard localSize.width > 0, localSize.height > 0,
              nativeSize.width > 0, nativeSize.height > 0 else { return }

        // Map local → native pixel coord first, then to cuabot's scaled input space.
        let nx = localPoint.x / localSize.width  * nativeSize.width
        let ny = localPoint.y / localSize.height * nativeSize.height
        let cx = Int((nx * scale).rounded())
        let cy = Int((ny * scale).rounded())

        var payload: [String: Any] = ["x": cx, "y": cy]
        if let button { payload["button"] = button }
        await postJSON("click", payload: payload)
    }

    func move(to localPoint: CGPoint,
              localSize: CGSize,
              nativeSize: CGSize,
              scale: CGFloat) async {
        guard localSize.width > 0, localSize.height > 0,
              nativeSize.width > 0, nativeSize.height > 0 else { return }
        let nx = localPoint.x / localSize.width  * nativeSize.width
        let ny = localPoint.y / localSize.height * nativeSize.height
        let cx = Int((nx * scale).rounded())
        let cy = Int((ny * scale).rounded())
        await postJSON("move", payload: ["x": cx, "y": cy])
    }

    func scroll(at localPoint: CGPoint,
                localSize: CGSize,
                nativeSize: CGSize,
                scale: CGFloat,
                dx: CGFloat,
                dy: CGFloat) async {
        guard localSize.width > 0, localSize.height > 0,
              nativeSize.width > 0, nativeSize.height > 0 else { return }
        let nx = localPoint.x / localSize.width  * nativeSize.width
        let ny = localPoint.y / localSize.height * nativeSize.height
        let cx = Int((nx * scale).rounded())
        let cy = Int((ny * scale).rounded())
        await postJSON("scroll", payload: ["x": cx, "y": cy,
                                           "dx": Int(dx.rounded()),
                                           "dy": Int(dy.rounded())])
    }

    func type(_ text: String) async {
        guard !text.isEmpty else { return }
        await postJSON("type", payload: ["text": text])
    }

    /// Special keys (Return, Tab, Escape, BackSpace, …) — cuabot's HTTP API
    /// does NOT expose /key (probed live; returns 404 despite --help). Fall
    /// back to xdotool inside the container via the /bash endpoint.
    func key(_ name: String, modifiers: [String] = []) async {
        let arg: String
        if modifiers.isEmpty {
            arg = name
        } else {
            arg = (modifiers + [name]).joined(separator: "+")
        }
        let escaped = arg.replacingOccurrences(of: "'", with: "'\\''")
        await postJSON("bash", payload: ["command":
            "DISPLAY=:100 xdotool key --clearmodifiers '\(escaped)' 2>/dev/null || true"])
    }

    private func postJSON(_ path: String, payload: [String: Any]) async {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        req.timeoutInterval = 3.0
        _ = try? await URLSession.shared.data(for: req)
    }
}
