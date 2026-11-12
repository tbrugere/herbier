(** Dev builds only: what the app exposes on [globalThis.herbierDev] for a
    DevTools console or a test driver. Linked only when [app/dev_pages.ml] calls
    it, which a release build does not. *)

val install : unit -> unit
(** Sets [herbierDev.live()], the number of bindings not released ({!Rb.live}):
    the leak check; and [herbierDev.geocodeRequests()], {!geocode_requests} as
    ["<provider> <url>"] strings ([Geocode.request_to_string]): the "no request
    leaves the phone" check. Call it once, at startup. *)

val geocode_requests : unit -> Herbier_geo.Geocode.request list
(** Every geocode request started since {!install} ([Geocoder.observe]), oldest
    first. Never cleared: dev builds only. *)
