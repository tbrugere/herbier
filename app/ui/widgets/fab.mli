(** The floating round button at the bottom right of a screen (4l's « + »): the
    look of the tab bar's « Noter » button (60 px, [moss], paper icon, its
    shadow), [position: fixed], above the gesture bar. *)

type t = {el : Brr.El.t; click : unit React.event; bindings : Rb.binding list}

val v : label:string -> Icon.t -> t
(** A [button.fab] with [aria-label = label] holding the icon at size 30. *)
