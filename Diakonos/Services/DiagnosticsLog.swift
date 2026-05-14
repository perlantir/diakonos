import Foundation
import Combine

@MainActor
final class DiagnosticsLog: ObservableObject {
    static let shared = DiagnosticsLog()

    struct Entry: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let kind: Kind
        let detail: String

        enum Kind: String {
            case triggerDetected = "trigger"
            case routedToAgent = "route"
            case responseFromAgent = "response"
            case postedToChat = "postback"
            case selectorMissing = "selector"
            case error = "error"
            case info = "info"
        }
    }

    @Published private(set) var entries: [Entry] = []

    private let capacity = 500

    func log(_ kind: Entry.Kind, _ detail: String) {
        let entry = Entry(timestamp: Date(), kind: kind, detail: detail)
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        NSLog("[Diakonos] \(kind.rawValue): \(detail)")
    }

    func clear() { entries.removeAll() }
}
