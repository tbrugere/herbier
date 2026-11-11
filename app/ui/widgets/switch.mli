(** A settings row with a switch (4m « Sur le téléphone »): a label, an optional
    detail line, and the track on the right ([moss] when on). The whole row is
    the [role="switch"] button. *)

type t = {
  el : Brr.El.t;
  toggle : unit React.event;  (** a tap; the screen decides the new value *)
  bindings : Rb.binding list;
}

val v :
  ?detail:string ->
  ?disabled:bool ->
  label:string ->
  bool React.signal ->
  unit ->
  t
(** [disabled] (default false): the track at half opacity, the text left
    readable; taps ignored. *)
