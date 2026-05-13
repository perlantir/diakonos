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
    @discardableResult
    func focus(_ position: PaneSlotPosition) -> Bool {
        guard let view = registry[position]?.view, let window = view.window else {
            return false
        }
        window.makeKeyAndOrderFront(nil)
        return window.makeFirstResponder(view)
    }
}

/// Notification posted by the CommandMenu when Cmd+1..4 fires.
extension Notification.Name {
    static let diakonosFocusSlot = Notification.Name("DiakonosFocusSlot")
}
