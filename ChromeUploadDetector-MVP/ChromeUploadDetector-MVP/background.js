const ENDPOINT = "http://127.0.0.1:8765/event";

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg?.source !== "CHROME_UPLOAD_DETECTOR") return;

  const payload = {
    ...msg.payload,
    tab_id: sender.tab?.id ?? null,
    tab_url: sender.tab?.url ?? msg.payload?.page_url ?? ""
  };

  fetch(ENDPOINT, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify(payload)
  })
  .then(r => sendResponse({ok: r.ok}))
  .catch(e => sendResponse({ok: false, error: String(e)}));

  return true;
});
