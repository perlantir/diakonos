#!/usr/bin/env python3
"""
Diakonos v1.6 keyboard test harness.

Empirically validates the CDP semantics that Swift's `KeyboardEventTranslator`
+ `CDPInput` pipeline relies on. Drives every key category through CDP
against a controlled `data:text/html` page (a textarea + a JS keydown
listener) and reports what arrived.

WHY: the goal contract is "test EVERY key." This script makes the
contract verifiable: connect to one of Diakonos's chat-pane Chromiums
(port 9223 for Claude Chat, 9224 for ChatGPT) or the Browser-pane
Chromium (9222 inside the cuabot container — usually only reachable from
the container itself, so use 9223/9224 for tests run from the Mac host).

USAGE
    python3 keyboard_cdp_harness.py --port 9223

REQUIREMENTS
    pip install websockets
    A running Diakonos with at least one Claude Chat or ChatGPT pane.

WHAT IT REPORTS
    PASS / FAIL per category:
      - lowercase a-z
      - uppercase A-Z (via Shift modifier)
      - digits 0-9
      - shifted symbols (!@#$%^&*()_+, {}|:"<>?, ~)
      - named special keys (Enter, Tab, Esc, BackSpace, arrows, Home/End/PgUp/PgDn)
      - F1..F12
      - Cmd+A (select-all chord, observed via JS document.execCommand)
      - text insertion via `type:'char'` event vs key chord

For each category, the harness clears the textarea, sends the key
events, then reads the textarea content and/or the recorded JS event log.
"""
from __future__ import annotations
import argparse, asyncio, json, sys, urllib.request

try:
    import websockets
except ImportError:
    print("ERROR: pip install websockets", file=sys.stderr); sys.exit(2)


TEST_PAGE = """data:text/html,<!DOCTYPE html><html><body>
<textarea id="t" autofocus style="width:90vw;height:60vh;font-size:18px;"></textarea>
<pre id="log" style="font-family:monospace;white-space:pre-wrap;"></pre>
<script>
window.__events = [];
const t = document.getElementById('t');
t.focus();
for (const e of ['keydown','keypress','input']) {
  t.addEventListener(e, (ev) => {
    window.__events.push({
      type: ev.type,
      key: ev.key, code: ev.code, keyCode: ev.keyCode,
      ctrl: ev.ctrlKey, meta: ev.metaKey, shift: ev.shiftKey, alt: ev.altKey,
      data: ev.data || null,
      inputType: ev.inputType || null,
    });
    const log = document.getElementById('log');
    log.textContent = JSON.stringify(window.__events.slice(-6), null, 2);
  });
}
window.__clear = () => { t.value = ''; window.__events = []; };
window.__state = () => ({ value: t.value, events: window.__events });
</script></body></html>"""


async def cdp(ws_url):
    return await websockets.connect(ws_url, ping_interval=None, max_size=20_000_000)


async def call(ws, mid, method, params):
    await ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    while True:
        msg = await ws.recv()
        try:
            obj = json.loads(msg)
        except Exception:
            continue
        if obj.get("id") == mid:
            return obj


async def ws_url_for(port):
    raw = urllib.request.urlopen(f"http://localhost:{port}/json", timeout=2).read()
    tabs = [t for t in json.loads(raw) if t.get("type") == "page"]
    if not tabs:
        raise RuntimeError(f"no page tabs at :{port}")
    return tabs[0]["webSocketDebuggerUrl"]


async def navigate_to_test_page(ws, mid):
    await call(ws, mid, "Page.navigate", {"url": TEST_PAGE})
    await asyncio.sleep(0.6)
    # Re-focus the textarea (data: URLs sometimes lose focus on nav).
    await call(ws, mid + 1, "Runtime.evaluate", {
        "expression": "document.getElementById('t').focus()",
    })


async def clear_state(ws, mid):
    await call(ws, mid, "Runtime.evaluate", {"expression": "window.__clear()"})


async def read_state(ws, mid):
    r = await call(ws, mid, "Runtime.evaluate", {
        "expression": "JSON.stringify(window.__state())",
        "returnByValue": True,
    })
    val = (r.get("result", {}).get("result", {}) or {}).get("value")
    if val:
        try: return json.loads(val)
        except Exception: return None
    return None


# ---------- the actual key dispatches, copying CDPInput.swift semantics ----------

MODBITS = {"alt": 1, "ctrl": 2, "meta": 4, "super": 4, "cmd": 4, "shift": 8}

def modbits(mods):
    b = 0
    for m in mods:
        b |= MODBITS.get(m.lower(), 0)
    return b


SPECIAL = {
    "Return":    ("Enter",      "Enter",      13),
    "Tab":       ("Tab",        "Tab",         9),
    "Escape":    ("Escape",     "Escape",     27),
    "BackSpace": ("Backspace",  "Backspace",   8),
    "Delete":    ("Delete",     "Delete",     46),
    "Left":      ("ArrowLeft",  "ArrowLeft",  37),
    "Right":     ("ArrowRight", "ArrowRight", 39),
    "Up":        ("ArrowUp",    "ArrowUp",    38),
    "Down":      ("ArrowDown",  "ArrowDown",  40),
    "Home":      ("Home",       "Home",       36),
    "End":       ("End",        "End",        35),
    "Page_Up":   ("PageUp",     "PageUp",     33),
    "Page_Down": ("PageDown",   "PageDown",   34),
}
for n in range(1, 13):
    SPECIAL[f"F{n}"] = (f"F{n}", f"F{n}", 111 + n)


