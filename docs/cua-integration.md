# cua Integration Notes

This document captures what Diakonos knows about cua going into Phase 2. Claude Code should treat this as a starting point — confirm or correct it by reading cua's actual docs and source before writing integration code.

## What cua is

[cua](https://github.com/trycua/cua) is open-source infrastructure for Computer-Use Agents. MIT-licensed. 14.8k stars at time of writing.

It provides:

- **Sandbox runtime** — spin up isolated VMs/containers via Apple Virtualization Framework (Lume) on Apple Silicon, or Docker/QEMU elsewhere
- **Python SDK (`cua-sandbox`)** — programmatic control of sandboxes
- **CLI tools (`cuabot`, `cua`)** — command-line interfaces over the SDK
- **Agent framework (`cua-agent`)** — for building AI agents that operate inside sandboxes
- **Benchmarks (`cua-bench`)** — for evaluating agent performance

## What Diakonos uses

For v1, Diakonos uses **cua as a sandbox runtime via subprocess invocation**. We do NOT:

- Link cua as a Swift library (it's Python; bridging would be heavy)
- Reimplement cua's runtime in Swift (out of scope)
- Use cua's agent framework (Diakonos provides its own UI; cua-agent is a different abstraction)

Instead, Diakonos shells out to cua's CLI to manage sandbox lifecycle, and reads/writes via the sandbox's exposed interfaces (PTY for terminal panes, screen capture for browser pane in future phases).

## Integration surface we expect

Based on cua's public README and our research notes, we expect to use:

### Sandbox lifecycle via CLI

```
cuabot                          # interactive setup/onboarding
cuabot claude                   # spawn sandboxed Claude Code window
cuabot chromium                 # spawn sandboxed Chromium window
cuabot --screenshot             # capture sandbox screenshot
cuabot --type "hello"           # send keystrokes
cuabot --click <x> <y>          # send mouse clicks
```

### Or via Python SDK

```python
from cua import Sandbox, Image

async with Sandbox.ephemeral(Image.linux()) as sb:
    await sb.shell.run("echo hello")
    screenshot = await sb.screenshot()
    await sb.mouse.click(100, 200)
```

For Diakonos Phase 2, the question is **which interface to use**. Options:

**Option A: Wrap `cuabot` CLI invocations from Swift via `Process`.**
- Pros: simplest, no Python bridge needed, follows the design's "spawn a sandboxed app" pattern
- Cons: we depend on cuabot's CLI surface being stable, and we get whatever output format cuabot prints

**Option B: Spawn a long-running Python helper that uses cua-sandbox SDK and exposes a JSON-RPC or stdio protocol to Swift.**
- Pros: more control over what we get back, structured responses
- Cons: more moving parts, we maintain the helper script, harder to debug

**Option C: Skip cuabot, use cua's lower-level lume directly for sandbox creation.**
- Pros: most control
- Cons: most engineering, we're at the wrong abstraction layer for our product

**Recommended starting point: Option A.** Use `cuabot` to spawn sandboxes for our four panes. If the CLI surface proves insufficient (e.g., we can't get a PTY for our terminal pane), upgrade to Option B.

Claude Code's Phase 2 job: read cua's actual CLI options and docs, validate Option A is workable, surface any discrepancies, then implement.

## PTY integration for terminal panes

The trickiest piece. Our three terminal panes (Terminal, Claude Code, Hermes Agent Chat) all need:

1. A PTY (pseudo-terminal) running inside a cua sandbox
2. That PTY's input/output streamed to/from a SwiftTerm view on the Mac

cuabot can spawn sandboxed apps (`cuabot claude`, `cuabot chromium`) and they appear as native Mac windows via H.265 video streaming. But for our terminal panes, we don't want a Chromium-rendered terminal — we want a real PTY that SwiftTerm can drive.

**Phase 2 needs to figure out:** Can we ask cuabot for a PTY into a sandbox shell (not just a video stream of an app)? If yes, we attach SwiftTerm to that PTY. If no, we fall back to either:

- Running a shell helper inside the sandbox that exposes stdin/stdout over a socket
- Using cuabot's screen-stream output and live with the visual fidelity of a video-streamed terminal (worse for a code-focused product)

Surface this in the Phase 2 checkpoint with what you actually find.

## Browser pane in v1

The design (screen 01) shows a Browser pane displaying sandboxed Chromium. cuabot can do this via `cuabot chromium` which spawns a sandboxed Chromium window.

**For v1, we punt on full integration.** Browser pane uses a regular WKWebView pointed at whatever URL the user types. We get "browser pane works" without solving "stream cuabot's H.265 Chromium video into a SwiftUI view," which is real engineering for v0.3.

This is a deliberate compromise for v1. Document in PROJECT_STATE.md's "Known Risks" that browser-pane sandboxing is deferred.

## Installation prerequisites

For Diakonos to function, the user's machine needs:
- cua installed (`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/scripts/install.sh)"` or equivalent)
- cuabot accessible on PATH
- Whatever cua wants in `~/.cua/` (likely the standard install location)

v1 does NOT ship with cua bundled. The README tells users to install cua first. v0.5+ may include a built-in installer.

## Things we don't know yet

These are things Phase 2 needs to discover or confirm:

- Exact `cuabot` CLI surface for spinning up sandboxes programmatically (not interactively)
- How to attach to a sandbox's shell via PTY from outside the sandbox
- How to get the running sandbox's state machine (running / stopped / error)
- How to forward keystrokes from a SwiftTerm view into a sandboxed shell efficiently
- How quickly cuabot spins up a sandbox cold-start (matters for UX)
- How cuabot handles multiple concurrent sandboxes (one per pane?)
- Whether sandboxes can share filesystem with the host (for file passing) or are fully isolated

Surface findings in the Phase 2 checkpoint. We'll lock decisions based on what's actually possible.
