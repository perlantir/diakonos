import AppKit
import Foundation

/// Mac NSPasteboard ↔ sandbox-Chromium clipboard bridge.
///
/// The Mac's `NSPasteboard.general` and the sandboxed Chromium's clipboard
/// are isolated — Chromium runs inside cuabot's Docker container and has
/// its own X11 selection / browser clipboard. Cmd+V in a pane was sending
/// the chord to Chromium and getting an empty paste. v1.6 routes paste
/// through this bridge:
///
///   - `paste(toPort:)` reads `NSPasteboard.general.string(forType: .string)`
///     and types it via CDP `Input.dispatchKeyEvent type:'char'`. The
///     **key event is NOT forwarded** because Chromium's native paste
///     handler would clobber what we just typed with an empty clipboard.
///
///   - `copyFromBrowser(port:)` evaluates `window.getSelection().toString()`
///     in the sandbox via CDP `Runtime.evaluate`, then writes the result to
///     `NSPasteboard.general`. The Cmd+C chord IS also forwarded so the
///     page's native copy handler (which may set richer mime types) still
///     runs in the sandbox.
///
///   - `cutFromBrowser(port:)` is identical to copy but corresponds to Cmd+X.
///     The forwarded chord triggers Chromium's native cut, which deletes
///     the selection in the sandbox; we capture the text first.
@MainActor
enum ClipboardBridge {

    /// Mac → sandbox paste. Reads NSPasteboard and dispatches text via CDP.
    /// Returns true if anything was pasted. Callers should NOT forward the
    /// Cmd+V key event after invoking this.
    @discardableResult
    static func paste(toPort port: Int) async -> Bool {
        guard let s = NSPasteboard.general.string(forType: .string), !s.isEmpty else {
            return false
        }
        await CDPInput.dispatchType(port: port, text: s)
        return true
    }

    /// Sandbox → Mac copy. Reads `window.getSelection().toString()` from
    /// the sandbox and writes it to NSPasteboard. Caller SHOULD also
    /// forward the Cmd+C/Cmd+X chord (via CDPInput.dispatchKey) so the
    /// page's native copy/cut handler runs.
    static func copyFromBrowser(port: Int) async {
        let js = "(()=>{ try { return (window.getSelection && window.getSelection()) ? String(window.getSelection().toString() || '') : ''; } catch(e) { return ''; } })()"
        guard let raw = await CDPInput.evaluate(port: port, expression: js) else { return }
        let unquoted = Self.unquoteJSON(raw)
        guard !unquoted.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(unquoted, forType: .string)
    }

    private static func unquoteJSON(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("\""), t.hasSuffix("\""), t.count >= 2 {
            t.removeFirst(); t.removeLast()
        }
        return t.replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
