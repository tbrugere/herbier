// Node test of web/runner/keepalive.js: the background runner's own
// script, loaded fresh per event in a node:vm context with the runner's
// globals stubbed (addEventListener, CapacitorKV over a Map,
// CapacitorApp.getState, fetch scripted per call, console capturing lines,
// a Date.now the test sets), fed the hand-off test/sync/handoff_sample.ml
// renders with the production Keepalive.Wire (handoff.json: a session doc and
// a queue doc of 3 entries) and the recorded gotrue_*/sync_* fixtures.
// CapacitorKV is stubbed as the plugin's KV API: get(key) -> {value},
// set(key, value), remove(key).
//
// It writes what test/sync/test_keepalive.ml decodes back: kv_after.json
// (takeSession's answer after a refresh), report.json (report's answer
// after a run of every outcome), report_with_session.json (report's answer
// while a session is held) and lines.json (those runs' console lines).

import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
// The rule's outputs go to the directory dune
// runs the action in: in a sandbox `here` is the symlink-resolved
// _build/default/test/runner, not where dune looks for the targets.
const out = process.cwd();
const root = path.resolve(here, "..", "..");

const jobSource = fs.readFileSync(
  path.join(root, "web/runner/keepalive.js"),
  "utf8"
);
const handoff = JSON.parse(
  fs.readFileSync(path.join(here, "handoff.json"), "utf8")
);

function fixture(name) {
  return fs.readFileSync(path.join(root, "test/fixtures", name), "utf8");
}

const FIX = {
  refresh200: fixture("gotrue_token_refresh_200.json"),
  refreshNotFound400: fixture("gotrue_token_refresh_not_found_400.json"),
  refreshInvalid400: fixture("gotrue_token_refresh_invalid_400.json"),
  pingOk: fixture("sync_select_tags_keepalive_200.json"),
  ping401: fixture("sync_select_tags_keepalive_401.json"),
  push409: fixture("sync_upsert_observations_fk_409.json"),
};

const refresh200Json = JSON.parse(FIX.refresh200);

const handoffDoc = JSON.parse(handoff.session_doc_json);
const handoffBackend = handoffDoc.backend;
const handoffSession = handoffDoc.session;
const handoffQueue = JSON.parse(handoff.queue_doc_json);
const handoffRequests = handoffQueue.requests;
assert.equal(
  handoffRequests.length,
  3,
  "handoff.json is expected to carry a queue of 3 requests (test/sync/handoff_sample.ml)"
);

// handoffSession.expires_at (seconds) comes from a fixture built around
// 2026-11-12T10:00:00Z; NOT_DUE_NOW sits 10 minutes before it (well outside
// the job's 90 s "due" window), REFRESH_SENT_MS is the fixed instant
// test/sync/test_keepalive.ml's decode_taken_session_of_the_js_refresh
// cross-checks kv_after.json against (expires_at = floor(sent_ms/1000) +
// expires_in): both files agree on this literal.
const EXPIRES_AT_MS = handoffSession.expires_at * 1000;
const NOT_DUE_NOW = EXPIRES_AT_MS - 10 * 60 * 1000;
const REFRESH_SENT_MS = 1_800_000_000_000;

// ---------- small harness ----------

function kvValue(obj) {
  return JSON.stringify(obj);
}

// A KV store over a Map. `timeline`, when given, also receives an entry for
// every get/set/remove, shared with a fetch stub's calls, so a test can
// assert relative order (the new session is written before it is used).
function makeKV(initial = {}, timeline = []) {
  const store = new Map(Object.entries(initial));
  return {
    store,
    timeline,
    get(key) {
      timeline.push({ kind: "kv-get", key });
      return { value: store.has(key) ? store.get(key) : null };
    },
    set(key, value) {
      timeline.push({ kind: "kv-set", key, value });
      store.set(key, value);
    },
    remove(key) {
      timeline.push({ kind: "kv-remove", key });
      store.delete(key);
    },
  };
}

// fetch, scripted call by call. Each entry is {status, body} or
// {throwMessage}, or a function of the call returning one of those (for a
// response with a side effect, e.g. a reclaim mid-run).
function sequenceFetch(script, timeline = []) {
  const calls = [];
  let i = 0;
  const fetch = async (url, opts = {}) => {
    const idx = i++;
    const call = {
      url,
      method: opts.method,
      headers: opts.headers || {},
      body: opts.body ?? null,
    };
    calls.push(call);
    timeline.push({ kind: "fetch", call });
    if (idx >= script.length) {
      throw new Error(
        `fetch stub: unscripted call #${idx} (${opts.method} ${url})`
      );
    }
    const entry =
      typeof script[idx] === "function" ? script[idx](call) : script[idx];
    if (entry.throwMessage) throw new Error(entry.throwMessage);
    const bodyText = entry.body ?? "";
    return {
      ok: entry.status >= 200 && entry.status < 300,
      status: entry.status,
      async json() {
        return JSON.parse(bodyText);
      },
      async text() {
        return bodyText;
      },
    };
  };
  return { fetch, calls };
}

// Every console line any loaded job printed in this file, for the token
// search (the aggregation test runs last; node:test runs a file's top-level
// tests in order).
const allConsoleLines = [];

