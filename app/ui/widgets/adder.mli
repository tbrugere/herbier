(** The dashed « + tag » / « + alias » pill (4f, 5a). A tap turns it into a
    small text input; Enter or leaving the input adds the trimmed text (when not
    blank) and turns it back into the pill; Escape cancels. *)

type t = {
  el : Brr.El.t;
  added : string React.event;  (** the trimmed, non-blank text *)
  bindings : Rb.binding list;
}

val v : label:string -> placeholder:string -> unit -> t
(** [label] without the « + »: [v ~label:"tag"] shows « + tag ». *)
