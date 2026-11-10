(** Dev-only page for {!Rb}: a self-check printing ok/FAIL per check on load,
    then interactive bindings (a reactive list whose rows hold a binding of
    their own, an {!Rb.act} handler) with buttons to release the display and its
    sources, and {!Rb.live} updated after each button. Reached with the URL
    fragment [#dev/rb]. *)

val el : unit -> Brr.El.t
