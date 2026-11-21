(** When a plant's references are fetched (architecture §6): on a creation or a
    link, on ↻, on opening the fiche when due, and when the network comes back
    for a plant whose fetch never completed. Pure; never raises. *)

module Reference := Herbier_domain.Reference

type trigger =
  | Linked  (** a plant was created linked, or linked to a taxon (committed) *)
  | Refresh  (** ↻ *)
  | Opened of Reference.t list  (** the fiche was entered; the plant's rows *)
  | Reconnected of {
      states : Reference.Fetch_state.t list;
          (** the states of the plant's live rows *)
      back_online : bool;
          (** the pass runs because the network came back (else: the app started
              online) *)
    }  (** the reconnect pass reached the plant *)

type action =
  | Fetch  (** run the three branches (then the thumbnail sync) *)
  | Sync_thumbs  (** only the thumbnail sync *)
  | Nothing

val equal_action : action -> action -> bool
val pp_action : Format.formatter -> action -> unit

val failed_retry_after : Ptime.Span.t
(** 10 minutes: how long a [Failed] row waits before {!unfinished} counts it
    again. *)

val unfinished :
  ?back_online:bool -> now:Ptime.t -> Reference.Fetch_state.t list -> bool
(** Over the states of one plant's live rows (sources outside {!Fanout.sources}
    ignored): some source of {!Fanout.sources} has no row, or its row is
    [Failed] with a [fetched_at] more than {!failed_retry_after} before [now]
    (strictly), or [Failed] at any age when [back_online] (default [false]): the
    network coming back is when a failure caused by its loss is retried.
    [Partial], [Missing] and [Complete] rows are finished (their retries are
    {!Fanout.due}'s). *)

val decide : trigger -> online:bool -> running:bool -> now:Ptime.t -> action
(** [running]: a fetch of this plant is running.
    - offline → [Nothing], whatever the trigger;
    - [Linked] → [Fetch] (even when [running]: the caller superseded it);
    - [Refresh] → [Fetch] unless [running];
    - [Opened rows] → [Nothing] when [running]; [Fetch] when
      [Fanout.due ~now rows] or {!unfinished} over their live states; else
      [Sync_thumbs];
    - [Reconnected {states; back_online}] → [Nothing] when [running]; [Fetch]
      when [unfinished ~back_online]; else [Nothing]. *)

val pending :
  back_online:bool ->
  now:Ptime.t ->
  plants:Herbier_domain.Plant.t list ->
  states:Reference.Fetch_state.t list ->
  (Herbier_domain.Ids.Plant_id.t * int) list
(** The plants a reconnect pass fetches, with their gbif_key: live
    ([deleted_at = None]), [gbif_key = Some k], and [unfinished ?back_online]
    over the [states] whose [plant_id] is theirs. Ordered by [updated_at]
    descending (the plant just created first), ties by [Plant_id.compare]
    ascending. *)
