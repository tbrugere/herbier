// Preloaded (node -r) by test/bindings/jsoo/dune, before cap_uploader_smoke's
// js_of_ocaml program loads: a stub Uploader Capacitor plugin under
// globalThis.herbier.uploader, standing for
// android/app/src/main/java/re/bruge/herbier/UploaderPlugin.java. Controlled
// from OCaml through plain string/JSON globals (a closure cannot cross the
// jsoo boundary): __last_call_json records the last enqueue, cancel or jobs
// call, as JSON.stringify([name, args]); __next_jobs_json controls what
// jobs() resolves to; __next_error, when set to {code, message}, makes
// enqueue, cancel and jobs reject instead. cap_uploader_smoke.ml empties globalThis.herbier
// itself for the "plugin absent" cases: nothing here needs to put it back.
globalThis.__last_call_json = "null";
globalThis.__next_jobs_json = JSON.stringify({ jobs: [] });
globalThis.__next_error = null;

function settle() {
  const e = globalThis.__next_error;
  if (e) {
    const err = new Error(e.message);
    if (e.code) err.code = e.code;
    return Promise.reject(err);
  }
  return Promise.resolve();
}

const uploader = {
  enqueue(args) {
    globalThis.__last_call_json = JSON.stringify(["enqueue", args]);
    return settle();
  },
  cancel(args) {
    globalThis.__last_call_json = JSON.stringify(["cancel", args]);
    return settle();
  },
  jobs() {
    globalThis.__last_call_json = JSON.stringify(["jobs", {}]);
    if (globalThis.__next_error) return settle();
    return Promise.resolve(JSON.parse(globalThis.__next_jobs_json));
  },
  addListener() {
    return Promise.resolve({ remove() {} });
  },
  removeAllListeners() {
    return Promise.resolve();
  },
};

globalThis.herbier = { uploader };
