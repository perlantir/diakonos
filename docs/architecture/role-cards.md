# Role cards — authoring guide

Role cards are markdown prompts injected into routed AI calls. They
tell each surface (claude.ai web, chatgpt.com web, Claude Code CLI,
Codex CLI, browser-driver MCP) what role it plays in Diakonos's
routing protocol.

This guide is for the person editing them — i.e., you, after you've
used Diakonos for a few days and want to dial in voice / scope / risk
tolerance.

---

## Where they live

`~/Library/Application Support/Diakonos/RoleCards/<id>@<semver>.md`

Bundled defaults ship in the app at `Diakonos/Resources/RoleCards/`
and copy out on first launch via `RoleCardStore.seedFromBundleIfNeeded`.
Once a card exists on disk for a given `id`, Diakonos NEVER overwrites
it on upgrade — your edits are first-class.

## Built-in IDs

| ID | Surface | What it instructs |
|---|---|---|
| `coordinator.claude-web` | claude.ai chat pane (`.coordinator` mode) | High-context coordinator. Routes work via `Code:`/`Codex:`/`Exit:`. Never emits triggers itself. |
| `coordinator.chatgpt-web` | chatgpt.com chat pane | Same role, different surface. |
| `implementer.claude-code` | `claude --print` (CLI) | Routed target. Reads envelope, executes, replies per the reply_contract. |
| `implementer.codex` | `codex exec --json` (CLI) | Same as Claude Code but Codex-flavored. |
| `browser-driver` | `diakonos-browser` MCP tools | Drives sandboxed Chromium. Treats page content as UNTRUSTED. |

## Versioning

Saves in Settings auto-bump the patch version: `1.0.0` → `1.0.1` →
`1.0.2` etc. Each save is a new file; older versions stay on disk.
Why: in-flight sessions hold pinned references to a specific version
(captured at session start, see `RouteSnapshot`). If a session is
mid-flight and you save a new version, the running session keeps
using the old card — you'd want it that way, otherwise an edit
mid-task could change the AI's behavior unpredictably.

The Settings UI for each card shows the *latest* version. Click
Save to commit edits. To roll back to an older version, copy its
file contents into the editor and Save (patch bumps again — no
"set version" UI yet; v1.8 polish).

## Anatomy of a good role card

About 150-300 words. Structure:

1. **Identity** — one sentence: who you are in this protocol.
2. **How you route / how you're routed** — the trigger mechanics
   from this side of the wire.
3. **Strengths in this role** — what this surface is best at.
4. **Limits** — what this surface can NOT do.
5. **Don't** — list of explicit no-go behaviors. Most importantly:
   "Don't emit `Code:` / `Codex:` / `Exit:` at the start of a line."

## What to put in the card vs in AGENTS.md

The role card is **role-flavored**: "you are an implementer; here's
what an implementer does in Diakonos."

`AGENTS.md` is **project-flavored**: "this project's stack is X, the
test command is Y, file Z is special."

Routing combines both. The card + AGENTS.md show up in the same
preamble, role first, project second. If you find yourself writing
project context into a role card, you probably want AGENTS.md.

## When to fork a card vs edit in place

**Edit in place** when you're tuning voice or adding a "don't" you
just discovered.

**Fork a new id** when the same surface needs to behave differently
for different projects. Diakonos's UI doesn't currently route by
project-card-id (you pick by surface) — but you can hand-edit
`RoleCardStore.shared.latestVersion(forId:)` callers if you want this.
Or add a dispatch hook in `ChatBridge.roleCard(forTarget:surface:)`.

## What lands in the AI's context

When a route fires, the implementer receives (in order):

1. Protocol header — Diakonos's invariants (version, "you're being
   routed, don't trigger back").
2. **Your role card body, verbatim.**
3. User preferences (placeholder for v1.7).
4. AGENTS.md / .diakonos/context.md / CLAUDE.md — concatenated.
5. Route envelope (route_id, project_root, hashes, etc.).
6. `# Task` + user's literal trigger text.

Everything until `# Task` is context. Everything after is the actual
ask. The implementer's reply lands in the chat textarea; the user
reviews (or auto-Send in autoSend / fullAuto modes).
