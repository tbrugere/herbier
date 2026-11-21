(** The [sand] text field (4a search bar, 4i search, 5a name): an optional
    leading icon, the input, and an optional trailing action in [moss]
    (["Coller un lien"]). *)

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
  ?action_enabled:bool React.signal ->
  ?label:string ->
  ?enterkeyhint:string ->
  ?value:string ->
  placeholder:string ->
  unit ->
  t
(** [value] is the initial text (default empty). [action_enabled]: the trailing
    action is [aria-disabled] while it is [false] (always enabled without it;
    ignored without [action]). [label]: the input's accessible name (default
    [placeholder]), for a field under a visible label. [enterkeyhint]: the
    keyboard's Enter key (["done"] where Enter submits). *)