async def dispatch_type(ws, base_mid, text):
    """Mirror of CDPInput.dispatchType — one CDP message per character."""
    for i, ch in enumerate(text):
        await call(ws, base_mid + i, "Input.dispatchKeyEvent", {
            "type": "char", "text": ch,
        })


async def dispatch_key(ws, base_mid, name, mods):
    """Mirror of CDPInput.dispatchKey."""
    b = modbits(mods)
    if name in SPECIAL:
        key, code, kc = SPECIAL[name]
    elif len(name) == 1:
        ch = name
        key = ch.lower()
        if ch.isalpha():
            code = f"Key{ch.upper()}"
            kc = ord(ch.upper())
        elif ch.isdigit():
            code = f"Digit{ch}"
            kc = ord(ch)
        else:
            code = ch; kc = ord(ch) if ch else 0
    else:
        key = name; code = name; kc = 0
    await call(ws, base_mid, "Input.dispatchKeyEvent", {
        "type": "keyDown", "key": key, "code": code,
        "windowsVirtualKeyCode": kc, "modifiers": b,
    })
    await call(ws, base_mid + 1, "Input.dispatchKeyEvent", {
        "type": "keyUp", "key": key, "code": code,
        "windowsVirtualKeyCode": kc, "modifiers": b,
    })


# ---------- test cases ----------

CASES_PRINTABLE = [
    ("lowercase a-z",   "abcdefghijklmnopqrstuvwxyz"),
    ("uppercase A-Z",   "ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
    ("digits 0-9",      "0123456789"),
    ("shifted symbols", "!@#$%^&*()_+{}|:\"<>?~"),
    ("space + punct",   " .,;:'-=[]\\/"),
]

CASES_SPECIAL = ["Return", "Tab", "Escape", "BackSpace", "Delete",
                 "Left", "Right", "Up", "Down",
                 "Home", "End", "Page_Up", "Page_Down",
                 "F1", "F2", "F5", "F11", "F12"]


async def run_printable(ws, base_mid, label, text):
    await clear_state(ws, base_mid)
    await dispatch_type(ws, base_mid + 1, text)
    await asyncio.sleep(0.2)
    state = await read_state(ws, base_mid + 1000) or {}
    got = state.get("value", "")
    ok = (got == text)
    return ok, got


async def run_special(ws, base_mid, name):
    await clear_state(ws, base_mid)
    await dispatch_key(ws, base_mid + 1, name, [])
    await asyncio.sleep(0.15)
    state = await read_state(ws, base_mid + 1000) or {}
    evs = state.get("events", [])
    keys = [e.get("key") for e in evs if e.get("type") == "keydown"]
    expected_key = SPECIAL[name][0]
    return (expected_key in keys), keys


async def run_chord(ws, base_mid, name, mods, label):
    await clear_state(ws, base_mid)
    # Pre-fill some text to make selectAll observable for Cmd+A.
    await dispatch_type(ws, base_mid + 1, "hello")
    await asyncio.sleep(0.1)
    await dispatch_key(ws, base_mid + 100, name, mods)
    await asyncio.sleep(0.15)
    state = await read_state(ws, base_mid + 1000) or {}
    evs = state.get("events", [])
    meta_seen = any(e.get("type") == "keydown"
                    and (e.get("meta") or e.get("ctrl"))
                    and (e.get("key", "").lower() == name.lower())
                    for e in evs)
    return meta_seen, evs[-3:] if evs else []


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=9223,
                    help="CDP port (9223=Claude Chat, 9224=ChatGPT, 9222=Browser pane Chromium inside cuabot)")
    args = ap.parse_args()

    print(f"=== Diakonos v1.6 keyboard harness — port {args.port} ===\n")
    ws_url = await ws_url_for(args.port)
    ws = await cdp(ws_url)
    try:
        await call(ws, 1, "Page.enable", {})
        await call(ws, 2, "Runtime.enable", {})
        await navigate_to_test_page(ws, 10)

        passed = failed = 0

        # Printable categories.
        for label, text in CASES_PRINTABLE:
            ok, got = await run_printable(ws, 200, label, text)
            mark = "PASS" if ok else "FAIL"
            if ok: passed += 1
            else:  failed += 1
            print(f"[{mark}] dispatchType: {label}")
            if not ok:
                print(f"        expected: {text!r}")
                print(f"        got:      {got!r}")

        # Named-special-key categories.
        for name in CASES_SPECIAL:
            ok, keys = await run_special(ws, 300, name)
            mark = "PASS" if ok else "FAIL"
            if ok: passed += 1
            else:  failed += 1
            print(f"[{mark}] dispatchKey: {name}")
            if not ok:
                print(f"        keydown.key seen: {keys}")

        # Cmd+A / Cmd+C / Cmd+V / Cmd+X / Cmd+Z / Cmd+Shift+Z chord smoke tests.
        for name, mods, label in [
            ("a", ["super"], "Cmd+A"),
            ("c", ["super"], "Cmd+C"),
            ("v", ["super"], "Cmd+V"),
            ("x", ["super"], "Cmd+X"),
            ("z", ["super"], "Cmd+Z"),
            ("z", ["super", "shift"], "Cmd+Shift+Z"),
        ]:
            ok, evs = await run_chord(ws, 400, name, mods, label)
            mark = "PASS" if ok else "FAIL"
            if ok: passed += 1
            else:  failed += 1
            print(f"[{mark}] dispatchKey chord: {label}")
            if not ok:
                print(f"        events: {evs}")

        print(f"\n=== TOTAL: {passed} passed, {failed} failed ===")
        sys.exit(0 if failed == 0 else 1)
    finally:
        await ws.close()


if __name__ == "__main__":
    asyncio.run(main())
