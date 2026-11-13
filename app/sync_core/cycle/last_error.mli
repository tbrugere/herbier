(** What a parked outbox entry's [last_error] says, written by {!Push} and read
    back by 4m (ui_model/parked_entry.ml). Pure. *)

type t =
  | Rejected of int  (** the server answered this 4xx *)
  | Invalid of string
      (** the entry cannot be sent: unknown table, undecodable payload *)
  | Other of string  (** any other text, kept as is *)
[@@deriving eq, show]

val to_string : t -> string
(** [Rejected n] → ["HTTP <n>"]; [Invalid why] → ["invalid entry: <why>"];
    [Other s] → [s]. *)

val of_string : string -> t
(** Inverse of {!to_string} on its outputs; any other text → [Other]. An [Other]
    text that looks like one of the two other shapes reads back as that shape.
    Never raises. *)
