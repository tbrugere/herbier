(** Dev-only page for {!Rb}: a self-check printing ok/FAIL per check on load,
    then interactive bindings with buttons to release the display and its
    sources. Reached with the URL fragment [#dev/rb]. *)

val el : unit -> Brr.El.t
