# Diakonos

A native macOS dev workspace with AI panes and a sandboxed browser.

Diakonos gives you a four-pane native Mac window: two real terminals on your
real machine, Claude Code on a project folder you pick, and a sandboxed
Chromium browser streamed from a [cua](https://github.com/trycua/cua)
container. The first three are pure native; the browser is the only surface
where untrusted web content lives, so it's isolated.

Open source, MIT.

## Status

v1.7 in active development. Installed locally to `/Applications/Diakonos.app`;
not yet code-signed or notarized.

## What's new in v1.7

**Routing protocol redesigned end-to-end.** v1.5/v1.6 had an implicit,
always-on routing path. v1.7 is explicit, layered, versioned, and safe.

- **Per-pane modes** — `PaneMode`: `.soloChat` (default for new chat
  panes) / `.coordinator` (routes `Code:`/`Codex:` triggers) /
  `.implementer` (the routed target) / `.browserDriver`. Header chip
  toggles for chat panes. **v1.5 chat panes that auto-routed now
  default to `.soloChat` after upgrade — flip the chip to opt in.**
- **Three postback modes** — `PostbackMode`:
  - `Manual` (default): response in textarea, you press Send. Banner
    above composer if you'd been typing — your draft is preserved.
  - `Auto-send`: Diakonos clicks Send 300 ms after writing the
    response (long enough for React to settle).
  - `Full Auto`: assistant's `Code:`/`Codex:` ALSO route. Autonomous
    loop, with all of: per-conversation opt-in, max-turns ceiling
    (Preferences, default 10), red "AUTO N/MAX" chip, always-visible
    Stop button.
- **Versioned role cards** — markdown prompts at
  `~/Library/Application Support/Diakonos/RoleCards/<id>@<semver>.md`.
  5 bundled defaults seeded on first run. Settings → Role Cards
  editor; save auto-bumps patch. Active sessions pin to their version.
- **AGENTS.md canonical** — Diakonos reads `AGENTS.md`,
  `.diakonos/context.md`, and `CLAUDE.md` from your chosen project
  folder. Auto-creates templates if missing. CLAUDE.md should
  `@AGENTS.md` to import the canonical view.
- **Trigger safety** — DOM attribution (user-only selector, verified),
  message-start, no-code-block, no-quote, `\Code:` escape,
  per-conversation Confirm/Cancel/Always modal on first route.
- **9-state route state machine** with structured envelope
  (route_id, project_root, hashes, role card version) and
  append-only JSONL session log under
  `~/Library/Application Support/Diakonos/Sessions/<conv-id>.jsonl`.
- **CWD fix** — routed subprocess (`claude --print` / `codex exec`)
  now runs in your project folder. v1.5/v1.6 silently inherited
  Diakonos's launch CWD; v1.7 sets `Process.currentDirectoryURL`
  explicitly. Self-test runs at every app launch.
- **Context Doctor** — Settings → Diagnostics → "Check Context"
  surfaces conflicts (test command divergence, missing imports,
  missing files) across AGENTS.md / CLAUDE.md / .diakonos/context.md.
- **Browser content untrusted** — `mcp_browser.py` tool descriptions
  warn agents that page content is data, not instructions. Route
  detection never fires on browser-pane content.

See `docs/v1.7-spec.md` for the protocol, `docs/architecture/routing-protocol.md`
for the state machine + envelope, and `docs/architecture/role-cards.md`
for the authoring guide.

## What's in v1.6

- **Keyboard pipeline unified.** Every pane (Terminal, Claude Code, Codex,
  Chat panes, Browser) routes through one classifier and one CDP backend.
  Fixes Shift+symbol regressions (`!@#$%`…), adds F1-F12, and corrects
  Option-key diacritics (`é`, `ç`, `´`). Empirically validated 27/27 in
  `scripts/keyboard_cdp_harness.py`.
- **Mac ↔ sandbox clipboard.** Cmd+V pastes from your Mac clipboard into a
  pane's Chromium. Cmd+C / Cmd+X scrape the sandbox selection back to the
  Mac clipboard. Text only for v1.6; images / rich types are v1.7.
- **6-pane mode (NEW).** Toolbar 4/6 toggle switches between 2×2 and 2×3
  layouts. Two new positions: top-mid, bottom-mid. Cmd+1..6 focus shortcuts.
  State persists across mode toggles and app launches; v1.5 layouts
  auto-migrate.
- **Half-landed audit fix.** `EmptyPaneBody`'s dropdown is now derived
  from `PaneSlotKind.allCases`, so a new pane kind can't silently fail to
  appear in the picker (the bug class that bit v1.3 and v1.5).

See `Docs/v1.6-spec.md` for architecture details.

## What's in v1.5

- **Browser pane fills the pane.** v1.4 sized chromium small inside a
  fixed-1280×720 cuabot screenshot, leaving 75% black margin. v1.5
  launches chromium fullscreen so the screenshot is 100% chromium.
- **Two new sandboxed pane kinds**:
  - **Claude Chat** (pinned to `https://claude.ai`)
  - **ChatGPT** (pinned to `https://chatgpt.com`)
  Each runs in its own headless chromium-like instance with its own
  `--user-data-dir`. **Login persists across Diakonos restarts.**
- **ChatBridge — bidirectional message routing**:
  - Type `Code: <prompt>` at the start of a chat message → routes the
    payload to your Claude Code pane via `claude --print` with session-id
    continuity.
  - Type `Codex: <prompt>` → routes to Codex pane.
  - Type `Exit:` → ends the routing thread for that conversation.
  - **Per-conversation thread state.** Switching to a new chat
    conversation resets routing.
  - **The agent's response is placed in the chat's textarea, NOT
    auto-submitted.** You review and press Send yourself.
  - **Visual badge:** the chat pane's header shows `→ Claude Code` or
    `→ Codex` while a routing thread is active.
- **Diagnostics tab** in Settings: last 500 ChatBridge events. Selector
  failures surface here when chat-site DOMs change.

## ⚠️ v1.5 fragility note

The ChatBridge depends on DOM selectors for claude.ai and chatgpt.com
which change without notice. If routing stops working, open Settings →
Diagnostics — `selectorMissing` events tell you which site's DOM has
shifted. The selector source lives at
`Diakonos/Services/ChatPostbackJS.swift`.

## Install

```
xcodebuild -configuration Release build
cp -R build/release/Build/Products/Release/Diakonos.app /Applications/
xattr -dr com.apple.quarantine /Applications/Diakonos.app
```

**First launch:** right-click → Open → Open (Diakonos is unsigned in v1.4;
Developer ID + notarization is v1.5+). After that first trust, Spotlight,
Launchpad, and Dock launch work normally.

## What's in v1.3 (built on v1.2)

- **Codex pane** — runs `codex --dangerously-bypass-approvals-and-sandbox`
  natively with its own folder picker. OAuth handled by `codex login`.
- **Computer-use MCP bridge** — Claude Code and Codex panes get auto-registered
  with a `diakonos-browser` MCP server that exposes the sandboxed Chromium as
  `browser_screenshot / browser_click / browser_type / browser_key /
  browser_scroll / browser_navigate / browser_current_url` tools. Agent
  panes can drive what the Browser pane shows.
- **Dynamic Chromium resize** — Browser pane observes its size; Chromium
  resizes inside the sandbox to match (via CDP `Browser.setWindowBounds`).
- **Floating Xpra Mac window suppressed by default** — cua's per-window
  Mac surface is killed; opt in via Browser 3-dot → "Open in floating window".
- **Accent picker actually works** — 7-chip selector in Settings → General,
  persisted across launches, applied via `.tint()`.
- **No API keys to configure** — agents auth via their own CLI subscriptions
  (`claude login`, `codex login`).

## What's in v1.2

- Single window with a 2x2 grid of resizable panes
- **Each slot is reassignable** — Close pops the screen-07 empty
  placeholder with a dropdown to pick Terminal / Claude Code / Browser
- Default layout: top-left Terminal, top-right Claude Code, bottom-left
  Terminal 2, bottom-right Browser. User changes persist via UserDefaults.
- **Cmd+1..4** focus the four pane positions
- Pane header buttons all work: minimize collapses, maximize fills,
  close swaps to empty, 3-dot menu has kind-specific actions
- Native terminals: `$SHELL -l` in `$HOME` on the real Mac
- Claude Code: `claude --dangerously-skip-permissions` in a
  user-pickable project folder (folder persists across launches);
  auto-accepts the trust prompt on spawn
- Browser: sandboxed Chromium streamed via a **screenshot-stream
  protocol** (10 fps from cuabot, mouse + keyboard forwarded through
  cuabot's HTTP API). URL bar shows what Chromium actually displays
  (via CDP); URLs reuse the current tab instead of stacking.
- Preferences: API keys in Keychain auto-injected into pane env
  (ANTHROPIC_API_KEY, OPENAI_API_KEY, GOOGLE_API_KEY); model picker
  drives `ANTHROPIC_MODEL`; theme picker actually swaps light/dark.
- macOS 14.0+ (Sonoma)

## What's not in v1.1

- Multi-window support
- Custom pane layouts / pane reassignment (planned for v0.2)
- Onboarding (v0.2)
- Code signing, notarization, auto-update (v0.5+)
- CDP-based URL feedback in the Browser pane's address bar (v1.2)

## ⚠️ Security note

The Claude Code pane runs `claude --dangerously-skip-permissions`. The
Codex pane runs `codex --dangerously-bypass-approvals-and-sandbox`. **Both
mean the agent can read, modify, and delete any file on your Mac that
your user account can touch — without prompting you for confirmation on
each operation.** That's an intentional product choice for a power-user
workspace, but it means:

- Don't run Diakonos against folders containing irreplaceable data without
  backups.
- Don't share your screen with strangers while Diakonos is doing autonomous
  work.
- The Browser pane's sandboxed Chromium is the only surface that's
  isolated from your filesystem; the three terminal/agent panes are not.

If you want the v1 behavior (everything sandboxed), `git checkout
phase/0-v1-build`.

## Building from source

Requires:
- macOS 14.0+ (Sonoma or later)
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [cua](https://github.com/trycua/cua) installed and running (Browser pane
  only — other panes work without it)
- Docker Desktop (for cua; Browser pane only)

To build:
```
git clone https://github.com/perlantir/diakonos.git
cd diakonos
xcodegen generate
open Diakonos.xcodeproj
```

The Browser pane is the only piece that needs cua + Docker. If Docker isn't
running, the Browser pane shows a "Sandbox initializing…" placeholder; the
other three panes work fine.

## License

MIT. See [LICENSE](LICENSE).

## Credits

Diakonos is built by [Nick / perlantir](https://github.com/perlantir).

Powered by [cua](https://github.com/trycua/cua),
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), Apple's WebKit,
and the [Xpra](https://xpra.org/) HTML5 client.
