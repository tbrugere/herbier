(** The global « hors-ligne · N en attente » strip (handoff « Hors-ligne :
    bandeau discret dans la barre d'état »), outside every screen so it survives
    route changes. *)

val mount : App.t -> route:Route.t React.signal -> unit
(** Once, after the network is watched, with [route] the route shown
    ({!Router.start}'s): appends to [document.body] a [div.offline-banner]
    ([role="status"], [aria-live="polite"]) showing
    {!Herbier_ui_model.Network_text.banner} of {!State.network}, its count
    {!Herbier_ui_model.Drive_text.pending_count} of {!App.upload_queue}. It is
    hidden (the [hidden] attribute) when that is [None], on [Modal Record] (4d
    shows the same text as its pill) and on [Dev _] pages; while it shows,
    [document.documentElement] carries [data-offline] (the screens' top
    padding). Its bindings are held for the app's lifetime. Never raises. *)
