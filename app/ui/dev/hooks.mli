(** Dev builds only: what the app exposes on [globalThis.herbierDev] for a
    DevTools console or a test driver. Linked only when [app/dev_pages.ml] calls
    it, which a release build does not. *)

val install : unit -> unit
(** Sets [herbierDev.live()], the number of bindings not released ({!Rb.live}):
    the leak check. *)