// Loads web/runner/keepalive.js into a fresh vm context, as the plugin
// does for every event: only `kv` persists across calls, by being the same
// object passed to several `load`s. Returns the registered handlers,
// `sandbox` (to set `fetch` or move `__now` before or during a handler),
// `appState` (whose isActive a fetch stub may flip mid-run) and
// `consoleLines` (what this job printed).
function load({ kv, isActive = false, now }) {
  const consoleLines = [];
  const capture = (...a) => {
    const line = a.map(String).join(" ");
    consoleLines.push(line);
    allConsoleLines.push(line);
  };
  const handlers = {};
  const appState = { isActive };
  const sandbox = {
    __now: now,
    addEventListener(name, fn) {
      handlers[name] = fn;
    },
    CapacitorKV: kv,
    CapacitorApp: { getState: () => ({ isActive: appState.isActive }) },
    fetch: async () => {
      throw new Error("fetch stub not configured for this call");
    },
    console: {
      log: capture,
      warn: capture,
      error: capture,
    },
    setTimeout,
    clearTimeout,
    TextEncoder,
    TextDecoder,
    crypto: globalThis.crypto,
    CapacitorDevice: {},
    CapacitorNotifications: {},
    CapacitorGeolocation: {},
  };
  const context = vm.createContext(sandbox);
  // Date (like every other built-in) lives on the context's inner global,
  // not on the sandbox object the host sees: it cannot be patched from out
  // here (`context.Date` reads back as undefined even though `Date` resolves
  // fine to code run inside the context). Patch it with a snippet run inside
  // instead, reading the fixed instant off a plain data property (`__now`,
  // an ordinary property, round-trips normally).
  vm.runInContext("Date.now = function () { return globalThis.__now; };", context);
  vm.runInContext(jobSource, context, { filename: "keepalive.js" });
  return { handlers, consoleLines, sandbox, appState };
}

// Calls a handler the way dispatchEvent does (resolve, reject, details),
// waits until it settles (5 s at most), then one more turn, and returns how
// many times resolve/reject fired (exactly once on every path), which one
// first, and its value.
function invoke(handler, details) {
  const calls = { count: 0, kind: null, value: undefined };
  return new Promise((done) => {
    const guard = setTimeout(() => done(calls), 5000);
    const settle = (kind) => (v) => {
      calls.count++;
      if (calls.count === 1) {
        calls.kind = kind;
        calls.value = v;
        clearTimeout(guard);
        setTimeout(() => done(calls), 0);
      }
    };
    handler(settle("resolve"), settle("reject"), details);
  });
}

function lowerHeaders(h) {
  const out = {};
  for (const [k, v] of Object.entries(h || {})) out[k.toLowerCase()] = v;
  return out;
}

function assertBearerCall(call, req, accessToken, label) {
  assert.equal(call.url, req.url, `${label}: url`);
  assert.equal(call.method, req.method, `${label}: method`);
  const headers = lowerHeaders(call.headers);
  const expected = lowerHeaders(req.headers);
  expected.authorization = `Bearer ${accessToken}`;
  assert.deepEqual(headers, expected, `${label}: headers byte-for-byte plus the bearer`);
  assert.equal(call.body ?? null, req.body ?? null, `${label}: body byte-for-byte`);
}

function lastRun(kv) {
  const raw = kv.store.get("log");
  assert.ok(raw, "the log key is present in KV after a run");
  const log = JSON.parse(raw);
  assert.ok(Array.isArray(log) && log.length > 0, "the log holds at least one run");
  return log[0];
}

function withQueue(requests) {
  return kvValue({ v: 1, requests });
}

function sessionKV(extra = {}) {
  return makeKV({
    backend: kvValue(handoffBackend),
    session: kvValue(handoffSession),
    queue: kvValue(handoffQueue),
    ...extra,
  });
}

// ---------- setSession ----------

test("setSession stores backend and session and removes any queue", async () => {
  const kv = makeKV({ queue: kvValue({ v: 1, requests: [] }) });
  const { handlers } = load({ kv, now: NOT_DUE_NOW });
  const calls = await invoke(handlers.setSession, { json: handoff.session_doc_json });
  assert.equal(calls.count, 1);
  assert.equal(calls.kind, "resolve");
  assert.deepEqual(JSON.parse(kv.store.get("backend")), handoffBackend);
  assert.deepEqual(JSON.parse(kv.store.get("session")), handoffSession);
  assert.equal(kv.store.has("queue"), false);
});

test("setSession with invalid JSON rejects and leaves KV untouched", async () => {
  const kv = makeKV({ backend: "sentinel-backend", session: "sentinel-session" });
  const before = new Map(kv.store);
  const { handlers } = load({ kv, now: NOT_DUE_NOW });
  const calls = await invoke(handlers.setSession, { json: "{not json" });
  assert.equal(calls.count, 1);
  assert.equal(calls.kind, "reject");
  assert.deepEqual(kv.store, before);
});

test("setSession with a well-formed JSON object missing a required field rejects and leaves KV untouched", async () => {
  const kv = makeKV({ backend: "sentinel-backend" });
  const before = new Map(kv.store);
  const { handlers } = load({ kv, now: NOT_DUE_NOW });
  const calls = await invoke(handlers.setSession, {
    json: JSON.stringify({ backend: handoffBackend }), // no "session" key
  });
  assert.equal(calls.count, 1);
  assert.equal(calls.kind, "reject");
  assert.deepEqual(kv.store, before);
});

