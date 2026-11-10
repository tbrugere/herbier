(** Dev-only page for {!Widgets.Sheet}: a sheet with three snap points (72, 360,
    640 px) over a list, its visible height, a header button with its click
    count, and a log of the points it settles on. Reached with the URL fragment
    [#dev/sheet]. *)

val el : unit -> Brr.El.t
