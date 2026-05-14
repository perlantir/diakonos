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
    /// `data-testid="user-message"` (current as of 2026-05-13). The latest
    /// is the last one in DOM order. Returns its textContent.
    static let readLatestUserMessageClaude: String = """
    (() => {
      const nodes = document.querySelectorAll('[data-testid="user-message"]');
      if (!nodes || nodes.length === 0) return null;
      const last = nodes[nodes.length - 1];
      return (last.innerText || last.textContent || '').trim();
    })()
    """

    /// chatgpt.com: user messages live in elements with
    /// `data-message-author-role="user"` (current as of 2026-05-13).
    static let readLatestUserMessageChatGPT: String = """
    (() => {
      const nodes = document.querySelectorAll('[data-message-author-role="user"]');
      if (!nodes || nodes.length === 0) return null;
      const last = nodes[nodes.length - 1];
      return (last.innerText || last.textContent || '').trim();
    })()
    """

    // MARK: - Setting the textarea (NO auto-submit, per spec §b.1)

    /// claude.ai: input is a contenteditable div with
    /// `data-testid="chat-input"`. React-controlled, so we use
    /// `document.execCommand('insertText', ...)` for compatibility with
    /// React's onChange.
    static func setTextareaClaude(_ text: String) -> String {
        let js = jsString(text)
        return """
        (() => {
          const el = document.querySelector('[data-testid="chat-input"] [contenteditable="true"]')
            || document.querySelector('[contenteditable="true"][role="textbox"]');
          if (!el) return 'NO_INPUT';
          el.focus();
          document.execCommand('selectAll', false, null);
          document.execCommand('insertText', false, \(js));
          el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: \(js) }));
          return 'OK';
        })()
        """
    }

    /// chatgpt.com: textarea has id `prompt-textarea`. React-controlled.
    static func setTextareaChatGPT(_ text: String) -> String {
        let js = jsString(text)
        return """
        (() => {
          const el = document.getElementById('prompt-textarea')
            || document.querySelector('textarea[name="prompt"]')
            || document.querySelector('div[contenteditable="true"]');
          if (!el) return 'NO_INPUT';
          el.focus();
          // For native <textarea>, use the native setter so React picks up the change.
          if (el.tagName === 'TEXTAREA') {
            const setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
            setter.call(el, \(js));
            el.dispatchEvent(new Event('input', { bubbles: true }));
          } else {
            document.execCommand('selectAll', false, null);
            document.execCommand('insertText', false, \(js));
            el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: \(js) }));
          }
          return 'OK';
        })()
        """
    }

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
