(** The reference fetch of one plant (architecture §6): the three
    {!Herbier_refs.Fanout.branches} run concurrently through {!Http.run}; each
    branch, when done, is decided against the rows stored before the fetch and
    stored in one save, so a branch that fails or is slow never holds the others
    back nor blanks their rows. *)

module Reference := Herbier_domain.Reference
module Db := Herbier_store_io.Db

type outcome =
  | Written of Reference.Status.t  (** The row was stored with that status. *)
  | Kept
      (** The fetch's row was [Failed] and a live row was already stored: that
          row is left unchanged. *)
  | Skipped  (** The save was refused by the caller (superseded). *)
  | Not_fetched
      (** No row came back for the source: its branch raised (a bug, logged to
          the console as [refs: branch raised]). *)
  | Not_saved of Db.error  (** The branch's save failed (rolled back). *)

type report = (Reference.Source.t * outcome) list
(** One entry per source of {!Herbier_refs.Fanout.sources}, in that order. *)

val outcome_to_string : outcome -> string
(** ["complete"], ["partial"], ["missing"], ["failed"] for [Written], then
    ["kept"], ["skipped"], ["not fetched"], ["not saved: <error>"]. *)

val fetch :
  ?on_branch:(report -> unit) ->
  Db.t ->
  save:(Herbier_store.Outbox.edit list -> (int, Db.error) result Fut.t option) ->
  plant:Herbier_domain.Ids.Plant_id.t ->
  gbif_key:int ->
  (report, Db.error) result Fut.t
(** Reads the plant's live rows ([References.of_plant]); an error there is
    [Error] and nothing is fetched. Then runs the branches; for each finished
    branch: [Fanout.decide ~previous] on its rows, one
    [References.put ~plant ~source ~fetched_at:now ~payload ~status ~at:now] per
    kept row ([now] = [Ptime_clock.now ()] when the branch finished), all of a
    branch passed to [save] in one call. [save] returning [None] means
    "superseded, do not write": those sources are [Skipped]. A branch with
    nothing to store calls no [save]. Resolves once every branch settled, even
    when a program or [decide] raises (that branch's sources are [Not_fetched]).

    [on_branch] (default: nothing) is called once per branch, after its save
    settled (or was skipped, or was not needed), with that branch's entries only
    (in its sources' order; [[]] for a branch that raised), before the final
    result: the caller can act on Pl@ntNet's row without waiting for the slowest
    branch. An exception it raises is caught and logged to the console
    ([refs: on_branch raised]), never propagated. Never raises. *)
