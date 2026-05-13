# Diakonos — Project State

Live source-of-truth for Diakonos. Update when phases advance or architectural decisions change. Claude Code reads this; only Nick writes it.

Last human-authored update: 2026-05-12 (initial bootstrap)

## Current Phase

**Phase 0: Bootstrap and v1 build**

The repo is freshly initialized from a bootstrap zip. No code yet. Claude Code's first job is to execute `BUILD_SPEC.md` end-to-end, producing v1 in phases with checkpoints in between.

Phase branch: `phase/0-v1-build` (to be created from main on Claude Code's first commit)

## Repository State

- Main branch: empty repo, no code yet
- Active phase branch: not yet created
- Design assets: `design/` folder, populated from the design package
- Build spec: `BUILD_SPEC.md`

## Locked Architectural Decisions

These are ratified by Nick. Don't relitigate without explicit approval.

1. **Native macOS app, not Electron.** SwiftUI for UI, AppKit where SwiftUI is insufficient.
2. **Minimum macOS 14.0 (Sonoma).** Required for SwiftData and recent SwiftUI features.
3. **App sandbox: OFF.** Diakonos manages subprocesses and spawns cua sandboxes; the macOS App Sandbox prevents this. Will be distributed via Developer ID + notarization in a later phase.
4. **Hardened Runtime: ON** with `cs.allow-jit`, `cs.disable-library-validation`, `cs.allow-unsigned-executable-memory`.
5. **Bundle ID:** `com.uberkiwi.diakonos`
6. **cua integration via subprocess.** Diakonos shells out to cua's CLI (`cuabot`, `cua` Python SDK called via subprocess), not by linking cua as a library. This keeps Diakonos in Swift and lets cua evolve independently.
7. **Project generation via XcodeGen.** Don't hand-edit `.xcodeproj`; it's regenerated from `project.yml`.
8. **One window, four panes.** Per the design package. Window is resizable; panes are independently resizable via dividers. No multi-window support in v1.
9. **Terminal emulation via SwiftTerm.** For the three terminal panes (Terminal, Claude Code, Hermes Agent Chat). Browser pane uses WKWebView for v1 (will reconsider in v0.3+ if cua provides a video stream surface for sandboxed Chromium).
10. **Open source, MIT license.** Going to GitHub at `github.com/perlantir/diakonos`.
11. **No tests required for v1.** Visual verification by Nick. Write tests where they meaningfully verify behavior, but no coverage targets.
12. **Design tokens are authoritative.** `design/tokens.json` defines colors, typography, spacing, radii. Swift code reads these as constants. Don't invent design values; if a value is missing from tokens, ask.

## v1 Build Phases

The build is decomposed into 5 phases, each ending in a checkpoint. Claude Code executes them in order, stopping after each for Nick to ratify.

- **Phase 0:** Project scaffold — XcodeGen `project.yml`, app target, Info.plist, base SwiftUI app, design tokens compiled into Swift, Diakonos launches showing an empty workspace shell. ~1-2 hours.
- **Phase 1:** Workspace shell — 2x2 pane layout with draggable dividers, pane headers, toolbar (title bar with traffic lights, workspace dropdown, status indicator, agent mode toggle, settings button, fullscreen button). No sandbox integration yet; panes show static placeholders. ~2-3 hours.
- **Phase 2:** cua integration — invoke cua to spin up sandboxes, manage sandbox lifecycle, surface status in the toolbar indicator. Single sandbox running Terminal. ~3-5 hours.
- **Phase 3:** Four panes live — Terminal, Claude Code, and Hermes Agent Chat panes wired to SwiftTerm reading from cua sandboxes. Browser pane wired to WKWebView (sandboxed Chromium output is v0.3 work; v1 uses WKWebView). ~3-5 hours.
- **Phase 4:** Preferences and polish — preferences window with General, Sandbox, Panes, Agent, Shortcuts, About sections per the design. Dark mode verified. Final visual pass against the screen designs. ~2-3 hours.

Total estimated build time: 11-18 hours of Claude Code work, across 5 checkpoints.

## What Claude Code Is Allowed To Do

- Read `CLAUDE.md`, this file, `BUILD_SPEC.md`, `docs/`, and `design/`
- Create branch `phase/0-v1-build` from main and commit there
- Build the v1 product per `BUILD_SPEC.md`, in phase order
- Write phase checkpoints to `Docs/Checkpoints/`
- Ask Nick questions whenever unclear

## What Claude Code Is Not Allowed To Do

- Modify `CLAUDE.md`, `BUILD_SPEC.md`, this file, or anything in `docs/decisions.md`
- Merge phase branch to main (Nick does this)
- Add dependencies beyond what `BUILD_SPEC.md` lists
- Skip phases or work ahead of the current phase
- Ship anything that doesn't match the design package visually

## Known Risks Going Into v1

- **cua's actual SDK surface is partially unknown to us in advance.** Phase 2 will need to read cua's docs and source to confirm integration approach. If cua's subprocess interface doesn't match our assumption, surface and we'll adjust.
- **SwiftTerm + PTY + cua subprocess output may need real engineering** to wire correctly. The exact pattern of "stream a PTY from inside a cua sandbox into a SwiftTerm view on Mac" hasn't been done before by us.
- **Browser pane in v1 uses WKWebView, not sandboxed Chromium.** This is a stopgap. cua's `cuabot chromium` produces a video stream of sandboxed Chromium; integrating that into a Swift view is v0.3 work. v1 ships with WKWebView so we have something working.

## Out-of-Scope Items Observed

(Empty at bootstrap. Claude Code adds entries here as it works.)

## Human Contact

Project owner: Nick.
