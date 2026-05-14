import Foundation

/// JavaScript snippets injected into chat-pane Chromium via CDP
/// `Runtime.evaluate`. Two kinds: reading the latest user message, and
/// setting the textarea value (no auto-submit — user reviews + presses Send).
///
/// **DOM coupling warning:** selectors here mirror claude.ai and
/// chatgpt.com's current HTML structure. They WILL change. If the chat panes
/// stop routing user messages and Diagnostics shows `selectorMissing` events,
/// these strings are the fix point.
enum ChatPostbackJS {

    // MARK: - Reading the latest user message

    /// claude.ai: user messages live in elements with
    /// `data-testid="user-message"`. Empirically verified 2026-05-14
    /// (synthetic DOM probe) that this selector ONLY matches user-authored
    /// nodes; assistant emissions of "Code:" do NOT register.
    ///
    /// Returns a `id|||text` shape so the caller can dedupe on stable
    /// per-message IDs instead of text hashing. claude.ai exposes
    /// `data-message-id` on the same element; if it's missing we fall
    /// back to text hash.
    static let readLatestUserMessageClaude: String = """
    (() => {
      const nodes = document.querySelectorAll('[data-testid="user-message"]');
      if (!nodes || nodes.length === 0) return null;
      const last = nodes[nodes.length - 1];
      const text = (last.innerText || last.textContent || '').trim();
      const mid = last.getAttribute('data-message-id') ||
                  last.getAttribute('data-message-uuid') ||
                  ('hash:' + text.length + ':' + text.slice(0, 32));
      return mid + '|||' + text;
    })()
    """

    /// chatgpt.com: user messages live in elements with
    /// `data-message-author-role="user"`. Empirically verified
    /// 2026-05-14 that this selector ONLY matches user-authored nodes.
    /// `data-message-id` on the same element gives a stable dedupe key.
    static let readLatestUserMessageChatGPT: String = """
    (() => {
      const nodes = document.querySelectorAll('[data-message-author-role="user"]');
      if (!nodes || nodes.length === 0) return null;
      const last = nodes[nodes.length - 1];
      const text = (last.innerText || last.textContent || '').trim();
      const mid = last.getAttribute('data-message-id') ||
                  ('hash:' + text.length + ':' + text.slice(0, 32));
      return mid + '|||' + text;
    })()
    """

    // MARK: - Setting the textarea (NO auto-submit, per spec §b.1)

    /// claude.ai: input is a contenteditable div with
    /// `data-testid="chat-input"`. React-controlled, so we use
    /// `document.execCommand('insertText', ...)` for compatibility with
    /// React's onChange.
    ///
    /// v1.7 Part B: if the user has typed something into the textarea
    /// since the last post, we DO NOT silently overwrite it. We stash
    /// the response in `window.__diakonosPending` and inject a banner
    /// above the composer offering Accept/Dismiss buttons. Accept
    /// replaces; Dismiss leaves the user's text alone.
    static func setTextareaClaude(_ text: String) -> String {
        let js = jsString(text)
        return """
        (() => {
          \(bannerInjector(forSurface: "claude"))
          const el = document.querySelector('[data-testid="chat-input"] [contenteditable="true"]')
            || document.querySelector('[contenteditable="true"][role="textbox"]');
          if (!el) return 'NO_INPUT';
          const current = (el.innerText || el.textContent || '').trim();
          const writer = () => {
            el.focus();
            document.execCommand('selectAll', false, null);
            document.execCommand('insertText', false, \(js));
            el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: \(js) }));
          };
          window.__diakonosPending = \(js);
          window.__diakonosWrite = writer;
          if (current.length > 0) {
            __diakonosShowBanner('Diakonos has a routed response ready. Your draft is preserved.', false);
            return 'BANNER_USER_TEXT';
          } else {
            writer();
            __diakonosShowBanner('Diakonos posted a routed response.', true);
            return 'OK';
          }
        })()
        """
    }

    /// chatgpt.com: textarea has id `prompt-textarea`. React-controlled.
    static func setTextareaChatGPT(_ text: String) -> String {
        let js = jsString(text)
        return """
        (() => {
          \(bannerInjector(forSurface: "chatgpt"))
          const el = document.getElementById('prompt-textarea')
            || document.querySelector('textarea[name="prompt"]')
            || document.querySelector('div[contenteditable="true"]');
          if (!el) return 'NO_INPUT';
          const current = (el.tagName === 'TEXTAREA' ? (el.value || '') :
                           (el.innerText || el.textContent || '')).trim();
          const writer = () => {
            el.focus();
            if (el.tagName === 'TEXTAREA') {
              const setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
              setter.call(el, \(js));
              el.dispatchEvent(new Event('input', { bubbles: true }));
            } else {
              document.execCommand('selectAll', false, null);
              document.execCommand('insertText', false, \(js));
              el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: \(js) }));
            }
          };
          window.__diakonosPending = \(js);
          window.__diakonosWrite = writer;
          if (current.length > 0) {
            __diakonosShowBanner('Diakonos has a routed response ready. Your draft is preserved.', false);
            return 'BANNER_USER_TEXT';
          } else {
            writer();
            __diakonosShowBanner('Diakonos posted a routed response.', true);
            return 'OK';
          }
        })()
        """
    }

