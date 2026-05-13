# Diakonos v1 — Build Spec

This is the v1 build spec Claude Code executes against. Read `CLAUDE.md` first for how to operate. Read `PROJECT_STATE.md` for current status. Read `docs/cua-integration.md` for what we know about the cua sandbox layer.

## Goal

A native macOS app that opens a single window with a 2x2 grid of resizable panes. Each pane runs an application inside a cua sandbox. Visual fidelity matches the design package in `design/`.

## Constraints

- macOS 14.0 (Sonoma) minimum
- SwiftUI for UI, AppKit only where SwiftUI is insufficient (window chrome, key handling for terminals)
- No App Sandbox; Hardened Runtime ON with JIT exceptions
- Bundle ID `com.uberkiwi.diakonos`
- Project generated via XcodeGen from `project.yml`
- Dependencies authorized for v1 (do not add others without asking):
  - SwiftTerm (Miguel de Icaza, MIT) — terminal emulation
  - That's the entire third-party dependency surface for v1. cua integration is via subprocess, not a Swift library.

## Design source of truth

All visual decisions come from `design/`:
- Tokens: `design/tokens.json` (colors, typography, spacing, radii, shadows)
- Screens: `design/screens/01-09*.png` and matching SVGs
- Each screen shows light + dark mode at 1440x900 and 1920x1080

When tokens specify a value, use it exactly. When the screens specify a layout, match it. When a detail is ambiguous, ask Nick rather than invent.

## Build phases

Execute phases in order. After each phase, write a checkpoint to `Docs/Checkpoints/<UTC-timestamp>-phase-<N>-<short-name>.md` and stop. Wait for ratification before the next phase.

---

### Phase 0: Project scaffold

**Goal:** Diakonos.app builds and launches, showing a blank window with the app's window chrome (title bar, traffic lights). Design tokens compiled into Swift.

**Deliverables:**
- `project.yml` — XcodeGen spec defining the Diakonos app target, macOS 14.0 deployment, Hardened Runtime entitlements (no App Sandbox), bundle ID `com.uberkiwi.diakonos`
- `Diakonos/App/DiakonosApp.swift` — `@main` SwiftUI App
- `Diakonos/App/Info.plist` (or generated via XcodeGen)
- `Diakonos/Design/Tokens.swift` — Swift constants converted from `design/tokens.json`. Colors as `Color` values, font sizes as `CGFloat`, spacing as `CGFloat`, radii as `CGFloat`, shadows as `Shadow` helpers
- `Diakonos/Design/Typography.swift` — `Font` helpers for SF Pro Display/Text/Mono at the token sizes
- `Diakonos/UI/RootView.swift` — placeholder root view (just shows "Diakonos" centered)
- `.gitignore` for Swift/Xcode/macOS

**Acceptance:**
- `xcodegen generate` succeeds
- `xcodebuild -scheme Diakonos -destination 'platform=macOS' build` succeeds
- Launching the built app shows a Mac window with traffic lights and a centered "Diakonos" label
- Window is resizable, titled "Diakonos"
- Design tokens are accessible in Swift via `DesignTokens.Color.accentPrimary` etc.

**Checkpoint:** `Docs/Checkpoints/<timestamp>-phase-0-scaffold.md`

---

### Phase 1: Workspace shell

**Goal:** The 2x2 pane layout per the main workspace screen (`design/screens/01-main-workspace.png`). No sandbox integration yet; panes show static placeholders. Dividers are draggable.

**Deliverables:**
- `Diakonos/UI/Workspace/WorkspaceView.swift` — top-level workspace layout. Vertical split of two horizontal splits = 2x2 grid. Each pane is independently resizable via dividers.
- `Diakonos/UI/Workspace/PaneView.swift` — pane container. Header bar with title, three-dot menu button, minimize/maximize/close buttons. Body is generic over pane content.
- `Diakonos/UI/Workspace/PaneHeader.swift` — pane header row
- `Diakonos/UI/Workspace/SplitDivider.swift` — the draggable divider with hover state per the design
- `Diakonos/UI/Toolbar/WorkspaceToolbar.swift` — the toolbar below the title bar: workspace dropdown (static "Diakonos" for v1), sandbox status indicator (static "Initializing" for v1), agent mode toggle (Manual / Autonomous), settings button, fullscreen button
- `Diakonos/UI/Components/SegmentedToggle.swift` — Manual/Autonomous toggle component
- `Diakonos/UI/Components/StatusIndicator.swift` — colored dot + label

**Pane content for Phase 1 is static placeholder per the "Initializing" state in the design** — each pane shows its icon, name, and "Sandbox is initializing..." text. No real terminal or browser yet.

**Pane assignments for v1 (hardcoded for v1, configurable in v0.2):**
- Top-left: Terminal
- Top-right: Claude Code
- Bottom-left: Agent Chat (Hermes)
- Bottom-right: Browser

**Acceptance:**
- Build succeeds
- Launching shows the 2x2 layout matching screen 01 (light mode, initializing state)
- Dividers can be dragged to resize panes
- Toolbar elements render and respond to hover/click states per component states in screen 09
- Dark mode swaps theming correctly (verify by toggling system appearance)
- Visual match against `design/screens/01-main-workspace.png` is close enough that Nick says "yes, that's it" — minor pixel differences acceptable, structural differences not

**Checkpoint:** `Docs/Checkpoints/<timestamp>-phase-1-shell.md` — include a screenshot of the running app in light and dark mode.

---

### Phase 2: cua integration

**Goal:** Diakonos can spin up a single cua sandbox, run a Terminal inside it, and surface that terminal's output in the top-left pane. Sandbox status shown correctly in the toolbar indicator.

