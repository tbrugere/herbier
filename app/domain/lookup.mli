(** A closed value set stored as text: a Postgres lookup table's values (style
    guide, lookup tables) and the device-only ones. From its constructors and
    their wire strings, the reading back and the JSON codecs. *)

module type Values = sig
  type t

  val all : t list
  (** Every constructor, once each. *)

  val to_string : t -> string
  (** The wire string, one per constructor. *)
end

module Make (V : Values) : sig
  val of_string : string -> V.t option
  (** The constructor of [all] whose [to_string] is exactly the string; [None]
      for any other string. *)

  val to_json : V.t -> Yojson.Safe.t
  (** The JSON string [to_string t]: the column value as PostgREST sends and
      receives it. *)

  val of_json : Yojson.Safe.t -> V.t option
  (** [of_string] of a JSON string; [None] for any other JSON value. *)
end
