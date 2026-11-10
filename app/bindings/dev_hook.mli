(** Dev builds only: functions exposed on [globalThis.herbierDev] so a DevTools
    console or a test driver (Playwright, [scripts/webview.mjs]) can read the
    app's internals, e.g. [herbierDev.live()]. *)

val export_int : string -> (unit -> int) -> unit
(** [export_int name f] sets [globalThis.herbierDev[name]] to a JS function
    returning [f ()]. *)
