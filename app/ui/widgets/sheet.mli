(** Bottom sheet (4b drawer, 5b, the Noter suggestions): a [paper] panel with a
    grab handle, fixed to the bottom of the screen, dragged vertically between
    snap points. The drag is a [float] signal (the visible height) bound to
    [transform: translate3d], so a frame costs one style write and no layout. On
    release the sheet settles, with a 300 ms decelerating transition, on the
    snap point nearest to where the gesture was heading. Touch and pointer only:
    there is no keyboard path between snap points. *)

type t = {
  el : Brr.El.t;  (** the sheet; place it once, e.g. in a screen's root *)
  visible : float React.signal;  (** visible height in px; follows the finger *)
  settled : int React.event;
      (** index in [snaps] of the point the sheet settles on after a drag or a
          {!snap_to}; a tap on the drag area fires nothing *)
  snap_to : int -> unit;
      (** moves to that snap point (index, clamped); call it from outside an
          update step *)
  set_snaps : float list -> unit;
      (** replaces the snap points (same rules as [v]'s [snaps]; the sheet's
          height follows) and shows the same index as before, clamped, without a
          transition. Raises [Invalid_argument], changing nothing, when they are
          invalid. Call it from outside an update step. *)
  bindings : Rb.binding list;
}

val v :
  snaps:float list ->
  ?start:int ->
  header:Brr.El.t list ->
  body:Brr.El.t list ->
  unit ->
  t
(** [snaps] are visible heights in px, non-empty and strictly ascending (e.g.
    [[72.; 360.; 640.]]), measured above the system's gesture area; the sheet is
    as tall as the last one. [start] is the index shown first (default 0,
    clamped). The handle and [header] are the drag area: a press that moves
    becomes a drag, a tap stays with the header's own controls. [body] scrolls
    inside the visible part of the sheet, down to its end at every snap point.

    @raise Invalid_argument if [snaps] is empty or not strictly ascending. *)