for (const key of ["ping", "refresh", "logout"]) {
  test(`setSession rejects a backend whose ${key} request leaves supabase_url`, async () => {
    const kv = makeKV({});
    const { handlers } = load({ kv, now: NOT_DUE_NOW });
    const backend = {
      ...handoffBackend,
      [key]: { ...handoffBackend[key], url: "https://elsewhere.example/x" },
    };
    const calls = await invoke(handlers.setSession, {
      json: JSON.stringify({ backend, session: handoffSession }),
    });
    assert.equal(calls.kind, "reject");
    assert.equal(kv.store.has("session"), false);
  });
}

// ---------- handOff / reclaim ----------

test("handOff writes a well-formed queue document and resolves", async () => {
  const kv = makeKV({ queue: kvValue({ v: 1, requests: [] }) });
  const { handlers } = load({ kv, now: NOT_DUE_NOW });
  const calls = await invoke(handlers.handOff, { json: handoff.queue_doc_json });
  assert.equal(calls.count, 1);
  assert.equal(calls.kind, "resolve");
  assert.deepEqual(JSON.parse(kv.store.get("queue")), handoffQueue);
});

test("handOff with an invalid document rejects and leaves the queue untouched", async () => {
  const kv = makeKV({ queue: kvValue(handoffQueue) });
  const before = kv.store.get("queue");
  const { handlers } = load({ kv, now: NOT_DUE_NOW });
  const calls = await invoke(handlers.handOff, {
    json: JSON.stringify({ v: 1, requests: "not-an-array" }),
  });
  assert.equal(calls.count, 1);
  assert.equal(calls.kind, "reject");
  assert.equal(kv.store.get("queue"), before);
});

test("reclaim with nothing in flight removes the queue and answers in_flight false", async () => {
  const kv = makeKV({ queue: kvValue(handoffQueue) });
  const { handlers } = load({ kv, now: NOT_DUE_NOW });
  const calls = await invoke(handlers.reclaim, {});
  assert.equal(calls.count, 1);
  assert.equal(calls.kind, "resolve");
  assert.deepEqual(JSON.parse(calls.value.json), { v: 1, in_flight: false });
  assert.equal(kv.store.has("queue"), false);
});

test("reclaim waits for a request in flight to answer before it answers", async () => {
  const kv = makeKV({ queue: kvValue(handoffQueue), inflight: String(NOT_DUE_NOW) });
  const { handlers } = load({ kv, now: NOT_DUE_NOW });
  let answered = false;
  setTimeout(() => {
    assert.equal(answered, false, "reclaim has not answered while the request is in flight");
    // The run's request answers, and, racing the reclaim, the run writes
    // the queue back: the reclaim removes it again.
    kv.store.set("queue", kvValue(handoffQueue));
    kv.store.delete("inflight");
  }, 300);
  const calls = await invoke(handlers.reclaim, {});
  answered = true;
  assert.equal(calls.kind, "resolve");
  assert.deepEqual(JSON.parse(calls.value.json), { v: 1, in_flight: false });
  assert.equal(kv.store.has("queue"), false);
});

test("reclaim gives up after 10 s and answers in_flight true", async () => {
  const kv = makeKV({ queue: kvValue(handoffQueue), inflight: String(NOT_DUE_NOW) });
  const { handlers, sandbox } = load({ kv, now: NOT_DUE_NOW });
  setTimeout(() => {
    sandbox.__now = NOT_DUE_NOW + 11 * 1000;
  }, 50);
  const calls = await invoke(handlers.reclaim, {});
  assert.equal(calls.kind, "resolve");
  assert.deepEqual(JSON.parse(calls.value.json), { v: 1, in_flight: true });
  assert.equal(kv.store.has("queue"), false);
});

test("reclaim ignores an inflight mark older than 10 minutes (a run that died)", async () => {
  const kv = makeKV({
    queue: kvValue(handoffQueue),
    inflight: String(NOT_DUE_NOW - 11 * 60 * 1000),
  });
  const { handlers } = load({ kv, now: NOT_DUE_NOW });
  const calls = await invoke(handlers.reclaim, {});
  assert.deepEqual(JSON.parse(calls.value.json), { v: 1, in_flight: false });
});

// ---------- report ----------

test("report with no session and no run yet", async () => {
  const kv = makeKV({});
  const { handlers } = load({ kv, now: NOT_DUE_NOW });
  const calls = await invoke(handlers.report, {});
  assert.equal(calls.count, 1);
  const parsed = JSON.parse(calls.value.json);
  assert.deepEqual(parsed, { v: 1, session_expires_at: null, queued: 0, runs: [] });
});

test("report reflects the current session's expiry and the queued count", async () => {
  const kv = sessionKV();
  const { handlers } = load({ kv, now: NOT_DUE_NOW });
  const calls = await invoke(handlers.report, {});
  const parsed = JSON.parse(calls.value.json);
  assert.equal(parsed.session_expires_at, handoffSession.expires_at);
  assert.equal(parsed.queued, handoffRequests.length);
  // test/sync/test_keepalive.ml decodes it (a session's expiry, in seconds).
  fs.writeFileSync(path.join(out, "report_with_session.json"), calls.value.json);
});

// ---------- takeSession ----------

test("takeSession returns the current session and removes session and queue, keeping backend", async () => {
  const kv = sessionKV();
  const { handlers } = load({ kv, now: NOT_DUE_NOW });
  const calls = await invoke(handlers.takeSession, {});
  assert.equal(calls.count, 1);
  assert.equal(calls.kind, "resolve");
  const parsed = JSON.parse(calls.value.json);
  assert.equal(parsed.v, 1);
  assert.deepEqual(parsed.session, handoffSession);
  assert.equal(kv.store.has("session"), false);
  assert.equal(kv.store.has("queue"), false);
  assert.equal(kv.store.has("backend"), true, "backend (url/apikey) is not session state");
});

