(** Dev-only gallery of the shared widgets: one fixture entry per widget and
    state, with a log of the events they fire. Chips toggle and the tab bar
    follows the pressed tab, as a screen would wire them. The two mini-maps (a
    30 m accuracy circle, then none) log their taps. Reached with the URL
    fragment [#dev/gallery]. *)

val el : unit -> Brr.El.t
