// Diakonos v1.7.1 echo-loop test.
//
// v1.7's 11/11 trigger-safety harness verified string classification in
// isolation but never modeled the full trigger → post → user-send →
// re-poll cycle. This case re-creates that cycle and verifies the
// v1.7.1 fix logic in ChatBridge: posted-content hashes are tracked,
// the next scrape with that exact content is skipped (no re-route),
// and Manual mode never auto-continues even without a hash match.
//
// Mirrors `ChatBridge.isEchoOfRecentPostback` + `.recordPostedHash` +
// the mode-gated `.continueThread` arm. Mirror, not import — keeps the
// test stand-alone (no Xcode toolchain target wiring needed).
import Foundation

enum PostbackMode { case manual, autoSend, fullAuto
    var sendsAutomatically: Bool { self != .manual }
}
enum Trigger { case start, continueThread, exit, none }

// --- Bridge state ---
struct Bridge {
    let cap = 20
    var postedHashes: [String: [Int]] = [:]
    var lastRouteID:  [String: UUID]  = [:]
    var activeThread: [String: Bool]  = [:]   // simplified: just a flag

    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func recordPost(_ body: String, convo: String, route: UUID) {
        var list = postedHashes[convo] ?? []
        list.append(Bridge.normalize(body).hashValue)
        if list.count > cap { list.removeFirst(list.count - cap) }
        postedHashes[convo] = list
        lastRouteID[convo] = route
    }

    func isEcho(_ msg: String, convo: String) -> Bool {
        guard let hs = postedHashes[convo] else { return false }
        return hs.contains(Bridge.normalize(msg).hashValue)
    }

    // Mirrors handle(...) decision — but only returns the routing
    // outcome string. "ECHO" = skipped via hash. "MANUAL_NOOP" = plain
    // text in active thread + Manual. "CONT_ROUTE" = continuation
    // routed (AutoSend / FullAuto). "TRIGGER_ROUTE" = explicit prefix.
    // "IGNORE" = nothing happens.
    mutating func decide(scraped: String, convo: String, postback: PostbackMode) -> String {
        if isEcho(scraped, convo: convo) { return "ECHO" }
        let trimmed = scraped.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\\Code:") || trimmed.hasPrefix("\\Codex:") { return "IGNORE" }
        if trimmed.hasPrefix("Code:") || trimmed.hasPrefix("Codex:") {
            activeThread[convo] = true
            return "TRIGGER_ROUTE"
        }
        if trimmed.hasPrefix("Exit:") || trimmed == "Exit" {
            activeThread[convo] = false
            postedHashes[convo] = nil
            return "EXIT"
        }
        // Plain text + active thread:
        if activeThread[convo] == true {
            if postback.sendsAutomatically { return "CONT_ROUTE" }
            return "MANUAL_NOOP"
        }
        return "IGNORE"
    }
}

// --- Cases ---
// Format: (label, sequence of (text, postback), expected outcomes)

struct Case {
    let label: String
    let initialActive: Bool
    let recordedPosts: [(body: String, route: UUID)]
    let scrapes: [(text: String, mode: PostbackMode, expect: String)]
}

let convo = "test-conversation"
let r1 = UUID()
let r2 = UUID()

let cases: [Case] = [
    Case(label: "Manual: explicit trigger routes",
         initialActive: false, recordedPosts: [],
         scrapes: [
            ("Code: pwd", .manual, "TRIGGER_ROUTE"),
         ]),

    Case(label: "Manual: posted reply sent → echo dedupe (THE bug)",
         initialActive: true,
         recordedPosts: [("Summary: ran pwd\n/Users/perlantir/Projects/diakonos", r1)],
         scrapes: [
            // The user manually pressed Send. The textarea content (the
            // posted reply) becomes a new user-message. v1.7 routed
            // this; v1.7.1 must skip via echo dedupe.
            ("Summary: ran pwd\n/Users/perlantir/Projects/diakonos", .manual, "ECHO"),
         ]),

    Case(label: "Manual: plain follow-up after echo dedupe → NO route",
         initialActive: true,
         recordedPosts: [("prior reply", r1)],
         scrapes: [
            ("prior reply", .manual, "ECHO"),
            ("thanks, that worked", .manual, "MANUAL_NOOP"),
         ]),

    Case(label: "Manual: new Code: after echo dedupe → fresh route",
         initialActive: true,
         recordedPosts: [("prior reply", r1)],
         scrapes: [
            ("prior reply", .manual, "ECHO"),
            ("Code: ls", .manual, "TRIGGER_ROUTE"),
         ]),

    Case(label: "AutoSend: posted reply sent → echo dedupe (NOT re-routed)",
         initialActive: true,
         recordedPosts: [("auto-sent reply", r1)],
         scrapes: [
            ("auto-sent reply", .autoSend, "ECHO"),
         ]),

    Case(label: "AutoSend: plain follow-up after echo → CONTINUATION routes",
         initialActive: true,
         recordedPosts: [("auto-sent reply", r1)],
         scrapes: [
            ("auto-sent reply", .autoSend, "ECHO"),
            ("now try this", .autoSend, "CONT_ROUTE"),
         ]),

    Case(label: "FullAuto: posted reply sent → echo dedupe",
         initialActive: true,
         recordedPosts: [("full-auto reply", r1)],
         scrapes: [
            ("full-auto reply", .fullAuto, "ECHO"),
         ]),

    Case(label: "Whitespace normalization (\\r\\n + trailing space matches)",
         initialActive: true,
         recordedPosts: [("body\nwith\nbreaks", r1)],
         scrapes: [
            ("body\r\nwith\r\nbreaks   \n", .manual, "ECHO"),
         ]),

    Case(label: "LRU eviction — beyond cap=20, oldest hash evicted",
         initialActive: true,
         recordedPosts: (1...25).map { ("body \($0)", UUID()) },
         scrapes: [
            ("body 1", .manual, "MANUAL_NOOP"), // evicted (oldest of 25 > 20)
            ("body 25", .manual, "ECHO"),       // still in LRU
         ]),

    Case(label: "Exit: clears echo state + active thread",
         initialActive: true,
         recordedPosts: [("prior reply", r1)],
         scrapes: [
            ("Exit:", .manual, "EXIT"),
            ("prior reply", .manual, "IGNORE"), // no longer dedupe'd, but no active thread → no route
         ]),

    Case(label: "Backslash escape still ignored",
         initialActive: false, recordedPosts: [],
         scrapes: [
            ("\\Code: literal discussion", .manual, "IGNORE"),
         ]),
]

var pass = 0, fail = 0
for c in cases {
    var b = Bridge()
    b.activeThread[convo] = c.initialActive
    for (body, route) in c.recordedPosts { b.recordPost(body, convo: convo, route: route) }
    var allOk = true
    var trace: [String] = []
    for (text, mode, expect) in c.scrapes {
        let got = b.decide(scraped: text, convo: convo, postback: mode)
        let ok = (got == expect)
        if !ok { allOk = false }
        trace.append("  '\(text.prefix(40))' [\(mode)] → \(got) (want \(expect)) \(ok ? "OK" : "FAIL")")
    }
    if allOk { pass += 1; print("[PASS] \(c.label)") }
    else     { fail += 1; print("[FAIL] \(c.label)"); for line in trace { print(line) } }
}
print("=== \(pass) pass / \(fail) fail ===")
exit(fail == 0 ? 0 : 1)