test("takeSession with no session resolves {v:1, session:null}", async () => {
  const kv = makeKV({});
  const { handlers } = load({ kv, now: NOT_DUE_NOW });
  const calls = await invoke(handlers.takeSession, {});
  assert.equal(calls.count, 1);
  assert.deepEqual(JSON.parse(calls.value.json), { v: 1, session: null });
});

test("takeSession with an unreadable session resolves session:null and still clears session and queue", async () => {
  const kv = makeKV({
    backend: kvValue(handoffBackend),
    session: "not json",
    queue: kvValue(handoffQueue),
  });
  const { handlers } = load({ kv, now: NOT_DUE_NOW });
  const calls = await invoke(handlers.takeSession, {});
  assert.deepEqual(JSON.parse(calls.value.json), { v: 1, session: null });
  assert.equal(kv.store.has("session"), false);
  assert.equal(kv.store.has("queue"), false);
});

// ---------- keepAlive: no usable session ----------

test("a run with no session logs session:none, no queue, and makes no fetch call", async () => {
  const kv = makeKV({});
  const { handlers, sandbox } = load({ kv, now: NOT_DUE_NOW });
  sandbox.fetch = async () => {
    throw new Error("fetch must not be called with no session");
  };
  const outcome = await invoke(handlers.keepAlive, {});
  assert.equal(outcome.count, 1);
  assert.equal(outcome.kind, "resolve");
  const run = lastRun(kv);
  assert.equal(run.session, "none");
  assert.equal(run.queue, null);
  assert.equal(run.error, null);
  assert.equal(run.ping, null);
  assert.equal(run.trigger, "job");
});

for (const [label, extra, why] of [
  ["an unreadable session", { session: "{not json" }, "bad session in KV"],
  ["an unreadable backend", { backend: "{not json" }, "bad backend in KV"],
]) {
  test(`a run with ${label} in KV says so as its error, with no fetch`, async () => {
    const kv = sessionKV(extra);
    const { handlers, sandbox } = load({ kv, now: NOT_DUE_NOW });
    sandbox.fetch = async () => {
      throw new Error("fetch must not be called");
    };
    await invoke(handlers.keepAlive, {});
    const run = lastRun(kv);
    assert.equal(run.session, "none");
    assert.equal(run.error, why);
    assert.equal(run.queue, null);
  });
}

test("a run's `at` is the job's clock, in Unix milliseconds", async () => {
  const kv = makeKV({});
  const { handlers, sandbox } = load({ kv, now: NOT_DUE_NOW });
  sandbox.fetch = async () => {
    throw new Error("fetch must not be called with no session");
  };
  await invoke(handlers.keepAlive, {});
  const run = lastRun(kv);
  assert.equal(run.at, NOT_DUE_NOW, "at is Date.now() at the start of the run");
});

// ---------- keepAlive: valid session, full push + ping ----------

test("a fresh session, app inactive, a queue of 3: pushes all three in order, forgets the queue, then pings", async () => {
  const kv = sessionKV();
  const { fetch, calls } = sequenceFetch([
    () => {
      assert.ok(kv.store.has("inflight"), "a request in flight is marked");
      return { status: 201, body: "" };
    },
    { status: 201, body: "" },
    { status: 201, body: "" },
    { status: 200, body: FIX.pingOk },
  ]);
  const { handlers, sandbox } = load({ kv, isActive: false, now: NOT_DUE_NOW });
  sandbox.fetch = fetch;
  const outcome = await invoke(handlers.keepAlive, {});
  assert.equal(outcome.count, 1);
  assert.equal(outcome.kind, "resolve");
  assert.equal(calls.length, 4);
  handoffRequests.forEach((req, i) =>
    assertBearerCall(calls[i], req, handoffSession.access_token, `push #${i}`)
  );
  assertBearerCall(calls[3], handoffBackend.ping, handoffSession.access_token, "ping");
  const run = lastRun(kv);
  assert.equal(run.session, "fresh");
  assert.deepEqual(run.queue, { pushed: 3, stop: null });
  assert.equal(run.ping, 200);
  assert.equal(run.app_active, false);
  assert.equal(kv.store.has("queue"), false, "a queue pushed to the end is forgotten");
  assert.equal(kv.store.has("inflight"), false, "no request is left marked in flight");
});

test("a queue handed off again during the run is kept", async () => {
  const kv = sessionKV();
  const newer = withQueue([handoffRequests[0]]);
  const { fetch } = sequenceFetch([
    { status: 201, body: "" },
    { status: 201, body: "" },
    () => {
      kv.store.set("queue", newer);
      return { status: 201, body: "" };
    },
    { status: 200, body: FIX.pingOk },
  ]);
  const { handlers, sandbox } = load({ kv, now: NOT_DUE_NOW });
  sandbox.fetch = fetch;
  await invoke(handlers.keepAlive, {});
  assert.deepEqual(lastRun(kv).queue, { pushed: 3, stop: null });
  assert.equal(kv.store.get("queue"), newer);
});