    /// Inline JS function `__diakonosShowBanner(message, autoApplied)` —
    /// injects a sticky banner above the chat composer. `autoApplied`
    /// = true means the textarea was empty, response was inserted, the
    /// banner just announces it (and auto-fades after 4s). false means
    /// the user had typed; banner shows Accept/Dismiss buttons.
    private static func bannerInjector(forSurface: String) -> String {
        return """
        if (typeof window.__diakonosShowBanner !== 'function') {
          window.__diakonosShowBanner = function(message, autoApplied) {
            const old = document.getElementById('__diakonos_banner');
            if (old) old.remove();
            const banner = document.createElement('div');
            banner.id = '__diakonos_banner';
            banner.style.cssText = 'position:fixed;left:50%;bottom:140px;transform:translateX(-50%);' +
              'background:#1f2937;color:#fff;padding:8px 14px;border-radius:8px;' +
              'box-shadow:0 4px 12px rgba(0,0,0,0.25);font:13px -apple-system,system-ui;' +
              'z-index:99999;display:flex;gap:10px;align-items:center;';
            const text = document.createElement('span');
            text.textContent = '⤴ ' + message;
            banner.appendChild(text);
            if (!autoApplied) {
              const accept = document.createElement('button');
              accept.textContent = 'Accept';
              accept.style.cssText = 'background:#10b981;color:#fff;border:0;padding:4px 10px;border-radius:6px;font-weight:600;cursor:pointer;';
              accept.onclick = function() { (window.__diakonosWrite || function(){})(); banner.remove(); };
              banner.appendChild(accept);
              const dismiss = document.createElement('button');
              dismiss.textContent = 'Dismiss';
              dismiss.style.cssText = 'background:#374151;color:#fff;border:0;padding:4px 10px;border-radius:6px;font-weight:600;cursor:pointer;';
              dismiss.onclick = function() { banner.remove(); };
              banner.appendChild(dismiss);
            } else {
              setTimeout(function(){ if (banner.parentNode) banner.remove(); }, 4000);
            }
            document.body.appendChild(banner);
          };
        }
        """
    }

    // MARK: - Send button click (v1.7 Part B: auto-send / Full Auto)

    /// claude.ai Send-button click. Selector + heuristic: find the
    /// button that's next to the chat-input contenteditable. As of
    /// 2026-05-13 the button is `button[aria-label="Send Message"]`.
    /// Returns 'OK' / 'NO_BUTTON' / 'DISABLED'.
    static let clickSendClaude: String = """
    (() => {
      const candidates = [
        'button[aria-label="Send Message"]',
        'button[aria-label="Send message"]',
        'button[data-testid="send-button"]',
        '[contenteditable="true"] ~ button',
      ];
      let btn = null;
      for (const sel of candidates) {
        const found = document.querySelector(sel);
        if (found) { btn = found; break; }
      }
      if (!btn) return 'NO_BUTTON';
      if (btn.disabled) return 'DISABLED';
      btn.click();
      return 'OK';
    })()
    """

    /// chatgpt.com Send-button click. Selector: composer button[data-testid="send-button"]
    /// or aria-label="Send prompt".
    static let clickSendChatGPT: String = """
    (() => {
      const candidates = [
        'button[data-testid="send-button"]',
        'button[aria-label="Send prompt"]',
        'button[aria-label="Send message"]',
      ];
      let btn = null;
      for (const sel of candidates) {
        const found = document.querySelector(sel);
        if (found) { btn = found; break; }
      }
      if (!btn) return 'NO_BUTTON';
      if (btn.disabled) return 'DISABLED';
      btn.click();
      return 'OK';
    })()
    """

    // MARK: - Assistant-message scrape (Full Auto only)

    /// claude.ai: assistant messages live under `[data-testid="assistant-
    /// message"]` (heuristic). Returns id|||text of the latest, or 'null'.
    /// Used ONLY by `.fullAuto` postback mode — the autonomous loop opt-in.
    static let readLatestAssistantMessageClaude: String = """
    (() => {
      const sels = ['[data-testid="assistant-message"]',
                    '[data-message-author-role="assistant"]'];
      let nodes = [];
      for (const s of sels) {
        nodes = document.querySelectorAll(s);
        if (nodes.length) break;
      }
      if (!nodes.length) return null;
      const last = nodes[nodes.length - 1];
      const text = (last.innerText || last.textContent || '').trim();
      const mid = last.getAttribute('data-message-id') ||
                  last.getAttribute('data-message-uuid') ||
                  ('hash:' + text.length + ':' + text.slice(0, 32));
      return mid + '|||' + text;
    })()
    """

    /// chatgpt.com: assistant messages match `[data-message-author-role="assistant"]`.
    static let readLatestAssistantMessageChatGPT: String = """
    (() => {
      const nodes = document.querySelectorAll('[data-message-author-role="assistant"]');
      if (!nodes.length) return null;
      const last = nodes[nodes.length - 1];
      const text = (last.innerText || last.textContent || '').trim();
      const mid = last.getAttribute('data-message-id') ||
                  ('hash:' + text.length + ':' + text.slice(0, 32));
      return mid + '|||' + text;
    })()
    """

    // MARK: - Helpers

    private static func jsString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}
