import Foundation

/// The 9-state route lifecycle (v1.7 §6). One state machine instance per
/// active route — keyed by `routeID` in the parent ChatBridge. The
/// machine never skips states; transitions are linear except for the
/// `closed` terminal (which can be reached from any non-closed state on
/// an explicit `Exit:` trigger).
///
/// Why a state machine at all? v1.5/v1.6 conflated detection, dispatch,
/// reply capture, and postback into a single async closure. That made
/// the timing semantics opaque: was a particular event-log entry
/// "the route was sent" or "the reply landed"? With explicit states,
/// every transition logs a typed event into the per-session JSONL log
/// and the Diagnostics tab can render a timeline.
enum RouteState: String, Codable, CaseIterable {
    case idle
    case routeDraftDetected
    case awaitingDispatch
    case sentToTarget
    case targetRunning
    case replyCaptured
    case draftPostedToChat
    case awaitingUserReview
    case closed
}

/// A single route's lifecycle controller.
@MainActor
final class RouteStateMachine {
    let routeID: UUID
    let envelope: RouteEnvelope
    /// Per-conversation pinned snapshot (role-card version, project hash,
    /// protocol version). Settings edits to role cards after the
    /// session starts do NOT update an in-flight route — the snapshot
    /// is captured here at construction.
    let snapshot: RouteSnapshot

    @MainActor
    private(set) var state: RouteState = .idle

    /// Hook called on every transition. The owning ChatBridge attaches
    /// the SessionEventLog appender here.
    var onTransition: ((RouteState, RouteState) -> Void)?

    init(routeID: UUID, envelope: RouteEnvelope, snapshot: RouteSnapshot) {
        self.routeID = routeID
        self.envelope = envelope
        self.snapshot = snapshot
    }

    /// Advance to a new state. Logs the transition. Refuses backwards
    /// or invalid transitions (programming error → assert in DEBUG,
    /// silently no-op in release).
    func transition(to next: RouteState) {
        guard isAllowed(from: state, to: next) else {
            #if DEBUG
            assertionFailure("Invalid RouteState transition: \(state) → \(next) for route \(routeID)")
            #endif
            return
        }
        let prev = state
        state = next
        onTransition?(prev, next)
    }

    /// True when transitioning is legal. The happy path is forward
    /// progression; `closed` is reachable from any non-closed state
    /// (e.g., user typed `Exit:` mid-flight).
    private func isAllowed(from: RouteState, to: RouteState) -> Bool {
        if to == .closed { return from != .closed }
        let forward: [RouteState] = [
            .idle, .routeDraftDetected, .awaitingDispatch, .sentToTarget,
            .targetRunning, .replyCaptured, .draftPostedToChat,
            .awaitingUserReview, .closed
        ]
        guard let fi = forward.firstIndex(of: from),
              let ti = forward.firstIndex(of: to) else { return false }
        return ti == fi + 1
    }
}

/// Immutable per-session snapshot. The state machine carries this so
/// every event logged into the per-session JSONL has full provenance
/// without needing to round-trip back to settings or stores.
struct RouteSnapshot: Codable, Equatable {
    let roleCardID: String
    let roleCardVersion: String
    let protocolVersion: String
    let projectContextHash: String
    let createdAt: Date
}