test("a 409 on the second push stops the queue there and keeps it; the ping still runs", async () => {
  const kv = sessionKV();
  const { fetch, calls } = sequenceFetch([
    { status: 201, body: "" },
    { status: 409, body: FIX.push409 },
    { status: 200, body: FIX.pingOk },
  ]);
  const { handlers, sandbox } = load({ kv, isActive: false, now: NOT_DUE_NOW });
  sandbox.fetch = fetch;
  const outcome = await invoke(handlers.keepAlive, {});
  assert.equal(outcome.count, 1);
  assert.equal(calls.length, 3, "the third push never happens");
  const run = lastRun(kv);
  assert.deepEqual(run.queue, { pushed: 1, stop: "HTTP 409" });
  assert.equal(run.ping, 200);
  assert.equal(kv.store.has("queue"), true);
});

test("a network failure on the first push stops the queue with a network stop; the ping still runs", async () => {
  const kv = sessionKV();
  const { fetch, calls } = sequenceFetch([
    { throwMessage: "getaddrinfo ENOTFOUND api.example" },
    { status: 200, body: FIX.pingOk },
  ]);
  const { handlers, sandbox } = load({ kv, isActive: false, now: NOT_DUE_NOW });
  sandbox.fetch = fetch;
  const outcome = await invoke(handlers.keepAlive, {});
  assert.equal(outcome.count, 1);
  assert.equal(calls.length, 2);
  const run = lastRun(kv);
  assert.equal(run.queue.pushed, 0);
  assert.match(run.queue.stop, /^network: /);
  assert.equal(run.ping, 200);
  assert.equal(kv.store.has("inflight"), false);
});

test("a queued request outside the backend's /rest/v1/ is not sent", async () => {
  const kv = sessionKV({
    queue: withQueue([{ ...handoffRequests[0], url: "https://elsewhere.example/rest/v1/plants" }]),
  });
  const { fetch, calls } = sequenceFetch([{ status: 200, body: FIX.pingOk }]);
  const { handlers, sandbox } = load({ kv, now: NOT_DUE_NOW });
  sandbox.fetch = fetch;
  await invoke(handlers.keepAlive, {});
  assert.equal(calls.length, 1, "only the ping");
  assert.deepEqual(lastRun(kv).queue, { pushed: 0, stop: "foreign url" });
});

// ---------- keepAlive: the app active ----------

test("an active app skips the queue entirely but still pings", async () => {
  const kv = sessionKV();
  const { fetch, calls } = sequenceFetch([{ status: 200, body: FIX.pingOk }]);
  const { handlers, sandbox } = load({ kv, isActive: true, now: NOT_DUE_NOW });
  sandbox.fetch = fetch;
  const outcome = await invoke(handlers.keepAlive, {});
  assert.equal(outcome.count, 1);
  assert.equal(calls.length, 1, "only the ping; no push was attempted");
  const run = lastRun(kv);
  assert.equal(run.queue, "skipped");
  assert.equal(run.ping, 200);
  assert.equal(run.app_active, true);
});

test("the app turning active mid-run stops the queue with 'app active'; the ping still runs", async () => {
  const kv = sessionKV();
  let appState;
  const { fetch, calls } = sequenceFetch([
    () => {
      appState.isActive = true;
      return { status: 201, body: "" };
    },
    { status: 200, body: FIX.pingOk },
  ]);
  const loaded = load({ kv, isActive: false, now: NOT_DUE_NOW });
  appState = loaded.appState;
  loaded.sandbox.fetch = fetch;
  await invoke(loaded.handlers.keepAlive, {});
  assert.equal(calls.length, 2);
  const run = lastRun(kv);
  assert.deepEqual(run.queue, { pushed: 1, stop: "app active" });
  assert.equal(run.app_active, false, "the state at the start");
  assert.equal(run.ping, 200);
});

// ---------- keepAlive: the queue taken back mid-run ----------

test("the queue disappearing from KV between two pushes (a resume reclaiming it) stops the loop with 'taken back'", async () => {
  const kv = sessionKV();
  const { fetch, calls } = sequenceFetch([
    () => {
      kv.store.delete("queue");
      return { status: 201, body: "" };
    },
    { status: 200, body: FIX.pingOk },
  ]);
  const { handlers, sandbox } = load({ kv, isActive: false, now: NOT_DUE_NOW });
  sandbox.fetch = fetch;
  const outcome = await invoke(handlers.keepAlive, {});
  assert.equal(outcome.count, 1);
  assert.equal(outcome.kind, "resolve");
  assert.equal(calls.length, 2, "one push, then the ping; the 2nd and 3rd pushes never happen");
  const run = lastRun(kv);
  assert.deepEqual(run.queue, { pushed: 1, stop: "taken back" });
  assert.equal(run.ping, 200);
});

test("a reclaim during a push waits for it, and the run sends nothing after", async () => {
  const kv = sessionKV();
  let reclaimed = null;
  const { fetch, calls } = sequenceFetch([
    () => {
      // The app's reclaim, in its own engine, while this request is in flight.
      const { handlers } = load({ kv, now: NOT_DUE_NOW });
      reclaimed = invoke(handlers.reclaim, {});
      return { status: 201, body: "" };
    },
    { status: 200, body: FIX.pingOk },
  ]);
  const { handlers, sandbox } = load({ kv, now: NOT_DUE_NOW });
  sandbox.fetch = fetch;
  await invoke(handlers.keepAlive, {});
  const answer = await reclaimed;
  assert.deepEqual(JSON.parse(answer.value.json), { v: 1, in_flight: false });
  assert.equal(calls.length, 2, "one push, then the ping");
  assert.deepEqual(lastRun(kv).queue, { pushed: 1, stop: "taken back" });
  assert.equal(kv.store.has("queue"), false);
});

