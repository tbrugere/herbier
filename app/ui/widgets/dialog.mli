(** A centred confirmation over a veil. Hidden until {!t.show}, which moves the
    focus to the first button; a choice hides it. *)

type 'a t = {
  el : Brr.El.t;  (** put it anywhere in the screen: it is [position: fixed] *)
  show : unit -> unit;
  show_only : ('a -> bool) -> unit;
      (** {!show} with only the buttons whose value satisfies the predicate *)
  choice : 'a React.event;  (** the value of the button pressed *)
  bindings : Rb.binding list;
}

val v :
  title:string ->
  ?text:string ->
  ?body:Brr.El.t list ->
  (Button.kind * string * 'a) list ->
  'a t
(** Buttons stacked in the list's order, each with the value {!t.choice} gives
    when it is pressed; [text] is a line under the title, the dialog's
    [aria-describedby] (a fresh id); [body]: elements placed after [text] and
    before the buttons (default [[]]), not part of the description, so its lists
    and paragraphs stay navigable. The box scrolls when taller than the
    viewport. *)
