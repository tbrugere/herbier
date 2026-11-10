(** Dev-only page for {!Widgets.Sheet}: a sheet with three snap points (72, 360,
    640 px) over a list, its visible height, a header button with its click
    count, a log of the points it settles on, and the animation frames of the
    last gesture (press to release) with how many were dropped, also in the
    [data-frames], [data-dropped] and [data-longest-ms] attributes of [#frames].
    Reached with the URL fragment [#dev/sheet]. *)

val el : unit -> Brr.El.t
