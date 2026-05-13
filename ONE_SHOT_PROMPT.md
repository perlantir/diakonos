# Diakonos v1 — One-Shot Build Prompt

This is the prompt to paste into Claude Code (`claude /goal` or equivalent) to start the v1 build. Run it from inside the `diakonos/` repo root after `git init`.

---

## Copy from here ⬇

You are Claude Code, building Diakonos v1.

Before doing anything else, follow this sequence:

### Step 1: Read everything

Read these files in full. Don't skim:

1. `CLAUDE.md` — your operating constitution. This describes how you work on this project.
2. `PROJECT_STATE.md` — the current state of the project, including locked decisions and the v1 phase breakdown.
3. `BUILD_SPEC.md` — the actual v1 scope, broken into 5 phases with deliverables and acceptance criteria for each.
4. `docs/cua-integration.md` — what we know about the cua sandbox runtime we'll integrate with, and what's still unknown.
5. `docs/decisions.md` — locked architectural decisions. Don't relitigate these.
6. `design/README.md` — design package overview, screen-to-feature mapping, color usage.
7. `design/tokens.json` — design tokens (colors, typography, spacing). These become Swift constants.
8. `design/screens/01-main-workspace.png` — visual target for the main workspace (the v1 critical-path screen).
9. `design/screens/03-preferences.png` — visual target for the preferences window (the other v1 critical-path screen).
10. `design/screens/09-assets-naming.png` — app icon, state icons, pane-type icons, component states.

Glance at the other screens in `design/screens/` for context but don't deeply study them — they're v0.2+ work.

### Step 2: Surface questions and concerns

After reading, write a response to Nick covering:

**a) Your understanding.** Two paragraphs summarizing what Diakonos v1 is, what the 5 phases will produce, and how cua integration is structured. This is to verify you've understood the spec correctly.

**b) Questions about the spec.** Anything unclear, ambiguous, or contradictory. Examples of legitimate questions:
- "BUILD_SPEC.md Phase 2 says X but docs/cua-integration.md hints at Y — which is right?"
- "The design shows N but the spec is silent on M — should I assume Q?"
- "Token X is referenced in screen 03 but missing from tokens.json — what value should I use?"

**c) Concerns about feasibility.** Anything you think might be harder or different than the spec assumes. Specifically:
- cua's actual subprocess interface and whether Option A from `docs/cua-integration.md` will work
- PTY attachment from outside a cua sandbox into a SwiftTerm view on Mac
- Any other technical risk you spot
- If you think the phase ordering should be different, say so with reasoning

**d) Proposed first phase.** A concrete, specific description of what you'll do in Phase 0 (project scaffold). File list, what each file will contain at a high level, what `xcodegen generate` will produce, what `xcodebuild build` will produce, and what Nick will see when he launches Diakonos.app for the first time.

**e) Anything else worth surfacing.** If you have suggestions, observations, or worries, share them. Don't filter to "what Nick wants to hear" — share what's true.

Then **STOP**. Don't write any code. Wait for Nick to respond.

### Step 3: Iterate on the plan

Nick will respond to your Step 2 message. He may answer questions, push back on concerns, add constraints, or ratify the plan. Respond with any further questions, then ask for confirmation to proceed.

### Step 4: Execute, phase by phase

Once ratified:

1. Create branch `phase/0-v1-build` from main
2. Execute Phase 0 (project scaffold) per BUILD_SPEC.md
3. Write checkpoint `Docs/Checkpoints/<UTC-timestamp>-phase-0-scaffold.md`
4. Push to phase branch
5. **STOP. Wait for Nick to ratify Phase 0 before starting Phase 1.**

Repeat for each phase. Don't sprint past checkpoints.

### Critical reminders

- **Don't fabricate API surfaces.** If you're unsure how cua's CLI works, read its source or docs or surface the uncertainty. Don't write code against an imagined API.
- **Match the design exactly.** Design tokens are not approximations. If you're using a color, use the exact hex from `tokens.json`. If you're laying out a screen, match the structure in the PNG.
- **Stop and ask.** Whenever in doubt — ask. Asking is cheap; surfacing late is expensive.
- **One phase at a time.** Don't work ahead. Coherence drifts when you do.

Begin with Step 1.

## Copy until here ⬆

---

## What to expect when you paste this

Claude Code will read all the files, then come back with its Step 2 response — understanding summary, questions, concerns, proposed Phase 0 description.

You'll review that response. Push back on anything wrong, answer questions, ratify the plan, or course-correct.

Once you say "proceed," Claude Code creates the phase branch and executes Phase 0. It stops, writes a checkpoint, waits.

You ratify Phase 0 (or send back fixes). Claude Code does Phase 1. Stops. Waits.

Repeat for Phases 2, 3, 4. Total real time across all 5 phases: 11-18 hours of Claude Code work, plus your ratification time between them (a few minutes each).

## Tips for a smooth run

- **Run Claude Code with `--dangerously-skip-permissions`** so it doesn't ask you to approve every file write. The constitution still applies; the flag only removes per-call permission dialogs.
- **Keep terminal output visible.** Don't background Claude Code's session; the output is your real-time view into what it's doing.
- **If Claude Code goes longer than 90 minutes without a checkpoint, interrupt and ask for a status update.** That's the sign coherence might be drifting.
- **If a phase takes more than 2x its estimate, stop and reassess.** Don't push through; that's the sign something fundamental isn't working.
- **Visual verification is your job at every checkpoint.** Don't ratify a phase without actually launching the app and looking at it.