// ---------- keepAlive: a due session refreshes before pushing ----------

test("a due session triggers one refresh before the first bearer request; the new token is used for the pushes and the ping; KV is updated before it is used", async () => {
  const timeline = [];
  const kv = makeKV(
    {
      backend: kvValue(handoffBackend),
      session: kvValue(handoffSession),
      queue: kvValue(handoffQueue),
    },
    timeline
  );
  const { fetch, calls } = sequenceFetch(
    [
      { status: 200, body: FIX.refresh200 },
      { status: 201, body: "" },
      { status: 201, body: "" },
      { status: 201, body: "" },
      { status: 200, body: FIX.pingOk },
    ],
    timeline
  );
  const { handlers, sandbox } = load({ kv, isActive: false, now: REFRESH_SENT_MS });
  sandbox.fetch = fetch;
  const outcome = await invoke(handlers.keepAlive, {});
  assert.equal(outcome.count, 1);
  assert.equal(calls.length, 5);

  // The request the app rendered (Gotrue.refresh_grant), with the body.
  const refreshCall = calls[0];
  assert.equal(refreshCall.url, handoffBackend.refresh.url);
  assert.equal(
    refreshCall.url,
    `${handoffBackend.supabase_url}/auth/v1/token?grant_type=refresh_token`
  );
  assert.equal(refreshCall.method, "POST");
  assert.deepEqual(lowerHeaders(refreshCall.headers), lowerHeaders(handoffBackend.refresh.headers));
  assert.deepEqual(JSON.parse(refreshCall.body), {
    refresh_token: handoffSession.refresh_token,
  });
  const refreshHeaders = lowerHeaders(refreshCall.headers);
  assert.equal(refreshHeaders.apikey, handoffBackend.apikey);
  assert.equal(refreshHeaders["content-type"], "application/json");
  assert.equal(refreshHeaders.authorization, undefined);

  for (let i = 0; i < 3; i++) {
    assertBearerCall(
      calls[i + 1],
      handoffRequests[i],
      refresh200Json.access_token,
      `push #${i} after refresh`
    );
  }
  assertBearerCall(calls[4], handoffBackend.ping, refresh200Json.access_token, "ping after refresh");

  const sessionSetIdx = timeline.findIndex(
    (e) => e.kind === "kv-set" && e.key === "session"
  );
  const firstBearerIdx = timeline.findIndex(
    (e) =>
      e.kind === "fetch" &&
      Object.entries(e.call.headers || {}).some(
        ([k, v]) => k.toLowerCase() === "authorization" && /^Bearer /.test(v)
      )
  );
  assert.ok(sessionSetIdx !== -1, "the refreshed session was written to KV");
  assert.ok(firstBearerIdx !== -1, "a bearer request happened");
  assert.ok(
    sessionSetIdx < firstBearerIdx,
    "the new session is written to KV before any request uses it"
  );

  const run = lastRun(kv);
  assert.equal(run.session, "refreshed");
  assert.deepEqual(run.queue, { pushed: 3, stop: null });
  assert.equal(run.ping, 200);

  // test/sync/test_keepalive.ml's decode_taken_session_of_the_js_refresh
  // decodes this file against gotrue_token_refresh_200.json and the fixed
  // REFRESH_SENT_MS above.
  const taken = await invoke(handlers.takeSession, {});
  assert.equal(taken.count, 1);
  assert.equal(taken.kind, "resolve");
  fs.writeFileSync(path.join(out, "kv_after.json"), taken.value.json);
  const takenParsed = JSON.parse(taken.value.json);
  assert.equal(takenParsed.session.access_token, refresh200Json.access_token);
  assert.equal(takenParsed.session.refresh_token, refresh200Json.refresh_token);
});

test("the refresh margin is 90 s: refreshed at 90 s before expiry, not at 91 s", async () => {
  for (const [secondsLeft, refreshes] of [
    [90, true],
    [91, false],
  ]) {
    const kv = sessionKV({ queue: withQueue([]) });
    const { fetch, calls } = sequenceFetch(
      refreshes
        ? [{ status: 200, body: FIX.refresh200 }, { status: 200, body: FIX.pingOk }]
        : [{ status: 200, body: FIX.pingOk }]
    );
    const { handlers, sandbox } = load({
      kv,
      now: (handoffSession.expires_at - secondsLeft) * 1000,
    });
    sandbox.fetch = fetch;
    await invoke(handlers.keepAlive, {});
    assert.equal(lastRun(kv).session, refreshes ? "refreshed" : "fresh", `${secondsLeft} s left`);
    assert.equal(calls.length, refreshes ? 2 : 1);
  }
});

test("a session set by the app during the refresh stands: the refreshed one is logged out", async () => {
  const kv = sessionKV();
  const appSession = kvValue({ ...handoffSession, access_token: "app-handed-access" });
  const { fetch, calls } = sequenceFetch([
    () => {
      kv.store.set("session", appSession);
      return { status: 200, body: FIX.refresh200 };
    },
    { status: 204, body: "" },
  ]);
  const { handlers, sandbox } = load({ kv, now: REFRESH_SENT_MS });
  sandbox.fetch = fetch;
  await invoke(handlers.keepAlive, {});
  assert.equal(calls.length, 2, "the refresh, then the logout: no push, no ping");
  assertBearerCall(calls[1], handoffBackend.logout, refresh200Json.access_token, "logout");
  assert.equal(kv.store.get("session"), appSession);
  const run = lastRun(kv);
  assert.equal(run.session, "replaced");
  assert.equal(run.queue, null);
  assert.equal(run.ping, null);
});

