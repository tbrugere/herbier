(** A press that is a tap or a long-press. Pure: the DOM side
    ({!Herbier_ui.Long_press}) feeds it pointer events and the timer it asks
    for. *)

val hold_ms : int
(** 500 *)

val slop_px : float
(** 10.: a move farther than this from the press point (Euclidean) is not a
    hold. *)

type t

val idle : t

type input =
  | Down of {x : float; y : float}  (** primary pointer down *)
  | Move of {x : float; y : float}
  | Up
  | Cancel  (** pointercancel (a scroll took the gesture) *)
  | Elapsed of int  (** the timer armed with that token fired *)
  | Click  (** the element's [click] after a pointer press *)
  | Activate
      (** a [click] with no pointer behind it ([detail = 0]: the keyboard,
          assistive technology) *)

type output =
  | Nothing
  | Arm of int  (** start a [hold_ms] timer that sends [Elapsed token] *)
  | Long  (** the hold elapsed before the lift *)
  | Tap
      (** a click that ended no long-press and did not come while the pointer
          was still down after a move beyond [slop_px]; a press moved beyond
          [slop_px] and then lifted is still a tap at its click (the slop only
          cancels the hold) *)

val step : t -> input -> t * output
(** Total, never raises. Semantics:
    - [Down] from any phase → a new press with a fresh token (strictly greater
      than every earlier one) and [Arm token].
    - pressed: [Move] within [slop_px] → [Nothing]; beyond → moved (no hold);
      [Elapsed token] of the current press → fired, [Long]; [Elapsed] of another
      token → [Nothing]; [Up] → released; [Cancel] → idle; [Click] → idle,
      [Tap].
    - moved: [Elapsed _] → [Nothing]; [Up] → released; [Cancel] → idle; [Click]
      → idle, [Nothing].
    - released: [Click] → idle, [Tap]; [Elapsed _] → [Nothing].
    - fired: [Up] → swallowing; [Cancel] → idle; [Click] → idle, [Nothing].
    - swallowing (after a long-press): [Click] → idle, [Nothing] (the click that
      follows the lift is not a tap).
    - idle: [Click] → [Tap] (a click with no pointer press seen); everything
      else but [Down] and [Activate] → [Nothing].
    - [Activate] from any phase → idle, [Tap]: a long-press whose lift no click
      followed (Android) leaves the machine swallowing, and a keyboard or
      assistive activation must not be the click it waits for. *)
