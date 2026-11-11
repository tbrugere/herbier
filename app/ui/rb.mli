(** react ↔ Brr glue (ocaml-react primer §5–6b). Each function binds a signal,
    an event or a reactive list to one element and returns a {!binding}; a
    screen keeps its bindings and hands them to {!release} when it is torn down.
    A source holds its dependents weakly (js_of_ocaml maps weak arrays to
    [WeakRef]), so a binding must stay reachable from the screen: one that
    nothing holds may be collected and stop updating, one that is held but never
    released keeps updating its element, and keeps it alive, for as long as its
    source lives.

    The functions given to the sources must stay pure (style guide §9.2): the
    DOM write is the binding's own effect, made inside the update step. *)

type binding
(** A stoppable DOM effect. *)

val text : Brr.El.t -> string React.signal -> binding
(** The element's children become one text node holding the signal's value,
    replaced on each change. *)

val attr : Brr.El.t -> string -> string option React.signal -> binding
(** [attr el name s]: [Some v] sets the attribute [name] to [v]; [None] removes
    it. The value is written as is: never pass an untrusted value (a share, an
    API payload, user input) to a URL attribute ([href], [src]) unless it is
    already validated, nor to any [on*] attribute. *)

val class_ : Brr.El.t -> string -> bool React.signal -> binding
(** The class is present while the signal is [true]. *)

val style : Brr.El.t -> string -> string React.signal -> binding
(** [style el prop s] sets the inline property [prop] (["transform"],
    ["--progress"]) to the signal's value; [""] removes it. *)

val children : Brr.El.t -> Brr.El.t list React.signal -> binding
(** The element's children become the signal's list, replaced wholesale on each
    change. The elements must be static: a binding made inside them is not part
    of this one and is not released with it. For a list whose items change one
    at a time, use {!rlist}. *)

val rlist :
  Brr.El.t ->
  ('a -> Brr.El.t * binding list) ->
  'a ReactiveData.RList.t ->
  binding
(** [rlist el f l] keeps [el]'s child nodes equal to the nodes of [List.map f]
    of [l], applying each patch to the DOM: an insert or an update calls [f] on
    that item only and the other children are left as they are; a [Set] rebuilds
    them all. [f] may return a text node. [el] must hold nothing else. [f] also
    returns the item's own bindings (a card's click listener): they are released
    when the item is removed or replaced, and all of them when the [rlist]
    binding is released. An out-of-range patch never reaches the binding
    (ReactiveData raises first); a patch arriving when [el]'s child nodes no
    longer match the ones the binding made, because something else added or
    removed some, logs a warning and rebuilds the children from the list's
    value. Releasing the binding also stops the list itself unless it is
    anchored (see {!release}). *)

val view :
  Brr.El.t -> ('a -> Brr.El.t * binding list) -> 'a React.signal -> binding
(** [view el f s]: [el]'s only child is [f] of the signal's value, rendered
    again on each change, the previous rendering's bindings released (an
    {!rlist} of one item). *)

val ev : Brr.El.t -> 'a Brr.Ev.type' -> 'a Brr.Ev.t React.event * binding
(** [ev el type'] is an event fired by each DOM event [type'] on [el], outside
    any update step as long as the browser dispatches [type'] asynchronously.
    Not for events a DOM write can fire synchronously ([blur] or [focusout] when
    a binding removes a focused element, [focus] from a [.focus()] call): those
    would fire inside the step that made the write, and react raises. Releasing
    the binding removes the listener and stops the event. *)

val listen : Brr.El.t -> 'a Brr.Ev.type' -> ('a Brr.Ev.t -> unit) -> binding
(** [listen el type' f] calls [f] from the DOM listener itself, outside any
    update step and with no react event in between: for per-frame input such as
    a drag, where [f] sets a primitive signal. Releasing removes the listener.
*)

val click : Brr.El.t -> unit React.event * binding
(** [click el] is [ev el Ev.click] without the DOM event, for buttons whose
    click carries nothing. *)

val on : 'a React.event -> ('a -> unit) -> binding
(** [on e f] calls [f] on each occurrence of [e], inside the update step, for an
    effect outside the reactive graph (a log, a plugin call). [f] must not set a
    primitive signal, send an event or touch an [RList] handle: those run from
    outside a step (a DOM callback, a resolved future). [f] must not raise
    either: an exception leaves the step unfinished and the other bindings of
    that occurrence unrun. A plugin call only starts its future here and handles
    the result outside the step. *)

val act : 'a React.event -> ('a -> unit) -> binding
(** [act e f] calls [f] on each occurrence of [e] once the update step is over
    (in a microtask), so [f] may set primitive signals, touch [RList] handles
    and start queries: how a screen turns a widget's event into a state change.
    Released, it stops calling [f], even for an occurrence already queued. *)

val on_release : (unit -> unit) -> binding
(** [on_release f] calls [f] once, when the binding is released: for work a
    screen must finish when it is torn down, such as saving a field still being
    edited (removing a focused element fires no [blur]). [f] may run inside an
    update step (the router releases a screen from one), so the rules of {!on}
    apply: no primitive signal set, no event sent, no exception. *)

val hold : Brr.El.t -> binding list -> unit
(** [hold el bs] keeps [bs] reachable for as long as [el] is (see the module
    doc): for bindings that live as long as an element and are never released,
    such as the app shell's. *)

val live : unit -> int
(** How many bindings exist and are not released yet, over the whole app: a leak
    check (a screen switch must bring it back to the same value). *)

val release : binding list -> unit
(** Stops every binding strongly ([S.stop ~strong:true] / [E.stop ~strong:true])
    and removes their listeners: none of them writes to the DOM or fires again.
    Releasing a binding twice is harmless. A strong stop also stops, one
    producer after another, every derived signal or event the binding read that
    is left without dependents, even one the caller still holds: that is what
    frees the screen's graph. A source that must outlive the screen is therefore
    a primitive signal ([S.create]), which is never stopped, or is held with an
    {!anchor}. A reactive list is never primitive (even [RList.create]'s holds a
    derived event), so a list that outlives the screen binding it needs
    {!anchor_list}. *)

type anchor
(** A dependent that is never released, keeping a derived source alive. *)

val anchor : 'a React.signal -> anchor
(** [anchor s] keeps [s] updating after every binding on it is released, for as
    long as the anchor is reachable: the source's owner keeps it next to [s]. *)

val anchor_list : 'a ReactiveData.RList.t -> anchor
(** [anchor_list l] is {!anchor} for a reactive list: [l]'s value keeps
    following its handle, and a later {!rlist} on it sees every patch. *)