test("a session taken by the app during a refresh that GoTrue revokes stays taken", async () => {
  const kv = sessionKV();
  const { fetch, calls } = sequenceFetch([
    () => {
      kv.store.delete("session");
      return { status: 400, body: FIX.refreshNotFound400 };
    },
  ]);
  const { handlers, sandbox } = load({ kv, now: REFRESH_SENT_MS });
  sandbox.fetch = fetch;
  await invoke(handlers.keepAlive, {});
  assert.equal(calls.length, 1);
  assert.equal(kv.store.has("session"), false);
  assert.equal(lastRun(kv).session, "replaced");
});

// ---------- keepAlive: a due session that GoTrue revokes or that fails to refresh ----------

for (const [label, fixtureText, status] of [
  ["gotrue_token_refresh_not_found_400.json", FIX.refreshNotFound400, 400],
  ["gotrue_token_refresh_invalid_400.json", FIX.refreshInvalid400, 400],
]) {
  test(`a due session refreshed against ${label} is revoked: no PostgREST request, session and queue removed`, async () => {
    const kv = sessionKV();
    const { fetch, calls } = sequenceFetch([{ status, body: fixtureText }]);
    const { handlers, sandbox } = load({ kv, isActive: false, now: REFRESH_SENT_MS });
    sandbox.fetch = fetch;
    const outcome = await invoke(handlers.keepAlive, {});
    assert.equal(outcome.count, 1);
    assert.equal(calls.length, 1, "only the refresh attempt: no push, no ping");
    assert.equal(kv.store.has("session"), false);
    assert.equal(kv.store.has("queue"), false);
    const run = lastRun(kv);
    assert.equal(run.session, "revoked", "the outcome names the revoke");
    assert.equal(run.revoked_status, status, "the run carries GoTrue's status");
    assert.equal(run.ping, null);
    assert.equal(run.queue, null);
  });
}

for (const [label, entry, why] of [
  [
    "a 503 with a non-JSON body",
    { status: 503, body: "<html>Service Unavailable</html>" },
    /^HTTP 503$/,
  ],
  [
    "a 429",
    { status: 429, body: JSON.stringify({ error_code: "over_request_rate_limit", msg: "slow down" }) },
    /^HTTP 429$/,
  ],
  [
    "a 408 with a code",
    { status: 408, body: JSON.stringify({ error_code: "request_timeout", msg: "slow" }) },
    /^HTTP 408$/,
  ],
  ["a 400 with an HTML body", { status: 400, body: "<html>Bad Request</html>" }, /^HTTP 400$/],
  ["a 400 with JSON but no code", { status: 400, body: JSON.stringify({ msg: "x" }) }, /^HTTP 400$/],
  ["a 200 that is not a session", { status: 200, body: "{}" }, /^malformed answer$/],
  ["a network failure", { throwMessage: "ECONNRESET" }, /^network: .*ECONNRESET/],
]) {
  test(`a due session refresh answered with ${label} is kept as refresh_failed; no PostgREST request`, async () => {
    const kv = sessionKV();
    const { fetch, calls } = sequenceFetch([entry]);
    const { handlers, sandbox } = load({ kv, isActive: false, now: REFRESH_SENT_MS });
    sandbox.fetch = fetch;
    const outcome = await invoke(handlers.keepAlive, {});
    assert.equal(outcome.count, 1);
    assert.equal(calls.length, 1);
    assert.deepEqual(JSON.parse(kv.store.get("session")), handoffSession);
    const run = lastRun(kv);
    assert.equal(run.session, "refresh_failed");
    assert.match(run.refresh_error, why, "the run says why the refresh failed");
    assert.equal(run.ping, null);
    assert.equal(run.queue, null);
  });
}

// ---------- the log caps at 20 runs, newest first ----------

test("the log keeps at most 20 runs, newest first", async () => {
  const kv = makeKV({});
  for (let i = 0; i < 25; i++) {
    const { handlers, sandbox } = load({ kv, now: NOT_DUE_NOW + i * 1000 });
    sandbox.fetch = async () => {
      throw new Error("no fetch expected: there is no session");
    };
    const calls = await invoke(handlers.keepAlive, {});
    assert.equal(calls.count, 1);
  }
  const log = JSON.parse(kv.store.get("log"));
  assert.equal(log.length, 20);
  const ats = log.map((run) => run.at);
  for (let i = 1; i < ats.length; i++) {
    assert.ok(ats[i - 1] >= ats[i], "runs are newest first");
  }
  assert.equal(ats[0], NOT_DUE_NOW + 24 * 1000, "the most recent run is first");
  assert.equal(ats[19], NOT_DUE_NOW + 5 * 1000, "the earliest 5 runs were dropped");
});

// ---------- an unexpected exception during a run ----------

