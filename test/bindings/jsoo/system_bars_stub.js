// Preloaded (node -r) by test/bindings/jsoo/dune, before
// cap_system_bars_smoke's js_of_ocaml program loads: a stub SystemBars
// Capacitor plugin under globalThis.herbier.systemBars, standing for
// @capacitor/android's core com/getcapacitor/plugin/SystemBars.java.
// Controlled from OCaml through plain string/JSON globals (a closure cannot
// cross the jsoo boundary): __calls_json accumulates every setStyle argument,
// the failing calls included, as JSON.stringify([...calls]); __next_reject,
// when set to {code, message}, makes the next call reject instead (cleared
// after firing, so later calls succeed again); __next_throw, when true, makes
// the next call throw synchronously instead of returning a promise (cleared
// after firing). cap_system_bars_smoke.ml empties globalThis.herbier itself
// for the plugin-absent case: nothing here needs to put it back.
globalThis.__calls_json = "[]";
globalThis.__next_reject = null;
globalThis.__next_throw = false;

const systemBars = {
  setStyle(o) {
    const calls = JSON.parse(globalThis.__calls_json);
    calls.push(o);
    globalThis.__calls_json = JSON.stringify(calls);
    if (globalThis.__next_throw) {
      globalThis.__next_throw = false;
      throw new Error("boom");
    }
    const reject = globalThis.__next_reject;
    if (reject) {
      globalThis.__next_reject = null;
      const err = new Error(reject.message);
      if (reject.code) err.code = reject.code;
      return Promise.reject(err);
    }
    return Promise.resolve();
  },
};

globalThis.herbier = { systemBars };
