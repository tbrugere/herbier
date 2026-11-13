(** A 4m card row: a title over a meta line, then [trailing] (a button) when
    given. *)

val v : ?trailing:Brr.El.t -> title:string -> detail:string -> unit -> Brr.El.t