test("an exception thrown by a stub (CapacitorKV.get) is caught: the run is still logged with it and resolve is still called", async () => {
  const kv = sessionKV();
  const realGet = kv.get.bind(kv);
  let thrown = false;
  kv.get = (key) => {
    if (key === "queue" && !thrown) {
      thrown = true;
      throw new Error("KV backend unavailable");
    }
    return realGet(key);
  };
  const { handlers, sandbox } = load({ kv, isActive: false, now: NOT_DUE_NOW });
  sandbox.fetch = async () => {
    throw new Error("fetch must not be reached once CapacitorKV.get throws");
  };
  const before = kv.store.has("log") ? JSON.parse(kv.store.get("log")).length : 0;
  const outcome = await invoke(handlers.keepAlive, {});
  assert.equal(outcome.count, 1);
  assert.equal(outcome.kind, "resolve", "the job always resolves");
  kv.get = realGet;
  const after = kv.store.has("log") ? JSON.parse(kv.store.get("log")).length : 0;
  assert.equal(after, before + 1, "a run was logged despite the crash");
  assert.match(lastRun(kv).error, /KV backend unavailable/, "the run carries the error");
});

// ---------- a run of every outcome, decoded back on the OCaml side ----------

test(
  "report() after a sequence of runs covering every outcome is written to report.json, " +
    "their lines to lines.json; neither nor any console line ever carries a token",
  async () => {
    const kv = makeKV({});
    const lines = [];
    // Loads the job for one event; a run's console lines are kept in order.
    const run = async (event, { now = NOT_DUE_NOW, isActive = false, script = [] } = {}) => {
      const { handlers, sandbox, consoleLines } = load({ kv, isActive, now });
      const { fetch } = sequenceFetch(script);
      sandbox.fetch = fetch;
      const outcome = await invoke(handlers[event], event === "setSession"
        ? { json: handoff.session_doc_json }
        : event === "handOff"
          ? { json: handoff.queue_doc_json }
          : {});
      assert.equal(outcome.count, 1, event);
      assert.equal(outcome.kind, "resolve", event);
      for (const l of consoleLines)
        if (l.startsWith("keepalive: ")) lines.push(l.slice("keepalive: ".length));
      return outcome;
    };
    const ok201 = { status: 201, body: "" };
    const pingOk = { status: 200, body: FIX.pingOk };

    await run("keepAlive"); // none
    await run("setSession");
    await run("handOff");
    await run("keepAlive", { script: [ok201, ok201, ok201, pingOk] }); // pushed 3
    await run("handOff");
    await run("keepAlive", { script: [ok201, { status: 409, body: FIX.push409 }, pingOk] });
    await run("reclaim");
    await run("keepAlive", { script: [{ status: 401, body: FIX.ping401 }] }); // pushed 0, ping 401
    await run("handOff");
    await run("keepAlive", { isActive: true, script: [pingOk] }); // queue skipped
    await run("reclaim");
    await run("keepAlive", { script: [{ throwMessage: "ping: network unreachable" }] });
    const appSession = kvValue({ ...handoffSession, access_token: "app-handed-access" });
    await run("keepAlive", {
      now: REFRESH_SENT_MS,
      script: [
        () => {
          kv.store.set("session", appSession);
          return { status: 200, body: FIX.refresh200 };
        },
        { status: 204, body: "" },
      ],
    }); // replaced
    await run("keepAlive", {
      now: REFRESH_SENT_MS,
      script: [{ status: 503, body: "<html>down</html>" }],
    }); // refresh_failed
    await run("keepAlive", {
      now: REFRESH_SENT_MS,
      script: [{ status: 200, body: FIX.refresh200 }, pingOk],
    }); // refreshed
    const refreshedSession = JSON.parse(kv.store.get("session"));
    assert.equal(refreshedSession.access_token, refresh200Json.access_token);
    await run("keepAlive", {
      now: (refreshedSession.expires_at - 10) * 1000,
      script: [{ status: 400, body: FIX.refreshNotFound400 }],
    }); // revoked
    await run("runNow"); // dispatch, none
    kv.store.set("backend", kvValue(handoffBackend));
    kv.store.set("session", "{not json");
    await run("keepAlive"); // error: bad session in KV

    const reportOutcome = await run("report");
    const reportText = reportOutcome.value.json;
    fs.writeFileSync(path.join(out, "report.json"), reportText);
    fs.writeFileSync(path.join(out, "lines.json"), JSON.stringify(lines));
    const report = JSON.parse(reportText);

    assert.equal(report.v, 1);
    assert.equal(report.session_expires_at, null, "the session in KV is unreadable");
    assert.equal(report.queued, 0);
    assert.equal(report.runs.length, 12);
    assert.equal(lines.length, 12, "one line per run");

    const sessions = report.runs.map((r) => r.session);
    for (const s of ["none", "fresh", "refreshed", "replaced", "revoked", "refresh_failed"])
      assert.ok(sessions.includes(s), s);
    assert.ok(report.runs.some((r) => r.queue === "skipped"));
    assert.ok(report.runs.some((r) => r.queue !== null && r.queue.stop === "HTTP 409"));
    assert.ok(report.runs.some((r) => r.error === "bad session in KV"));
    assert.ok(report.runs.some((r) => r.trigger === "dispatch"));

    // No captured text anywhere carries a token: the report text itself and
    // every console line any job printed in this file (every run logs one,
    // including the ones that held real tokens).
    const haystacks = [reportText, ...allConsoleLines];
    const tokens = [
      handoffSession.access_token,
      handoffSession.refresh_token,
      refresh200Json.access_token,
      refresh200Json.refresh_token,
      "app-handed-access",
    ];
    for (const haystack of haystacks) {
      for (const token of tokens) {
        assert.ok(!haystack.includes(token), `no token leaks into: ${haystack.slice(0, 80)}`);
      }
    }
  }
);
