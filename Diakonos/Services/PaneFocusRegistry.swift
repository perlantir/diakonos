import AppKit
import Combine
import SwiftUI

/// Registry that maps slot index (0..3, by visual order TL/TR/BL/BR) to a
/// weak reference to the focusable NSView inside that slot. Used by the
/// Cmd+1..4 menu commands. Slots register on appear, deregister on disappear.
@MainActor
final class PaneFocusRegistry: ObservableObject {
    static let shared = PaneFocusRegistry()

    private var registry: [PaneSlotPosition: WeakBox] = [:]

    private final class WeakBox {
        weak var view: NSView?
        init(_ v: NSView?) { view = v }
    }

    func register(_ view: NSView?, at position: PaneSlotPosition) {
        registry[position] = WeakBox(view)
    }

    func clear(_ position: PaneSlotPosition) {
        registry[position] = nil
    }

    /// Focus the slot at position. Returns true if a view was found and asked
    /// to become first responder.
    ///
    /// v1.7 Part B: logs to NSLog when focus fails so Nick can debug why
    /// Cmd+5 / Cmd+6 don't move focus in some 6-pane layouts. Common
    /// causes: (1) slot at that position is `.empty` (no view registers
    /// from EmptyPaneBody) — toggle to a real pane kind; (2) view was
    /// registered but is no longer in a window (weak ref).
    @discardableResult
    func focus(_ position: PaneSlotPosition) -> Bool {
        guard let view = registry[position]?.view else {
            NSLog("[Diakonos] PaneFocusRegistry.focus(\(position.rawValue)) — no view registered (slot likely .empty)")
            return false
        }
        guard let window = view.window else {
            NSLog("[Diakonos] PaneFocusRegistry.focus(\(position.rawValue)) — registered view has no window (panes torn down?)")
            return false
        }
        window.makeKeyAndOrderFront(nil)
        let made = window.makeFirstResponder(view)
        if !made {
            NSLog("[Diakonos] PaneFocusRegistry.focus(\(position.rawValue)) — makeFirstResponder returned false")
        }
        return made
    }
}

/// Notification posted by the CommandMenu when Cmd+1..4 fires.
extension Notification.Name {
    static let diakonosFocusSlot = Notification.Name("DiakonosFocusSlot")
}
