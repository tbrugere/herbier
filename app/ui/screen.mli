(** What a screen hands the router: its root element and every binding it
    created. The router keeps the list reachable while the screen is shown (see
    {!Rb}) and releases it when the screen is left. *)

type t = {el : Brr.El.t; bindings : Rb.binding list}
