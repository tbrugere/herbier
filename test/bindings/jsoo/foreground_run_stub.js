// Preloaded (node -r) by test/bindings/jsoo/dune, before
// cap_foreground_run_smoke's js_of_ocaml program loads: a stub ForegroundRun
// Capacitor plugin under globalThis.herbier.foregroundRun, standing for
// android/app/src/main/java/re/bruge/herbier/ForegroundRunPlugin.java and
// ForegroundRunService.java. Controlled from OCaml through plain
// string/JSON globals:
// __last_call_json records the last start, update or stop call, as
// JSON.stringify([name, args]); __next_start_json controls what start()
// resolves to (default {"notifications":"granted"}); __next_error, when set
// to {code, message}, makes start, update, stop and addListener reject
// instead. addListener(name, cb) keeps cb and records the event name in
// __listener_name; its handle's remove() drops it; globalThis.__fire(json) calls the kept callback with
// JSON.parse(json), standing for the service (or the notification action)
// posting an "interrupt" event. cap_foreground_run_smoke.ml empties
// globalThis.herbier itself for the "plugin absent" case: nothing here needs
// to put it back.
globalThis.__last_call_json = "null";
globalThis.__next_start_json = JSON.stringify({ notifications: "granted" });
globalThis.__next_error = null;
globalThis.__listener_name = null;

let listener = null;

function recordCall(name, args) {
  globalThis.__last_call_json = JSON.stringify([name, args === undefined ? {} : args]);
}

function settle(resolveValue) {
  const e = globalThis.__next_error;
  if (e) {
    const err = new Error(e.message);
    if (e.code) err.code = e.code;
    return Promise.reject(err);
  }
  return Promise.resolve(resolveValue);
}

const foregroundRun = {
  start(args) {
    recordCall("start", args);
    if (globalThis.__next_error) return settle();
    return settle(JSON.parse(globalThis.__next_start_json));
  },
  update(args) {
    recordCall("update", args);
    return settle(undefined);
  },
  stop(args) {
    recordCall("stop", args);
    return settle(undefined);
  },
  addListener(name, cb) {
    if (globalThis.__next_error) return settle();
    globalThis.__listener_name = name;
    listener = cb;
    return Promise.resolve({
      remove() {
        listener = null;
      },
    });
  },
  removeAllListeners() {
    listener = null;
    return Promise.resolve();
  },
};

globalThis.__fire = function (json) {
  if (listener) listener(JSON.parse(json));
};

globalThis.herbier = { foregroundRun };
