(** A pack's stored text: [Communes.to_string] and [Communes.of_string]. *)

val to_string : Pack.t -> string
val of_string : string -> (Pack.t, Geocode.error) result
