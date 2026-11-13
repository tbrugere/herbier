(** Push (architecture §4, step 1): every unparked outbox entry, oldest first,
    one upsert each. Pure (a functor over the HTTP and the store). *)

type report = {pushed : int; parked : int} [@@deriving eq, show]

type t = Done of report | Stopped of report * Outcome.stop
[@@deriving eq, show]

module Make (H : Net.Rest.HTTP) (L : Local.S with module IO = H.IO) : sig
  val run :
    L.t ->
    conn:(unit -> (Postgrest.Client.conn, Outcome.stop) result H.IO.t) ->
    t H.IO.t
  (** Loop: read [Outbox.next ~limit:1]; none → [Done]. An entry that
      {!Synced.decode_entry} refuses is parked with [Last_error.Invalid] and
      {!Synced.entry_error_to_string}, without calling [conn] or sending
      anything, and the loop goes on. Else [conn ()] (once per request: the
      token is awaited per request) — [Error s] → [Stopped s], nothing written;
      then the upsert of the entry's row ([Net.Rest.upsert]):
      - [Ok ()] → [Outbox.delete seq], [pushed + 1], loop;
      - [Rejected status] →
        [Outbox.park seq ~error:(Last_error.to_string (Rejected status))],
        [parked + 1], loop (its children then fail on their foreign key and are
        parked in turn);
      - any other error → [Stopped] with {!Io.Make.stop_of_error}. The entry is
        left as it was (not parked, [attempts] unchanged).

      A store error at any point → [Stopped (Store (L.error_to_string e))]. The
      next entry is re-read after every delete or park, so no [seq] is held
      across a delete (outbox.mli). Never raises. *)
end
