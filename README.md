# Diakonos

A native macOS dev workspace with AI panes and a sandboxed browser.

Diakonos gives you a four-pane native Mac window: two real terminals on your
real machine, Claude Code on a project folder you pick, and a sandboxed
Chromium browser streamed from a [cua](https://github.com/trycua/cua)
container. The first three are pure native; the browser is the only surface
where untrusted web content lives, so it's isolated.

Open source, MIT.

## Status

v1.1 in active development. Not yet released.

## What's in v1.1

- Single window with a 2x2 grid of resizable panes
- Top-left: native macOS terminal (`$SHELL -l` in `$HOME`)
- Top-right: Claude Code running `claude --dangerously-skip-permissions` in
  a user-pickable project folder (folder persists across launches)
- Bottom-left: second native macOS terminal
- Bottom-right: sandboxed Chromium browser (streamed from cua's Docker
  container via Xpra HTML5)
- Preferences (General · Panes · Agent · Shortcuts · About), API keys in
  Keychain, light + dark mode
- macOS 14.0+ (Sonoma)

## What's not in v1.1

- Multi-window support
- Custom pane layouts / pane reassignment (planned for v0.2)
- Onboarding (v0.2)
- Code signing, notarization, auto-update (v0.5+)
- CDP-based URL feedback in the Browser pane's address bar (v1.2)

## ⚠️ Security note

The Claude Code pane runs `claude --dangerously-skip-permissions`. **This
means Claude Code can read, modify, and delete any file on your Mac that
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
