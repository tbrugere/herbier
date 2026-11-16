(** Runs a {!Herbier_ui_model.Motion.kind} around one route change. *)

val mark_hero : Brr.El.t -> Herbier_domain.Ids.Plant_id.t -> unit
(** Marks [el] as plant [id]'s hero end ([data-hero="<uuid>"]): 4a's card, 4f's
    hero. The name ([data-hero-named], which gives [view-transition-name: hero])
    is set only during a hero transition, on one element per state, then
    removed. *)

val run :
  Herbier_ui_model.Motion.kind ->
  root:Brr.El.t ->
  commit:(unit -> Screen.t) ->
  unit
(** [commit] performs the change (the router's [send]) and returns the screen
    now shown. With [Motion.how ~supported ~reduced] ([supported] is
    [View_transition.supported ()], [reduced] is the media query
    [(prefers-reduced-motion: reduce)]):
    - [Now]: [commit ()] at once.
    - [Css_fade]: [commit ()] at once, then class [motion-fade-in] on the new
      screen's [el].
    - [View]: for a hero kind, the old end ([data-hero] = id inside [root],
      {!Herbier_ui_model.Motion.in_view} against [window.innerHeight]) is named
      before the start; when it is missing the kind becomes
      [Motion.without_hero]. Sets [data-motion] on [<html>] to its
      [Motion.attribute], then starts a view transition whose update calls
      [commit ()] synchronously and, for a hero kind, waits for the new screen's
      [ready] or [Motion.ready_cap_ms], whichever comes first, then clears the
      old name and names the new end when it is found and in view. When the
      transition is over, its names and [data-motion] are removed, unless a
      later run has started since (it owns them then). When the start fails
      (support vanished), falls back to [Css_fade].

    Raises what [commit] raises on [Now] and [Css_fade] (including the fallback
    when the start fails); on [View], a raising [commit] is logged and the
    transition skipped ({!Herbier_bindings.View_transition.start}). Either way
    the route stays as requested, as after a raising effect in any React step.
    Holds the screens only until the transition is over. *)

type ran =
  | Now
  | Css_fade
  | View of {
      hero_old : bool;  (** the old end was named *)
      hero_new : bool;  (** the new end was named *)
      outcome : [`Finished | `Skipped];
    }

type record = {
  kind : Herbier_ui_model.Motion.kind;  (** after any degrade *)
  ran : ran;
}
(** What one {!run} did. *)

val observe : (record -> unit) -> unit
(** Dev builds: [f] is called once per {!run}, when it ends (dev hook
    [herbierDev.transitions()]). One observer; a second call replaces it. *)

val record_to_string : record -> string
(** ["<attribute|instant> <now|fade|view> <finished|skipped|immediate>
     hero=<old>/<new>"], e.g. ["hero-in view finished hero=1/1"]. *)
