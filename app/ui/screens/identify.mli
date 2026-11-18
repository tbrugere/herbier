(** The identification layer (6b, 6c, 6f, 6g; architecture §12): a full-screen
    layer over its caller (4d, 4k, 4g, or a dev page), not a route (a route
    change would release 4d's shots). Mounted inside [host] (the caller's root
    element), so releasing the caller's element removes it; registered with
    {!Overlay}, so Android back closes it (outcome [Left]). Runs
    {!Herbier_ui_model.Identify.Layer}: every request through
    [services.identify], one per Send command, never retried. No text names
    CORS, exposing or an origin; the console line of each request is
    [services.identify]'s (App.identify logs Make's). *)

type photo = {
  image : App.image;
      (** [Preview blob]: shown through an object URL the layer creates and
          revokes at close; [Stored id]: shown by {!Widgets.Preview_img} *)
  organ : Herbier_identify.Organ.sent;
}

type services = {
  gate : Herbier_ui_model.Identify_settings.gate React.signal;
  flora : Herbier_store.Settings.flora option React.signal;
  set_flora : Herbier_store.Settings.flora option -> unit Fut.t;
      (** errors are the service's to log *)
  floras :
    key:string ->
    (Herbier_identify.Plantnet.project list, App.identify_error) result Fut.t;
  identify :
    key:string ->
    flora:string ->
    no_reject:bool ->
    (App.image * Herbier_identify.Organ.sent) list ->
    Herbier_identify.identified App.current Fut.t;
  collection :
    unit ->
    (Herbier_domain.Plant.t list * Herbier_domain.Observation.t list) Fut.t;
      (** never fails: a read error is logged and gives [([], [])] *)
}

val error_of_app : App.identify_error -> Herbier_ui_model.Identify.Failure.error
(** [Identify_offline] → [Not_sent_offline]; [Preview_unreadable _] →
    [Preview_unreadable]; [Plantnet e] → [Plantnet e]. *)

val services : App.t -> App.channel -> services
(** The app's: {!App.identify_gate}, {!App.plantnet_flora}, [set_flora] =
    {!App.set_plantnet_flora} (its [Error] already logged, ignored),
    {!App.floras}, [identify] = {!App.identify} on [channel] (which carries no
    other request while the layer is open: a superseded answer leaves the layer
    sending until ← or « Continuer sans attendre »), [collection] =
    [Db.all Plants.list] and [Db.all Observations.list] (a failure logged
    through [Log] as « identify: collection … », [[]]). *)

type t

val open_ :
  host:Brr.El.t ->
  services ->
  caller:Herbier_ui_model.Identify.Caller.t ->
  add_photo:(Herbier_identify.Organ.sent -> photo option Fut.t) ->
  on_close:(Herbier_ui_model.Identify.Layer.outcome -> photo list -> unit) ->
  photo list ->
  t
(** Appends the layer to [host], moves the focus to its ←, pushes it on
    {!Overlay}, reads [services.collection] once, and runs
    [Layer.open_ ~caller ~flora:(S.value services.flora)] on the photos' organs
    (the photos past {!Herbier_identify.Organ.max_photos} are not shown nor
    sent, and go back unchanged at the end of [on_close]'s list). Commands:
    - [Send {seq; request}]: with [Failure.of_gate (S.value services.gate)] =
      [Ok k] →
      [services.identify ~key:(Key.to_string k) ~flora:request.flora
       ~no_reject:request.no_reject] over the layer's photos zipped with
      [request.organs]; [Settled r] → [Answered {seq; result}] ([App]'s
      [Identify_offline] → [Not_sent_offline], [Preview_unreadable _] →
      [Preview_unreadable], [Plantnet e] → [Plantnet e]); [Superseded] →
      nothing. [Error e]: [Answered] at once with [Error e]; no request.
    - [Wait_slow]: a [setTimeout], then [Slow seq] (cleared at close).
    - [Take_photo o]: [add_photo o]; [Some p] → [Photo_added (Some p.organ)],
      and the photo is appended when
      {!Herbier_ui_model.Identify.Layer.accepts_photo}; [None] →
      [Photo_added None]. A photo answered after close, or not accepted, stays
      the caller's to discard.
    - [Save_flora f]: [services.set_flora f].
    - [Close outcome]: {!close}'s work, then [on_close outcome photos] with the
      layer's photos (added ones included, organs as last sent). Answers and
      photos arriving after close are dropped. [on_close] runs from a tap or
      from Android back, outside any update step, except when the outcome comes
      from {!close}, which may run inside one: then the rules of {!Rb.on} apply
      to it (no signal set, no event sent, no raise). Every re-ask control
      (organ menu, add tile, flora menu, « Voir quand même », « Réessayer ») is
      [aria-disabled] and inert, with
      {!Herbier_ui_model.Identify.Text.reask_blocked}'s line, while the gate is
      not [Ready]. A species tile or « +N » opens {!Identify_compare} over the
      layer (and gets the focus back when it closes); nothing else does. Closing
      the layer closes it. A menu (organ or flora) closes at the next event. *)

val close : t -> unit
(** As ← : outcome [Left], [on_close] called once. Idempotent; a caller calls it
    from its own release ([Rb.on_release]): it sets no signal itself, so it may
    run inside an update step as long as the caller's [on_close] sets none
    either. Releases the layer's bindings, timers and object URLs, removes its
    element, removes it from {!Overlay}. *)
