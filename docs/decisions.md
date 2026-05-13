# Diakonos — Architectural Decisions

This is the locked-decisions log. Each decision is ratified by Nick and Claude Code should not relitigate. Decisions are immutable once written here; if circumstances change and a decision needs revisiting, Claude Code surfaces it and Nick decides whether to amend.

## D1 — Native macOS, SwiftUI

**Decision:** Diakonos is a native macOS app built with SwiftUI (with AppKit interop where SwiftUI is insufficient).

**Rationale:** Quality bar — the design package shows an Apple-HIG aesthetic that Electron can't deliver. Smaller binary, native scrolling, proper accessibility, real macOS feel. Matches the bar Nick set with Diak.

**Alternatives considered:** Electron + xterm.js (faster build but worse feel), Tauri (similar tradeoffs).

---

## D2 — macOS 14.0 minimum

**Decision:** Deployment target is macOS 14.0 Sonoma.

**Rationale:** SwiftData, modern SwiftUI features, recent virtualization API improvements. Targeting older versions is significant work for minimal audience expansion.

---

## D3 — No App Sandbox

**Decision:** App Sandbox entitlement is OFF.

**Rationale:** Diakonos spawns subprocesses (cua, sandboxed apps), embeds terminals, and otherwise needs system-level operations the App Sandbox prevents. Distribution via Developer ID + notarization (not Mac App Store).

---

## D4 — cua via subprocess, not as a library

**Decision:** Diakonos invokes cua via subprocess calls to `cuabot` and/or other CLI tools. cua is not linked as a Swift library, and we don't embed Python in Diakonos.

**Rationale:** cua is Python-based. Bridging Python into Swift is heavy maintenance and contradicts our "native Mac" thesis. Subprocess is a clean integration boundary — cua evolves independently, Diakonos talks to it as a service.

**Implication:** Users must install cua separately before running Diakonos. v1 README documents this; later versions may bundle installation.

**Note (2026-05-13, v1.1):** Partially superseded — D4 now applies only to the Browser pane. The Terminal, Claude Code, and Terminal 2 panes in v1.1 are pure native macOS (no cua, no Docker). See `Docs/v1.1-spec.md` for the architecture pivot.

---

## D5 — SwiftTerm for terminal panes

**Decision:** Terminal emulation in the three terminal panes (Terminal, Claude Code, Hermes Agent Chat) uses [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).

**Rationale:** Only mature Swift-native terminal emulator. MIT-licensed. Used in other Mac terminal products. Maintained.

**Risk:** SwiftTerm has a smaller community than xterm.js. Some edge cases may need patches. Acceptable for v1.

---

## D6 — WKWebView for browser pane in v1

**Decision:** The browser pane in v1 uses WKWebView (Safari's engine) pointed at user-typed URLs. It is NOT a sandboxed Chromium video stream from cua.

**Rationale:** Streaming cuabot's sandboxed Chromium H.265 video into a SwiftUI view is real engineering and not v1 critical path. WKWebView gives us "a browser pane that works" today; we upgrade to sandboxed Chromium in v0.3+.

**Tradeoff:** v1's browser pane is NOT actually sandboxed in the product-marketing sense. The other three panes are. This is a known v1 limitation. Document in README.

---

## D7 — One window, four hardcoded panes for v1

**Decision:** v1 ships with a single window containing exactly four panes in a 2x2 grid. Pane assignments are hardcoded: top-left Terminal, top-right Claude Code, bottom-left Hermes Agent Chat, bottom-right Browser.

**Rationale:** Layout presets, custom pane assignments, multi-window — all v0.2+. v1 proves the architecture.

---

## D8 — XcodeGen for project generation

**Decision:** The Xcode project is generated from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen).

**Rationale:** `.xcodeproj` files are gnarly to merge in git. `project.yml` is plain text, diff-able, and reproducible. Standard practice for Swift projects.

**Implication:** Don't hand-edit `Diakonos.xcodeproj`. Edit `project.yml`, run `xcodegen generate`. The `.xcodeproj` is gitignored.

---

## D9 — Open source MIT, going to GitHub

**Decision:** Diakonos is open-source, MIT-licensed, hosted at `github.com/perlantir/diakonos`.

**Rationale:** Nick's stated goal — share with others who'd want the same tool. MIT permits commercial use, modification, distribution. cua is also MIT, no license incompatibility.

---

## D10 — No tests for v1 (visual verification by Nick)

**Decision:** v1 does not pursue test coverage targets. Tests written where they verify meaningful behavior (e.g., a state machine), but no requirement to test UI components.

**Rationale:** v1 is a consumer UI product where visual quality matters more than internal correctness. Nick visually verifies acceptance. Tests come back in v0.2+ when the surface stabilizes.

---

## D11 — Design tokens are authoritative

**Decision:** `design/tokens.json` is the source of truth for colors, typography, spacing, radii, and shadows. Swift code reads these as compile-time constants.

**Rationale:** Prevents drift between design and code. If a value isn't in tokens, surface it; don't invent.

---

## D12 — Name: Diakonos

**Decision:** Product name is Diakonos. Greek for "servant" (διάκονος). Bundle ID `com.uberkiwi.diakonos`. Repo `github.com/perlantir/diakonos`.

**Rationale:** Distinctive, technical-but-not-cold, evokes the agent-serves-you ethos. One prior project of the same name (a dormant Linux text editor) exists but doesn't pose a brand conflict.

---

## Future decisions to surface

These will become decisions when we reach the relevant phase:

- **F1:** Exact cua subprocess interface (CLI flags, JSON output format) — Phase 2 will determine
- **F2:** PTY attachment pattern for terminal panes inside cua sandboxes — Phase 2 will determine
- **F3:** Whether v0.3 keeps WKWebView with optional sandboxed Chromium toggle, or makes sandboxed Chromium the default
- **F4:** Keychain schema for API keys (Anthropic, OpenAI, Hermes, etc.)
- **F5:** Whether v0.2's "layout presets" are stored in UserDefaults or SwiftData
