#!/usr/bin/env node
// A paused Supabase project on demand, for the device check of 4m's « Serveur
// en pause »: the local stack never answers 540. Node 22+, no dependencies.
// Listens on 127.0.0.1:<port> and forwards to 127.0.0.1:<upstream>; put it
// between the emulator and the stack with `adb reverse tcp:54321 tcp:<port>`,
// after `scripts/emulator.sh start` (which sets the direct mapping again,
// even on a booted emulator). Restore the direct mapping with
// `adb reverse tcp:54321 tcp:54321` (or `scripts/emulator.sh start`).
//
//   node scripts/pause-proxy.mjs [--port 54399] [--upstream 54321] [--paused]
//
// While paused, every /rest/v1/* request answers 540 with an empty body
// (Supabase's paused project) and the gateway's CORS header; everything else
// (GoTrue's /auth/v1, the CORS preflights) is forwarded. POST /__pause and
// POST /__resume toggle it (204). One stdout line per request. A test tool,
// not shipped.
import { createServer, request } from "node:http";

const usage = () => {
  console.error("usage: pause-proxy.mjs [--port N] [--upstream N] [--paused]");
  process.exit(2);
};

let port = 54399;
let upstream = 54321;
let paused = false;
const args = process.argv.slice(2);
while (args.length > 0) {
  const flag = args.shift();
  switch (flag) {
    case "--paused": paused = true; break;
    case "--port": port = Number(args.shift()); break;
    case "--upstream": upstream = Number(args.shift()); break;
    default: usage();
  }
}
if (!Number.isInteger(port) || !Number.isInteger(upstream)) usage();

const line = (req, status) =>
  console.log(`${req.method} ${req.url} → ${status}${paused ? " (paused)" : ""}`);

const forward = (req, res) => {
  const out = request(
    {
      host: "127.0.0.1",
      port: upstream,
      method: req.method,
      path: req.url,
      headers: { ...req.headers, host: `127.0.0.1:${upstream}` },
    },
    (up) => {
      res.writeHead(up.statusCode ?? 502, up.headers);
      up.on("error", () => res.destroy());
      up.pipe(res);
      line(req, up.statusCode);
    },
  );
  // Once the upstream's headers went out, a reset can only cut the body.
  out.on("error", (e) => {
    if (res.headersSent) res.destroy();
    else {
      res.writeHead(502);
      res.end();
    }
    console.log(`${req.method} ${req.url} → 502 (${e.message})`);
  });
  req.on("error", () => out.destroy());
  req.pipe(out);
};

createServer((req, res) => {
  const path = req.url ?? "/";
  if (req.method === "POST" && (path === "/__pause" || path === "/__resume")) {
    paused = path === "/__pause";
    req.resume();
    res.writeHead(204);
    res.end();
    line(req, 204);
  } else if (
    paused &&
    req.method !== "OPTIONS" &&
    path.startsWith("/rest/v1/")
  ) {
    // The gateway answers the CORS preflight and puts its CORS header on
    // every answer; without them the WebView's fetch fails with a TypeError
    // (offline) and never sees the 540.
    req.resume();
    res.writeHead(540, { "access-control-allow-origin": "*" });
    res.end();
    line(req, 540);
  } else {
    forward(req, res);
  }
}).listen(port, "127.0.0.1", () => {
  console.log(
    `pause-proxy: 127.0.0.1:${port} → 127.0.0.1:${upstream}, ${paused ? "paused" : "running"}`,
  );
});
