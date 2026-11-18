(** The [sand] text field (4a search bar, 4i search, 5a name): an optional
    leading icon, the input, and an optional trailing action in [moss]
    (["Coller un lien"]), and an optional trailing element (4d's Identifier
    button). *)

type t = {
  el : Brr.El.t;
  input : Brr.El.t;  (** the [input] itself, to focus it *)
  value : string React.signal;  (** the text, updated on each [input] event *)
  action : unit React.event;  (** the trailing action; never without one *)
  set : string -> unit;
      (** replaces the text (a tapped suggestion); call it outside update steps
      *)
  bindings : Rb.binding list;
}

val v :
  ?icon:Icon.t ->
  ?action:string ->
  ?trailing:Brr.El.t ->
  ?value:string ->
  placeholder:string ->
  unit ->
  t
(** [value] is the initial text (default empty). [trailing] is appended inside
    the field after the input (and after [action]'s button when both are given);
    its events are the caller's. *)
