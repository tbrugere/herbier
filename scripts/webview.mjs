#!/usr/bin/env node
// Minimal Chrome DevTools Protocol client for the app's WebView (or any
// page target), reached through `scripts/emulator.sh forward`. Node 22+, no
// dependencies (global fetch and WebSocket).
//
//   node scripts/webview.mjs [--port 9222] <command>
//
//   targets                       list the debuggable targets (JSON)
//   eval <js>                     evaluate an expression in the page (promises awaited), print the value
//   text                          print document.body.innerText
//   screenshot <file.png>         save a PNG of the viewport
//   heap                          force a full GC, then print the JS heap in use (bytes)
//   wait-for <js> [timeout-ms]    poll until the expression is truthy (default 30000)
//   wait-stable [quiet-ms] [timeout-ms]
//                                 wait until the page text has not changed for quiet-ms (default
//                                 2000; timeout 60000), then print it
//   drag <x,y[,ms]>...            one touch gesture in CSS px: press at the first point, move
//                                 through the others, lift at the last; ms is the pause after
//                                 reaching that point (default 16), so a rest before lifting is
//                                 `x,y,200` last
import { existsSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";

const usage = () => {
  console.error("usage: webview.mjs [--port N] targets | eval <js> | text | screenshot <file> | heap | wait-for <js> [ms] | wait-stable [quiet-ms] [ms] | drag <x,y[,ms]>...");
  process.exit(2);
};

let args = process.argv.slice(2);
let port = Number(process.env.HERBIER_DEVTOOLS_PORT || 9222);
if (args[0] === "--port") {
  port = Number(args[1]);
  args = args.slice(2);
}
const [command, ...rest] = args;
if (!command) usage();

// Driving the WebView is activity on the device lock (see emulator.sh): its
// last file is refreshed now and on exit, so a long wait counts too.
const lockDir = process.env.HERBIER_LOCK_DIR || `${homedir()}/.cache/herbier/emulator.lock`;
const touchLock = () => {
  if (!existsSync(lockDir)) return;
  try {
    const tmp = `${lockDir}/last.${process.pid}`;
    writeFileSync(tmp, `${Math.floor(Date.now() / 1000)}\n`);
    renameSync(tmp, `${lockDir}/last`);
  } catch {}
};
touchLock();
process.on("exit", touchLock);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function targets() {
  const res = await fetch(`http://127.0.0.1:${port}/json`);
  if (!res.ok) throw new Error(`devtools /json: HTTP ${res.status}`);
  return res.json();
}

async function connect() {
  const page = (await targets()).find((t) => t.type === "page" && t.webSocketDebuggerUrl);
  if (!page) throw new Error(`no page target on port ${port}`);
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((ok, ko) => {
    ws.onopen = ok;
    ws.onerror = () => ko(new Error(`cannot connect to ${page.webSocketDebuggerUrl}`));
  });
  let next = 0;
  const pending = new Map();
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    const p = pending.get(msg.id);
    if (!p) return;
    pending.delete(msg.id);
    msg.error ? p.ko(new Error(`${msg.error.message} (${msg.error.code})`)) : p.ok(msg.result);
  };
  const send = (method, params = {}) =>
    new Promise((ok, ko) => {
      const id = ++next;
      pending.set(id, { ok, ko });
      ws.send(JSON.stringify({ id, method, params }));
    });
  return { send, close: () => ws.close() };
}

async function evaluate(cdp, expression) {
  const { result, exceptionDetails } = await cdp.send("Runtime.evaluate", {
    expression,
    awaitPromise: true,
    returnByValue: true,
  });
  if (exceptionDetails) {
    const what = exceptionDetails.exception?.description || exceptionDetails.text;
    throw new Error(`page exception: ${what}`);
  }
  return result.value;
}

const print = (v) => console.log(typeof v === "string" ? v : JSON.stringify(v, null, 2));
const pageText = "document.body ? document.body.innerText : ''";

async function main() {
  if (command === "targets") return print(await targets());
  const cdp = await connect();
  try {
    switch (command) {
      case "eval":
        if (!rest[0]) usage();
        return print(await evaluate(cdp, rest[0]));
      case "text":
        return print(await evaluate(cdp, pageText));
      case "screenshot": {
        if (!rest[0]) usage();
        const { data } = await cdp.send("Page.captureScreenshot", { format: "png" });
        writeFileSync(rest[0], Buffer.from(data, "base64"));
        return console.log(rest[0]);
      }
      case "heap": {
        // performance.memory is bucketed and cached outside a site-locked
        // renderer (the WebView); the protocol's reading is exact.
        await cdp.send("HeapProfiler.collectGarbage");
        const { usedSize } = await cdp.send("Runtime.getHeapUsage");
        return console.log(usedSize);
      }
      case "wait-for": {
        if (!rest[0]) usage();
        const deadline = Date.now() + Number(rest[1] || 30000);
        for (;;) {
          let ok = false;
          try {
            ok = await evaluate(cdp, `!!(${rest[0]})`);
          } catch {
            // the page may be reloading
          }
          if (ok) return console.log("ok");
          if (Date.now() > deadline) throw new Error(`timed out waiting for ${rest[0]}`);
          await sleep(250);
        }
      }
      case "wait-stable": {
        const quiet = Number(rest[0] || 2000);
        const deadline = Date.now() + Number(rest[1] || 60000);
        let last = null;
        let since = Date.now();
        for (;;) {
          let text = null;
          try {
            text = await evaluate(cdp, pageText);
          } catch {
            // the page may be reloading
          }
          if (text !== last) {
            last = text;
            since = Date.now();
          } else if (text !== null && Date.now() - since >= quiet) {
            return print(text);
          }
          if (Date.now() > deadline) {
            print(last ?? "");
            throw new Error("timed out: the page text kept changing");
          }
          await sleep(250);
        }
      }
      case "drag": {
        if (rest.length < 2) usage();
        const points = rest.map((p) => {
          const [x, y, ms = 16] = p.split(",").map(Number);
          if ([x, y, ms].some(Number.isNaN)) usage();
          return { x, y, ms };
        });
        const touch = (type, { x, y }) =>
          cdp.send("Input.dispatchTouchEvent", {
            type,
            touchPoints: type === "touchEnd" ? [] : [{ x, y, id: 1 }],
          });
        for (const [i, p] of points.entries()) {
          await touch(i === 0 ? "touchStart" : "touchMove", p);
          await sleep(p.ms);
        }
        await touch("touchEnd", points.at(-1));
        return console.log("ok");
      }
      default:
        usage();
    }
  } finally {
    cdp.close();
  }
}

main().catch((e) => {
  console.error(`webview.mjs: ${e.message}`);
  process.exit(1);
});
