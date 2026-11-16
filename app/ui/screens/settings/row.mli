(** A 4m card row: a title over a meta line, then [below] (a link) under them
    and [trailing] (a button) beside them when given. *)

val v :
  ?below:Brr.El.t ->
  ?trailing:Brr.El.t ->
  title:string ->
  detail:string ->
  unit ->
  Brr.El.t
