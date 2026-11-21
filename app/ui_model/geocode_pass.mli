(** The geocoding pass's work list and its decisions after a save (architecture
    §8), kept apart from the Brr/Fut runner ([ui/app/geocoding.ml]) so each
    outcome is tested natively. *)

module Observation = Herbier_domain.Observation
module Places = Herbier_domain.Places

type job =
  | Name  (** store a name on an unnamed observation *)
  | Rename of {was : string}
      (** rename one named before the commune-first rule; [was] is its
          [place_derived] as read, matched exactly by the guarded rename *)

type item = {o : Observation.t; p : Places.point; kind : job}

val items :
  to_geocode:Observation.t list -> to_rename:Observation.t list -> item list
(** The unnamed observations, then the ones to rename, each with its position
    ([None] position or, for a rename, [None] name: left out). *)

val yields : item -> again:bool -> bool
(** [true] when the pass should end before this item so that a new run starts at
    once: a [Rename] while another run was asked for ([again]), so newly pending
    observations are named before the one-off rename backlog. A [Name] never
    yields. *)

type after_save = {
  outcome : string;  (** ["named"], ["renamed"] or ["unchanged"], for the log *)
  mark_tried : bool;  (** remote sources are not asked again at this position *)
  forget : bool;  (** the rename marker is deleted *)
}

val after_save : job -> changes:int -> after_save
(** What follows a committed name or rename that changed [changes] rows:
    - [Name], 0 (moved, named or deleted meanwhile): unchanged, mark tried;
    - [Name], more: named;
    - [Rename], 0 (already right, moved, labelled or deleted): unchanged,
      forget;
    - [Rename], more: renamed, forget.

    A rename that resolves to nothing, is deferred or fails keeps its marker:
    the runner never calls this then. *)
