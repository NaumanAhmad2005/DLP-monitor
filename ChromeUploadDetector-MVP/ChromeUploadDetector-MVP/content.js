(() => {
  const seen = new WeakSet();

  function send(payload) {
    try {
      chrome.runtime.sendMessage({
        source: "CHROME_UPLOAD_DETECTOR",
        payload
      });
    } catch {}
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

  // Detect file inputs added dynamically
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
  // Drag & Drop detection
  // ---------------------------------------------------------

  document.addEventListener("drop", event => {
    try {
      const files = event.dataTransfer?.files;

      if (!files || files.length === 0) {
        return;
      }

      for (const file of Array.from(files)) {
        emit(
          "file_dropped",
          file,
          null,
          {
            drop_x: event.clientX,
            drop_y: event.clientY
          }
        );
      }

    } catch {}
  }, true);


  // ---------------------------------------------------------
  // Form submission detection
  // ---------------------------------------------------------

  document.addEventListener("submit", event => {
    const form = event.target;

    if (!(form instanceof HTMLFormElement)) {
      return;
    }

    form.querySelectorAll('input[type="file"]').forEach(input => {
      for (const file of Array.from(input.files || [])) {
        emit("upload_submit", file, input);
      }
    });

  }, true);

})();