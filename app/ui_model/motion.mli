(** How the app moves from one screen to the next (handoff « Interactions »:
    modals from the bottom, 300 ms decelerate; the fiche's hero shared from its
    Collection card, 350 ms; tabs without animation; a plain fade where the View
    Transitions API is missing, stack.md). Pure: the router classifies its
    routes into {!place}s and [Herbier_ui.Transition] runs the result. *)

type place =
  | Collection  (** the 4a tab *)
  | Tab  (** any other tab: 4b, 4c, 4m *)
  | Fiche of Herbier_domain.Ids.Plant_id.t  (** 4f/4g of that plant *)
  | Modal  (** any other modal route *)
  | Dev  (** a [#dev/*] page *)

type direction =
  | Forward  (** a new history entry (Route.go) or a forward traversal *)
  | Back  (** a backward traversal (←, Android back, history.back) *)
  | Replace  (** the current entry replaced (Route.replace, tab presses) *)
  | Unknown  (** no Navigation API index on one side *)
[@@deriving eq]

val direction : before:int option -> after:int option -> direction
(** From [navigation.currentEntry.index] before and after the change: after >
    before → [Forward], after < before → [Back] (any distance), equal →
    [Replace], either [None] → [Unknown]. *)

type kind =
  | Instant
  | Fade
  | Modal_in
  | Modal_out
  | Hero_in of Herbier_domain.Ids.Plant_id.t
  | Hero_out of Herbier_domain.Ids.Plant_id.t
[@@deriving eq]

val kind : from:place -> to_:place -> direction -> kind
(** Rules, first match wins:
    + [Dev] on either side → [Instant].
    + tab to tab ([Collection] or [Tab] on both sides) → [Instant].
    + [Collection] → [Fiche p]: [Back] → [Fade], else [Hero_in p].
    + [Fiche p] → [Collection]: [Hero_out p] in every direction (← or Android
      back from the fiche gives [Back], [Unknown] without the Navigation API; a
      missing card degrades at run time, {!without_hero}).
    + tab ([Collection] or [Tab]) → [Modal] or [Fiche _]: [Back] → [Fade], else
      [Modal_in].
    + [Modal] or [Fiche _] → tab: [Modal_out].
    + modal to modal ([Modal] or [Fiche _] on both sides): [Forward] →
      [Modal_in], [Back] → [Modal_out], [Replace] and [Unknown] → [Fade]. *)

val without_hero : kind -> kind
(** [Hero_in _] → [Modal_in], [Hero_out _] → [Modal_out], any other kind
    unchanged: what runs when the old end of the shared hero is missing. *)

type how =
  | Now  (** swap with no animation *)
  | Css_fade  (** swap, then the new screen fades in (CSS class) *)
  | View  (** through [document.startViewTransition] *)
[@@deriving eq]

val how : supported:bool -> reduced:bool -> kind -> how
(** [reduced] (prefers-reduced-motion) → [Now] for every kind; [Instant] →
    [Now]; not [supported] → [Css_fade] for every other kind; else [View]. *)

val attribute : kind -> string option
(** The [data-motion] value on [<html>] that selects the CSS of a [View]: [Fade]
    ["fade"], [Modal_in] ["modal-in"], [Modal_out] ["modal-out"], [Hero_in _]
    ["hero-in"], [Hero_out _] ["hero-out"]; [Instant] [None]. *)

val hero : kind -> Herbier_domain.Ids.Plant_id.t option
(** The plant of [Hero_in] and [Hero_out]; [None] otherwise. *)

val ready_cap_ms : int
(** 300: the longest a hero transition waits for the new screen's content (the
    [ready] of [Herbier_ui.Screen.t]) before its new state is captured. *)

val in_view : viewport_height:float -> top:float -> bottom:float -> bool
(** An element's box (client coordinates) is at least partly on screen:
    [bottom > 0. && top < viewport_height]. A hero end outside it is not named
    (the morph would come from or go to an invisible place). *)
