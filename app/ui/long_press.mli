(** {!Herbier_ui_model.Long_press} on an element: pointer listeners and the
    timer. Replaces {!Rb.click} on an element that also has a long-press. *)

type t = {
  tap : unit React.event;
      (** a click that ended no long-press and did not come while the pointer
          was still down after a move beyond
          {!Herbier_ui_model.Long_press.slop_px} (a moved press, once lifted, is
          still a tap at its click), or any keyboard or assistive activation *)
  long : unit React.event;
      (** fires once, [hold_ms] after a still press, before the lift *)
  bindings : Rb.binding list;
}

val v : Brr.El.t -> t
(** Listens to [pointerdown] (primary pointer only), [pointermove], [pointerup],
    [pointercancel], [click] (a [detail] of 0 is
    {!Herbier_ui_model.Long_press.Activate}), and [contextmenu] (prevented, so
    Android's long-press menu / text selection does not show); a [touchend] that
    lifts a fired long-press is prevented, so no mouse events nor click follow
    it onto what the long-press opened. Events are sent from the DOM listeners
    or the timer, outside update steps. Releasing the bindings removes the
    listeners and clears a pending timer. Never raises. *)

val optional : bool -> Brr.El.t -> t
(** [optional true el] is [v el]; [optional false el] has {!Rb.click}'s click as
    [tap] and [React.E.never] as [long]. *)
