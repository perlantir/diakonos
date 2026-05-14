import AppKit
import Foundation

/// Sole owner of the policy: "is this NSEvent a printable, a named special
/// key, or a command chord?" Both `WebAppPaneView` (chat panes, CDP on
/// 9223/9224) and `BrowserPaneView` (browser, CDP on 9222) call into this
/// translator so the two pipelines can't diverge.
///
/// Policy summary (v1.6):
///   - Cmd (.command) and Ctrl (.control) are **command modifiers** —
///     they invariably mean "chord," not "typing."
///   - Option (.option) and Shift (.shift) alone are **typing modifiers**
///     — they produce printable characters (Shift+2 → "@", Opt+e → "´",
///     Opt+e+e → "é"). They do NOT trigger the chord path.
///   - Named special keys (Return, Tab, Escape, arrows, Home/End/PgUp/PgDn,
///     F1-F12, BackSpace, Delete) take the dispatchKey route regardless of
///     modifiers — they're not typeable text.
///   - Clipboard intercepts: Cmd+V → `.clipboardPaste` (Mac → sandbox);
///     Cmd+C → `.clipboardCopy` (sandbox → Mac + forward); Cmd+X →
///     `.clipboardCut` (sandbox → Mac + forward). Cmd+A is just a chord.
///
/// The translator returns the route to take. The caller (each pane's
/// `keyDown(with:)`) is responsible for invoking the appropriate
/// `CDPInput` / `ClipboardBridge` method.
enum KeyboardEventTranslator {

    enum Route {
        /// Printable text — caller should `CDPInput.dispatchType(port:, text:)`.
        case type(String)
        /// Named key or chord — caller should
        /// `CDPInput.dispatchKey(port:, name:, modifiers:)`.
        case key(name: String, modifiers: [String])
        /// Mac → sandbox paste. Caller reads `NSPasteboard.general.string`
        /// and dispatches via `ClipboardBridge.paste(toPort:)`. Don't forward
        /// the key event — Chromium would paste an empty sandbox clipboard.
        case clipboardPaste
        /// Sandbox → Mac copy. Caller calls
        /// `ClipboardBridge.copyFromBrowser(port:)` AND forwards Cmd+C as a
        /// key chord so the page's native handler still runs.
        case clipboardCopy
        /// Sandbox → Mac cut. Same as copy but Cmd+X.
        case clipboardCut
        /// Empty event or one we explicitly drop.
        case ignore
    }

    /// Classify an `NSEvent`. The caller has already established that the
    /// view is first responder.
    static func classify(_ event: NSEvent) -> Route {
        let mods = event.modifierFlags
        let hasCmd  = mods.contains(.command)
        let hasCtrl = mods.contains(.control)
        let hasShift = mods.contains(.shift)
        let hasOpt   = mods.contains(.option)
        let hasCommandModifier = hasCmd || hasCtrl

        // Modifier-bit list passed to CDP. Order doesn't matter; CDPInput
        // bitmasks them.
        var modList: [String] = []
        if hasCmd   { modList.append("super") }
        if hasOpt   { modList.append("alt") }
        if hasCtrl  { modList.append("ctrl") }
        if hasShift { modList.append("shift") }

        // ---- Named-special-key table ----
        // These always take the dispatchKey route, even bare. CDP needs the
        // structured key/code/keyCode so Chromium fires the right
        // `keydown` event (typing 'Enter' as a char is a no-op).
        if let specialName = Self.namedKey(forKeyCode: event.keyCode) {
            return .key(name: specialName, modifiers: modList)
        }

        // ---- Command-modifier chord path ----
        // The character we want to send is the unmodified version: Cmd+V →
        // "v", Cmd+Shift+Z → "z" with shift in mods. Chromium's keyboard
        // shortcut handling expects the lowercase letter and a modifier bit.
        if hasCommandModifier {
            let raw = event.charactersIgnoringModifiers ?? ""
            // Single-key clipboard intercepts (Cmd + V / C / X). We only
            // trip this on Cmd alone (or Cmd+Shift+) — not Ctrl — because
            // Ctrl+V on macOS is rarely "paste."
            if hasCmd, !hasCtrl, !hasOpt {
                let key = raw.lowercased()
                if !hasShift {
                    switch key {
                    case "v": return .clipboardPaste
                    case "c": return .clipboardCopy
                    case "x": return .clipboardCut
                    default:  break
                    }
                }
            }
            guard !raw.isEmpty else { return .ignore }
            // Use the lowercased letter for plain-letter chords (Chromium's
            // shortcut table is canonicalized on lowercase). For symbols
            // like Cmd+/ we leave them as-is.
            let name: String
            if raw.count == 1, let scalar = raw.unicodeScalars.first,
               CharacterSet.letters.contains(scalar) {
                name = raw.lowercased()
            } else {
                name = raw
            }
            return .key(name: name, modifiers: modList)
        }

        // ---- Typing path ----
        // Shift and Option alone produce printable text. event.characters
        // already gives the composed character: Shift+2 → "@", Opt+e+e → "é".
        let typed = event.characters ?? ""
        if typed.isEmpty {
            return .ignore
        }
        // Strip control/private-use chars that AppKit sometimes emits for
        // arrow keys when keyCode mapping missed (e.g., custom keyboards).
        // The typeable subset: U+0020 ..= U+007E plus higher Unicode (for
        // diacritics and emoji typed via input methods).
        if typed.allSatisfy({ $0.isASCII && ($0.asciiValue ?? 0) < 0x20 }) {
            return .ignore
        }
        return .type(typed)
    }

    /// macOS virtual key code → CDPInput key-name. Names here MUST match
    /// the table in `CDPInput.dispatchKey`. F-keys and numpad are included.
    private static func namedKey(forKeyCode keyCode: UInt16) -> String? {
        switch Int(keyCode) {
        case 36:  return "Return"
        case 76:  return "Return"       // numpad Enter — same key, distinct keyCode
        case 53:  return "Escape"
        case 51:  return "BackSpace"
        case 117: return "Delete"
        case 48:  return "Tab"
        case 123: return "Left"
        case 124: return "Right"
        case 125: return "Down"
        case 126: return "Up"
        case 115: return "Home"
        case 119: return "End"
        case 116: return "Page_Up"
        case 121: return "Page_Down"
        // F1-F12 — macOS virtual key codes:
        // F1=122, F2=120, F3=99, F4=118, F5=96, F6=97, F7=98, F8=100,
        // F9=101, F10=109, F11=103, F12=111.
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:  return nil
        }
        // Note: numpad digit/operator keys (82-92, 65, 67, 69, 75, 78, 81)
        // fall through deliberately — their NSEvent.characters already
        // resolves to the printed digit/operator, so they take the typing
        // path. Treating them as named keys would require their own table
        // and gain nothing.
    }
}
