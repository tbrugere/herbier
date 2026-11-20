(** Dev builds only: what the app exposes on [globalThis.herbierDev] for a
    DevTools console or a test driver. Linked only when [app/dev_pages.ml] calls
    it, which a release build does not. *)

val install : unit -> unit
(** Sets [herbierDev.live()], the number of bindings not released ({!Rb.live}):
    the leak check; and [herbierDev.geocodeRequests()], {!geocode_requests} as
    ["<provider> <url>"] strings ([Geocode.request_to_string]): the "no request
    leaves the phone" check; and [herbierDev.transitions()], every route
    transition run since then, oldest first, as {!Transition.record_to_string}
    gives it. Call it once, at startup. *)

val geocode_requests : unit -> Herbier_geo.Geocode.request list
(** Every geocode request started since {!install} ([Geocoder.observe]), oldest
    first. Never cleared: dev builds only. *)

val install_app : App.t -> unit
(** Sets [herbierDev.markOriginal(state)], [state] ["uploaded"] or
    ["original_missing"]: {!Drive_check.mark_original} on the newest live
    Drive-bound photo, its outcome a console line (so 4e and 5e can be checked
    live while open). Called once, by [Dev_pages.find], with the app.

    Also « Toute la France »: [herbierDev.downloadFrance(codes)] ([codes]
    comma-separated, spaces ignored, an invalid code logged and dropped, [""]
    the whole list) runs {!App.france_plan} then {!App.download_france} without
    confirmation, the outcome one console line [france: …];
    [herbierDev.cancelFrance()] is {!App.cancel_france};
    [herbierDev.franceState()] is one string: [idle], [deleting], [starting],
    [running 37/101 <bytes> <name>], [retrying 2/3 20000],
    [complete <n> <bytes> failed=<codes>], [cancelled 37/101],
    [stopped 37/101 <error>] (a cancel asked adds [ cancelling] to the running
    ones); [herbierDev.packSizes()] is ["<code> <size_bytes>"] per pack in code
    order (the same measure as {!Herbier_geo.France_sizes.table}: the stored
    size per pack). *)
