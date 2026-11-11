(** Pinch zoom of one 5e photo, imperative: pointer events on the box write the
    content's [transform] directly ({!Zoom} does the geometry), no signal per
    frame. Two fingers pinch about their midpoint and pan with it, and a pinch
    left under ×1.01 settles back to ×1; one finger pans while zoomed; a double
    tap toggles ×2.5 at that point. A tap is one finger, lifted within 250 ms
    and 10 px of where it went down: a pan, a pinch or a swipe the browser takes
    ([pointercancel]) never counts. While zoomed the box has
    [touch-action: none] and the class [is-zoomed], so the photo track's
    horizontal swipe is off. *)

type t = {
  el : Brr.El.t;  (** the box, holding [content] *)
  reset : unit -> unit;  (** back to ×1 (when the photo leaves the screen) *)
  bindings : Rb.binding list;
}

val v : Brr.El.t -> t
