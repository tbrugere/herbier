(** Pull (architecture §4, step 2): every table's rows since its cursor, from
    the network first, then merged and written in one bare transaction, parents
    first, cursors included. Pure (a functor over the HTTP and the store). *)

type table_report = {
  table : string;
  fetched : int;  (** rows received, duplicates included *)
  inserted : int;
  replaced : int;
  unchanged : int;
  kept_local : int;
  repeated : bool;  (** an id came twice: the cursor was not moved *)
  cursor : Ptime.t option;
      (** after the pull; unchanged when [fetched = 0] or [repeated] *)
}
[@@deriving eq, show]

type report = table_report list [@@deriving eq, show]
(** In {!Synced.all} order. *)

type t = Done of report | Stopped of Outcome.stop [@@deriving eq, show]

val writes : report -> int
(** [inserted + replaced] over every table: did the pull change the store. *)

module Make (H : Net.Rest.HTTP) (L : Local.S with module IO = H.IO) : sig
  val run :
    L.t ->
    conn:(unit -> (Postgrest.Client.conn, Outcome.stop) result H.IO.t) ->
    t H.IO.t
  (** 1. [Sync_state.all] (store error → [Stopped (Store _)]). 2. Per table in
      {!Synced.all} order, [since] = its cursor (absent → [None]): pages 0, 1, …
      of [Net.Rest.select_since] ([conn ()] before each) until a page has fewer
      than {!Net.Rest.page_size} rows. Any error → [Stopped] (mapped as in
      {!Push}; another 4xx → [Rejected]), nothing written, no cursor moved. 3.
      One [L.bare_transaction]; per table in order, when it fetched rows: rows
      de-duplicated by id keeping the last occurrence ([repeated] when any id
      came twice); per chunk of ≤ {!Herbier_store.Stmt.max_ids} ids,
      [Synced.local]; [Outbox.pending_ids]; per row in server order
      [Synced.decide ~pending ~local]: [Insert] / [Replace] →
      [L.Tx.write (Synced.write t row)]; [Unchanged] / [Keep_local] → nothing.
      Then, unless [repeated], [Sync_state.set] to the greatest [updated_at]
      fetched for the table. The pull never reads back its own writes. 4. A
      failed transaction (a row's constraint, a foreign key checked before the
      commit) → [Stopped (Store _)]: everything rolled back, cursors included;
      the next cycle retries.

      Never raises. Every table's rows are held in memory, which is fine for one
      user's collection. *)
end
