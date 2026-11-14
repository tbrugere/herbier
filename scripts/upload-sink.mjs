#!/usr/bin/env node
// A stand-in for a Drive resumable session, for the device checks of the
// originals' uploads (#dev/uploader, UploadWorker.java) without Google. Node
// 22+, no dependencies. Listens on 127.0.0.1; reach it from the emulator with
// `adb reverse tcp:8787 tcp:8787` (the debug build's allow-list accepts
// http://localhost:<port>).
//
//   node scripts/upload-sink.mjs [--port 8787] [--fail N] [--gone <id>]... [--dir <out>]
//
// PUT /upload/<id>:
//   Content-Range: bytes */N (no body)  status query: 308 with
//                                       Range: bytes=0-<received-1> (no Range
//                                       when nothing), or 200 when complete
//   a body (Content-Range: bytes a-b/N  appended at its offset: 200
//   optional)                           {"id":"sink-<id>","webViewLink":…} once
//                                       complete, else 308
// A resend after bytes are held must carry Content-Range (else 400).
// --fail N: the first N requests answer 503. --gone <id>: every request for
// that id answers 404 "Not Found" (an expired session). Each request is one
// stdout line; a complete file is written to <out>/<id> (default a fresh
// temporary directory) and its SHA-256 printed.
import { createHash } from "node:crypto";
import { mkdtempSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";

const usage = () => {
  console.error("usage: upload-sink.mjs [--port N] [--fail N] [--gone <id>]... [--dir <out>]");
  process.exit(2);
};

let port = 8787;
let failures = 0;
let dir;
const gone = new Set();
const args = process.argv.slice(2);
while (args.length > 0) {
  const flag = args.shift();
  const value = args.shift();
  if (value === undefined) usage();
  switch (flag) {
    case "--port": port = Number(value); break;
    case "--fail": failures = Number(value); break;
    case "--gone": gone.add(value); break;
    case "--dir": dir = value; break;
    default: usage();
  }
}
if (!Number.isInteger(port) || !Number.isInteger(failures)) usage();
dir ??= mkdtempSync(join(tmpdir(), "herbier-sink-"));
console.log(`sink: http://127.0.0.1:${port}/upload/<id>, files in ${dir}`);

// id → {total: number | undefined, data: Buffer}
const sessions = new Map();

const answer = (res, status, headers, body, line) => {
  res.writeHead(status, headers);
  res.end(body);
  console.log(`${line} → ${status}`);
};

const server = createServer((req, res) => {
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    const body = Buffer.concat(chunks);
    const match = /^\/upload\/([A-Za-z0-9-]+)$/.exec(req.url ?? "");
    const range = req.headers["content-range"] ?? "";
    const line = `${req.method} ${req.url} range=${range || "-"} bytes=${body.length}`;
    if (req.method !== "PUT" || !match) return answer(res, 404, {}, "Not Found", line);
    const id = match[1];
    if (failures > 0) {
      failures -= 1;
      return answer(res, 503, {}, "Service Unavailable", line);
    }
    if (gone.has(id)) return answer(res, 404, { "Content-Type": "text/plain" }, "Not Found", line);
    const session = sessions.get(id) ?? { total: undefined, data: Buffer.alloc(0) };
    sessions.set(id, session);
    const query = /^bytes \*\/(\d+)$/.exec(range);
    const part = /^bytes (\d+)-(\d+)\/(\d+)$/.exec(range);
    if (query) {
      session.total = Number(query[1]);
    } else {
      const offset = part ? Number(part[1]) : 0;
      session.total = part ? Number(part[3]) : body.length;
      if (offset !== session.data.length) {
        return answer(res, 400, {}, `offset ${offset}, held ${session.data.length}`, line);
      }
      session.data = Buffer.concat([session.data, body]);
    }
    if (session.total !== undefined && session.data.length >= session.total) {
      const file = join(dir, id);
      writeFileSync(file, session.data);
      const sha = createHash("sha256").update(session.data).digest("hex");
      console.log(`complete ${id}: ${session.data.length} bytes sha256 ${sha} (${file})`);
      return answer(
        res,
        200,
        { "Content-Type": "application/json" },
        JSON.stringify({ id: `sink-${id}`, webViewLink: `http://localhost/sink/${id}` }),
        line,
      );
    }
    const held = session.data.length > 0 ? { Range: `bytes=0-${session.data.length - 1}` } : {};
    return answer(res, 308, held, "", line);
  });
});
server.listen(port, "127.0.0.1");
