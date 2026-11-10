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

val rlist : Brr.El.t -> ('a -> Brr.El.t) -> 'a ReactiveData.RList.t -> binding
(** [rlist el f l] keeps [el]'s child nodes equal to [List.map f] of [l],
    applying each patch to the DOM: an insert or an update calls [f] on that
    item only and the other children are left as they are; a [Set] rebuilds them
    all. [f] may return a text node, and must build static nodes: a binding made
    inside a row is not part of this one and is not released with it. [el] must
    hold nothing else. An out-of-range patch never reaches the binding
    (ReactiveData raises first); a step that no longer fits [el]'s child nodes,
    because something else added or removed some, logs a warning and rebuilds
    the children from the list's value. Releasing the binding also stops the
    list itself unless it is anchored (see {!release}). *)

val ev : Brr.El.t -> 'a Brr.Ev.type' -> 'a Brr.Ev.t React.event * binding
(** [ev el type'] is an event fired by each DOM event [type'] on [el], outside
    any update step as long as the browser dispatches [type'] asynchronously.
    Not for events a DOM write can fire synchronously ([blur] or [focusout] when
    a binding removes a focused element, [focus] from a [.focus()] call): those
    would fire inside the step that made the write, and react raises. Releasing
    the binding removes the listener and stops the event. *)

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
