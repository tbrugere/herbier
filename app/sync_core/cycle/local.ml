(** The local store as push and pull use it: {!Herbier_store_io.Db} on the
    device (in {!Engine}, which includes [Db] as is), the sqlite3 CLI in
    test/sync. The names are [Db]'s. *)

module type S = sig
  module IO : Postgrest.Client.IO

  type t
  type error

  val error_to_string : error -> string
  val all : t -> 'a Herbier_store.Stmt.query -> ('a list, error) result IO.t
  val write : t -> Herbier_store.Stmt.t -> (int, error) result IO.t

  type tx

  val bare_transaction :
    t -> (tx -> ('a, error) result IO.t) -> ('a, error) result IO.t
  (** {!Herbier_store_io.Db.bare_transaction}'s contract: atomic, foreign keys
      checked at the end, rolled back on any error. *)

  module Tx : sig
    val all : tx -> 'a Herbier_store.Stmt.query -> ('a list, error) result IO.t
    val write : tx -> Herbier_store.Outbox.bare -> (int, error) result IO.t
    val write_local : tx -> Herbier_store.Stmt.t -> (int, error) result IO.t
  end
end
