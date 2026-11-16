(** Dev builds only: functions exposed on [globalThis.herbierDev] so a DevTools
    console or a test driver (Playwright, [scripts/webview.mjs]) can read the
    app's internals, e.g. [herbierDev.live()]; and readers of the browser's own
    diagnostics (JS heap, garbage collector) for the dev pages. *)

val export_int : string -> (unit -> int) -> unit
(** [export_int name f] sets [globalThis.herbierDev[name]] to a JS function
    returning [f ()]. *)

val export_strings : string -> (unit -> string list) -> unit
(** [export_strings name f] sets [globalThis.herbierDev[name]] to a JS function
    returning [f ()] as an array of strings. *)

val export_action : string -> (string -> unit) -> unit
(** [export_action name f] sets [globalThis.herbierDev[name]] to a JS function
    of one argument calling [f] with it as a string ([""] when absent or
    [null]); it returns [undefined]. *)

val heap_used : unit -> float option
(** [performance.memory.usedJSHeapSize] in bytes, where the browser has it
    (Chromium and the Android WebView); [None] elsewhere. Precise only in a
    renderer locked to one site, as desktop Chromium's are; in any other,
    Chromium rounds it to coarse buckets and caches it for twenty minutes, so
    two readings a few seconds apart are equal whatever happened. The Android
    WebView is not expected to be site-locked: read its heap over the DevTools
    Protocol instead ([scripts/webview.mjs heap]). *)

val collect_garbage : unit -> bool
(** Runs a full garbage collection through [globalThis.gc] when the engine
    exposes it (Chromium started with [--js-flags=--expose-gc]); [false], and
    nothing done, otherwise. *)
