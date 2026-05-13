# Diakonos

A sandboxed AI agent workspace for macOS.

Diakonos gives you a four-pane native Mac window where AI agents (Claude Code, Hermes, browser automation, terminal commands) run inside isolated sandboxes — they can do real work without touching your real machine.

Built on [cua](https://github.com/trycua/cua) for the sandbox runtime. Open source, MIT.

## Status

v1 in active development. Not yet released.

## What's in v1

- Single window with 2x2 resizable panes
- Each pane runs an application inside a cua sandbox
- Default panes: Terminal, Claude Code, Hermes agent chat, Browser
- Sandbox lifecycle management (start, stop, restart, reset)
- Basic preferences (API keys, sandbox config)
- Light + dark mode
- macOS 14.0+ (Sonoma)

## What's not in v1

- Onboarding flow (planned for v0.2)
- Layout presets / preset manager (v0.2)
- Agent control panel (v0.3)
- Empty pane and error state UI (v0.2)
- Code signing, notarization, auto-update (v0.5+)

## Building from source

Requires:
- macOS 14.0+ (Sonoma or later)
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [cua](https://github.com/trycua/cua) installed and running

To build:
```
git clone https://github.com/perlantir/diakonos.git
cd diakonos
xcodegen generate
open Diakonos.xcodeproj
```

## License

MIT. See LICENSE.

## Credits

Diakonos is built by [Nick / perlantir](https://github.com/perlantir).

Powered by [cua](https://github.com/trycua/cua), [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), and Apple's WebKit.