**Required reading before starting:**
- `docs/cua-integration.md`
- cua's docs at https://cua.ai/docs and the README at https://github.com/trycua/cua
- Specifically: how to spin up a sandbox programmatically, what subprocess invocations look like, how to attach to a PTY inside the sandbox

**Deliverables:**
- `Diakonos/Services/CUASandboxManager.swift` — actor managing sandbox lifecycle. Methods: `start(image:)`, `stop(id:)`, `restart(id:)`, `currentStatus(id:)`. Operates by invoking cua's CLI/SDK as subprocesses and parsing output.
- `Diakonos/Services/CUAProcessSupervisor.swift` — supervises the cua subprocesses themselves (similar pattern to Diak's HermesProcessSupervisor if relevant — but adapt to cua's actual interface).
- `Diakonos/Models/SandboxState.swift` — sandbox status enum (`initializing`, `running`, `stopped`, `error`)
- `Diakonos/UI/Workspace/Panes/TerminalPaneView.swift` — pane content that hosts a SwiftTerm view connected to a PTY inside the cua sandbox
- SwiftTerm dependency added to `project.yml` SPM dependencies

**Acceptance:**
- Build succeeds
- Launching Diakonos triggers cua sandbox startup
- Toolbar status indicator shows "Initializing" then "Healthy" once sandbox is up
- Top-left pane shows a working terminal connected to the sandboxed shell
- Typing in the terminal pane sends keystrokes to the sandbox; output streams back
- Other three panes still show their Phase 1 placeholders

**Checkpoint:** `Docs/Checkpoints/<timestamp>-phase-2-cua.md` — include a screenshot of the running terminal pane and a description of cua's actual integration surface (since we're partly discovering it during this phase).

---

### Phase 3: Four panes live

**Goal:** All four panes wired up.

**Deliverables:**
- `Diakonos/UI/Workspace/Panes/ClaudeCodePaneView.swift` — SwiftTerm pane that spawns `claude` inside the sandbox
- `Diakonos/UI/Workspace/Panes/HermesAgentPaneView.swift` — SwiftTerm pane that spawns `hermes` inside the sandbox; orange-themed terminal styling per Hermes' native CLI
- `Diakonos/UI/Workspace/Panes/BrowserPaneView.swift` — WKWebView pane with a URL bar (back, forward, address field, reload). For v1, this is a regular WKWebView pointing at whatever URL the user types. (Wiring this to a sandboxed Chromium is v0.3 work.)
- Each pane connects to the cua sandbox manager and reflects its own sandbox status in its header

**Acceptance:**
- All four panes render and operate independently
- Each pane shows correct visual treatment per the active state in screen 01
- Terminal, Claude Code, and Hermes panes accept input and show output
- Browser pane navigates to URLs
- Stopping/restarting one pane's sandbox doesn't affect others

**Checkpoint:** `Docs/Checkpoints/<timestamp>-phase-3-panes.md` with a screenshot of all four panes active.

---

### Phase 4: Preferences and polish

**Goal:** Preferences window per `design/screens/03-preferences.png`. Final visual pass. Dark mode verified across all surfaces.

**Deliverables:**
- `Diakonos/UI/Preferences/PreferencesWindow.swift` — preferences window with sidebar navigation
- Sections per screen 03: General, Sandbox, Panes, Agent, Shortcuts, About
- `Diakonos/UI/Components/` additions as needed for sidebar rows, switches, segmented controls, text fields, dropdowns, buttons, sliders — all per the component states board in screen 03
- API keys storage via Keychain (Anthropic, OpenAI, Hermes, others as the design shows)
- `Diakonos/UI/Components/AppIcon.swift` or `.icns` asset built from `design/screens/09-assets-naming.png`'s app icon spec

**Acceptance:**
- Preferences accessible via `Cmd+,`
- All six sidebar sections render
- Settings persist across launches (UserDefaults or SwiftData as appropriate)
- API keys store in Keychain securely
- Dark mode renders correctly across preferences
- App icon shows correctly in Dock, Cmd+Tab, and About

**Checkpoint:** `Docs/Checkpoints/<timestamp>-phase-4-prefs.md` with screenshots of every preferences section in both light and dark mode.

---

## Phase boundaries

Don't work ahead. If you finish Phase 1 and feel tempted to start Phase 2, stop, write the checkpoint, wait. Cumulative momentum across phases is how coherence drifts.

If a phase is taking dramatically longer than estimated (more than 2x), stop and write a status checkpoint asking Nick whether to continue or adjust.

If you discover a phase's deliverables aren't possible as specified (e.g., cua's subprocess interface fundamentally differs from our assumption), stop, write a status checkpoint, and surface options.

## Out-of-scope for v1

Listed explicitly so you don't accidentally do them:

- Onboarding flow (screen 02) — defer to v0.2
- Layout picker / preset manager (screen 04) — defer to v0.2
- Agent control panel (screen 05) — defer to v0.3
- Sandbox status detail popover (screen 06) — defer to v0.2; v1 has just the toolbar indicator
- Empty pane state (screen 07) — defer to v0.2; v1 has hardcoded pane assignments
- Sandbox error state (screen 08) — defer to v0.2; v1 has basic error logging
- Multi-window support
- Sparkle, notarization, Sentry, distribution work
- Real sandboxed Chromium in browser pane (v0.3)
- Tests with coverage targets

## Done definition for v1

Nick opens Diakonos.app on his machine. He sees four panes wired up to running sandboxes. He uses each pane for a few minutes. Nothing crashes. The visual quality matches the design package. He's willing to commit it to GitHub.

That's v1. Ship it, ratify, then plan v0.2.
