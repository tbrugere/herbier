// Preloaded (node -r) by test/bindings/jsoo/dune, before
// cap_volume_key_smoke's js_of_ocaml program loads: a stub VolumeKey
// Capacitor plugin under globalThis.herbier.volumeKey, standing for
// android/app/src/main/java/re/bruge/herbier/VolumeKeyPlugin.java.
// __last_call records the last enable or disable call's name; __next_error,
// when set to {code, message}, makes enable, disable and addListener reject.
// addListener(name, cb) keeps cb and records the event name in
// __listener_name; its handle's remove() drops it; globalThis.__fire() calls
// the kept callback with {}, standing for a volume-down press.
globalThis.__last_call = "";
globalThis.__next_error = null;
globalThis.__listener_name = null;

let listener = null;

function settle() {
  const e = globalThis.__next_error;
  if (e) {
    const err = new Error(e.message);
    if (e.code) err.code = e.code;
    return Promise.reject(err);
  }
  return Promise.resolve(undefined);
}

const volumeKey = {
  enable() {
    globalThis.__last_call = "enable";
    return settle();
  },
  disable() {
    globalThis.__last_call = "disable";
    return settle();
  },
  addListener(name, cb) {
    if (globalThis.__next_error) return settle();
    globalThis.__listener_name = name;
    listener = cb;
    return Promise.resolve({
      remove() {
        listener = null;
        return Promise.resolve();
      },
    });
  },
};

globalThis.__fire = function () {
  if (listener) listener({});
};

globalThis.herbier = { volumeKey };
