// Preloaded (node -r) by test/fetch/jsoo/dune: replaces fetch before the
// js_of_ocaml program loads. globalThis.__next picks the answer.
globalThis.__texts = 0;
globalThis.__ua = [];
globalThis.__next = "ok";
const failing = () =>
  new ReadableStream({ start(c) { c.error(new Error("boom")); } });
const counted = (r) => {
  const text = r.text.bind(r);
  r.text = () => { globalThis.__texts += 1; return text(); };
  return r;
};
globalThis.fetch = (url, init) => {
  const headers = new Headers((init && init.headers) || {});
  globalThis.__ua.push(headers.get("api-user-agent") === null ? "no ua" : "ua");
  switch (globalThis.__next) {
    case "ok":
      return Promise.resolve(counted(new Response('{"a":1}', { status: 200 })));
    case "503":
      return Promise.resolve(counted(new Response("busy", {
        status: 503, headers: { "Retry-After": "7" } })));
    case "503 unreadable":
      return Promise.resolve(counted(new Response(failing(), { status: 503 })));
    case "200 unreadable":
      return Promise.resolve(counted(new Response(failing(), { status: 200 })));
    case "rejected":
      return Promise.reject(new TypeError("Failed to fetch"));
    case "echo":
      return new Response(init.body).text().then((t) =>
        counted(new Response(init.method + " " + t, { status: 200 })));
    case "hangs":
      return new Promise((_, reject) =>
        init.signal.addEventListener("abort", () =>
          reject(new DOMException("This operation was aborted", "AbortError"))));
  }
};
