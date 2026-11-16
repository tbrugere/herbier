// Preloaded (node -r) by test/bindings/jsoo/dune, before
// cap_filesystem_smoke's js_of_ocaml program loads: a stub Capacitor
// Filesystem plugin under globalThis.herbier.filesystem, standing for the
// @capacitor/filesystem plugin.
//
// readdir resolves the fixtures of test/fixtures/, read here with
// fs.readFileSync from the paths the dune rule sets in
// HERBIER_FIXTURE_READDIR_{PREVIEWS,REFTHUMBS,MISSING} (a jsoo program has
// no plain `require`, so the reading happens in this preload script, not in
// cap_filesystem_smoke.ml); the previews/refthumbs ones are also exposed as
// __fixture_readdir_{previews,refthumbs}_json so the OCaml test can decode
// the same values for its expectations, instead of copying them by hand.
// __next_readdir_json / __next_readdir_error (set from OCaml, like
// uploader_stub.js's __next_jobs_json) override the response for the
// decode-error and other-rejection cases the fixtures do not cover.
// __readdir_tree_json, a JSON object from path to listing (or to
// {"reject": {code, message}}), answers a whole directory tree for
// Files.usage; a path it lacks rejects as missing. __last_call_json records
// the last call, as JSON.stringify([name, args]). rmdir rejects as missing
// for "nope", with __next_rmdir_error when set, and resolves otherwise; its
// call is recorded the same way.
const fs = require("node:fs");

function readFixture(envVar) {
  const path = process.env[envVar];
  if (!path) throw new Error(`${envVar} not set`);
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

const fixturePreviews = readFixture("HERBIER_FIXTURE_READDIR_PREVIEWS");
const fixtureRefthumbs = readFixture("HERBIER_FIXTURE_READDIR_REFTHUMBS");

globalThis.__fixture_readdir_previews_json = JSON.stringify(fixturePreviews);
globalThis.__fixture_readdir_refthumbs_json = JSON.stringify(fixtureRefthumbs);

globalThis.__last_call_json = "null";
globalThis.__next_readdir_json = null;
globalThis.__next_readdir_error = null;
globalThis.__readdir_tree_json = null;
globalThis.__next_rmdir_error = null;

function recordCall(name, args) {
  globalThis.__last_call_json = JSON.stringify([name, args]);
}

function rejectWith(payload) {
  const err = new Error(payload.message || "");
  if (payload.code) err.code = payload.code;
  return Promise.reject(err);
}

const filesystem = {
  readdir(args) {
    recordCall("readdir", args);
    if (globalThis.__next_readdir_error) {
      return rejectWith(JSON.parse(globalThis.__next_readdir_error));
    }
    if (globalThis.__next_readdir_json) {
      return Promise.resolve(JSON.parse(globalThis.__next_readdir_json));
    }
    if (globalThis.__readdir_tree_json) {
      const listing = JSON.parse(globalThis.__readdir_tree_json)[args.path];
      if (listing === undefined) {
        return rejectWith(readFixture("HERBIER_FIXTURE_READDIR_MISSING"));
      }
      if (listing.reject) return rejectWith(listing.reject);
      return Promise.resolve(listing);
    }
    switch (args.path) {
      case "previews":
        return Promise.resolve(fixturePreviews);
      case "refthumbs":
        return Promise.resolve(fixtureRefthumbs);
      case "nope":
        return rejectWith(readFixture("HERBIER_FIXTURE_READDIR_MISSING"));
      default:
        return Promise.reject(
          new Error(`filesystem_stub: unexpected path ${args.path}`),
        );
    }
  },
  rmdir(args) {
    recordCall("rmdir", args);
    if (globalThis.__next_rmdir_error) {
      return rejectWith(JSON.parse(globalThis.__next_rmdir_error));
    }
    if (args.path === "nope") {
      return rejectWith(readFixture("HERBIER_FIXTURE_READDIR_MISSING"));
    }
    return Promise.resolve();
  },
};

globalThis.herbier = { filesystem };
