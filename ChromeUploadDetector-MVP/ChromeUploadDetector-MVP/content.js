(() => {
  const seen = new WeakSet();

  function send(payload) {
    try {
      if (!chrome?.runtime?.id) return;

      chrome.runtime.sendMessage({
        source: "CHROME_UPLOAD_DETECTOR",
        payload
      }).catch(() => {
        // Extension context may have been invalidated after reload.
      });
    } catch {
      // Ignore invalidated extension contexts.
    }
  }

  function emit(type, file, input = null, extra = {}) {
    if (!file) return;

    send({
      type,
      filename: file.name || "",
      size: Number(file.size || 0),
      mime: file.type || "",
      page_url: location.href,
      page_title: document.title,
      input_name: input?.name || "",
      input_id: input?.id || "",
      timestamp: new Date().toISOString(),
      ...extra
    });
  }

  function emitPaste(type, extra = {}) {
    send({
      type,
      page_url: location.href,
      page_title: document.title,
      input_name: document.activeElement?.name || "",
      input_id: document.activeElement?.id || "",
      input_type: document.activeElement?.getAttribute?.("type") || "",
      timestamp: new Date().toISOString(),
      ...extra
    });
  }

  // ---------------------------------------------------------
  // Normal <input type="file"> detection
  // ---------------------------------------------------------

  function hook(input) {
    if (
      !(input instanceof HTMLInputElement) ||
      input.type !== "file" ||
      seen.has(input)
    ) {
      return;
    }

    seen.add(input);

    input.addEventListener("change", () => {
      for (const file of Array.from(input.files || [])) {
        emit("file_selected", file, input);
      }
    }, true);
  }

  function scan(root = document) {
    try {
      root.querySelectorAll?.('input[type="file"]').forEach(hook);
    } catch {}
  }

  scan();

  new MutationObserver(mutations => {
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        if (node.nodeType !== Node.ELEMENT_NODE) continue;

        if (node.matches?.('input[type="file"]')) {
          hook(node);
        }

        scan(node);
      }
    }
  }).observe(document.documentElement || document, {
    childList: true,
    subtree: true
  });

  // ---------------------------------------------------------
  // Clipboard paste detection
  // IMPORTANT: only metadata is logged. Clipboard content is
  // never sent to the local receiver.
  // ---------------------------------------------------------

  document.addEventListener("paste", event => {
    try {
      const clipboard = event.clipboardData;
      if (!clipboard) return;

      const types = Array.from(clipboard.types || []);
      const items = Array.from(clipboard.items || []);

      const hasImage = items.some(item => item.kind === "file" &&
        typeof item.type === "string" &&
        item.type.startsWith("image/"));

      const hasFile = items.some(item => item.kind === "file");

      const hasText = types.includes("text/plain") ||
                      items.some(item => item.kind === "string");

      let pasteType = "other";
      if (hasImage) {
        pasteType = "image";
      } else if (hasFile) {
        pasteType = "file";
      } else if (hasText) {
        pasteType = "text";
      }

      // For text, calculate size without sending the text itself.
      let textSize = 0;
      if (hasText) {
        try {
          const textItem = items.find(item =>
            item.kind === "string" && item.type === "text/plain"
          );

          if (textItem) {
            textItem.getAsString(text => {
              emitPaste("chrome_paste", {
                source: "clipboard",
                paste_type: pasteType,
                clipboard_types: types,
                text_size: new Blob([text || ""]).size
              });
            });
            return;
          }
        } catch {
          // Fall through to metadata-only event.
        }
      }

      emitPaste("chrome_paste", {
        source: "clipboard",
        paste_type: pasteType,
        clipboard_types: types,
        item_count: items.length,
        text_size: textSize
      });
    } catch {
      // Never interfere with normal browser paste behavior.
    }
  }, true);

  // ---------------------------------------------------------
  // Drag & Drop detection
  // ---------------------------------------------------------

  document.addEventListener("drop", event => {
    try {
      const files = event.dataTransfer?.files;

      if (!files || files.length === 0) return;

      for (const file of Array.from(files)) {
        emit("file_dropped", file, null, {
          drop_x: event.clientX,
          drop_y: event.clientY
        });
      }
    } catch {}
  }, true);

  // ---------------------------------------------------------
  // Form submission detection
  // ---------------------------------------------------------

  document.addEventListener("submit", event => {
    const form = event.target;

    if (!(form instanceof HTMLFormElement)) return;

    form.querySelectorAll('input[type="file"]').forEach(input => {
      for (const file of Array.from(input.files || [])) {
        emit("upload_submit", file, input);
      }
    });
  }, true);
})();
