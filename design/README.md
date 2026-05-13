# Diakonos Design Package

This folder is the visual source of truth for Diakonos. Match it exactly.

## Files

- `tokens.json` — design tokens (colors, typography, spacing, radii, shadows). Diakonos' Swift code reads these as `DesignTokens.*` constants.
- `tokens.css` — same tokens as CSS variables (reference, not used by Swift)
- `screens/` — PNG mockups of all 9 screens
- `screens-svg/` — SVG versions of the same screens

## Screens

Each screen shows: 1440x900 light, 1440x900 dark, 1920x1080 light, 1920x1080 dark, plus component states / details. Refer to the screen for visual decisions; if the screen is silent on a detail, ask Nick.

| File | Screen | v1 scope |
|---|---|---|
| `01-main-workspace.png` | Main workspace (2x2 panes) | **v1 critical path** |
| `02-onboarding.png` | First-run onboarding (3-step flow) | v0.2 — skip in v1 |
| `03-preferences.png` | Preferences window (General/Sandbox/Panes/Agent/Shortcuts/About) | **v1 critical path** |
| `04-layout-picker.png` | Layout presets / preset manager | v0.2 — skip in v1 |
| `05-agent-control.png` | Agent control side panel | v0.3 — skip in v1 |
| `06-sandbox-status.png` | Sandbox status / health popover | v0.2 — v1 has just the toolbar indicator |
| `07-empty-pane.png` | Empty pane state | v0.2 — v1 has hardcoded pane assignments |
| `08-error-state.png` | Sandbox error state | v0.2 — v1 has basic error logging |
| `09-assets-naming.png` | App icon, state icons, pane-type icons, component states, naming candidates | **v1 uses app icon and state icons** |

## Filename note

The filenames in this folder differ from the original design package's filenames. The original package had a numbering mismatch where the file numbers didn't match the screen IDs. This folder has them corrected — file `02-onboarding.png` is actually the onboarding screen, etc.

## Naming candidates from the design

The designer suggested five name candidates: Enclave, Runbox, Vanta, Lattice, Harbor. After review, all five had prior-art issues (some are taken by major SaaS companies).

**Final name: Diakonos.** Locked in `docs/decisions.md` as D12.

## Design language anchors

The screens reference these aesthetic anchors:

- Things 3 — window chrome, polish
- Linear's Mac app — sidebar interactions, density
- Raycast — command palette, accent color use
- Cron / Notion Calendar — rounded panel design
- Cursor — editor-pane density

Anchor **away from**: Electron-y look, Material Design, Linux GTK, sharp 90-degree corners everywhere, prominent gradients.

## Component states

Screen 09 includes a component states board showing default/hover/active/disabled/focused for primary buttons, secondary buttons, segmented toggles, dropdowns, tabs, inputs, checkboxes, switches.

Screen 01 includes additional component states for toolbar elements: status indicator, agent mode toggle, settings button, fullscreen button, pane controls, draggable dividers.

When implementing components, match all states shown.

## Color usage

From `tokens.json`:
- **Background app:** `#F5F6FA` (light), `#111827` (dark)
- **Surface:** `#FFFFFF` (light), elevated panels use `#FCFCFD`
- **Accent:** `#2F6BFF` (the single accent color throughout)
- **Status healthy:** `#22C55E`, **warning:** `#F59E0B`, **error:** `#EF4444`, **stopped:** `#94A3B8`
- **Hermes orange:** `#F59E0B` for Hermes-specific theming (the Agent Chat pane uses this)
- **Text:** `#111827` primary, `#667085` secondary, `#98A2B3` muted

Use these exact values via `DesignTokens.Color.*` Swift constants. Don't pick approximate values.
