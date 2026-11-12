(** 4i's « Référence · GBIF » section, shared by every mode of
    [screens/resolve.ml]: GBIF's species search over the screen's search field,
    driven by {!Ref_search} (300 ms debounce, stale answers dropped, offline
    state, « Réessayer »), and one row per candidate with the button
    {!Ref_pick.action} gives it.

    The section follows {!State.network}: offline, the search stops and the
    rows' « + » are inactive; back online, it searches again without typing. Its
    timer is stopped and late answers are ignored once its bindings are
    released. *)

type t = {
  el : Brr.El.t;
  status : Ref_search.status React.signal;
      (** For the screen's own state: 4i's « Créer avec un nom libre » shows
          while [Offline] or [Failed]. *)
  bindings : Rb.binding list;
}

val v :
  App.t ->
  mode:Ref_pick.mode ->
  current:Herbier_domain.Ids.Plant_id.t option ->
  plants:Herbier_domain.Plant.t list ->
  query:string React.signal ->
  pick:(Ref_pick.action -> Herbier_refs.Resolve.Candidate.t -> unit) ->
  t
(** [query] is the search field's text: its value now is the prefilled query,
    searched at once. [plants] are the live plants {!Ref_pick.action} looks at.
    [pick] is called outside any update step with the row's action (never
    [Inert]) and its candidate; a [Create] or [Link_this] row only while online.
*)
