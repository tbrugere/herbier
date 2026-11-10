(** Reading CSS custom properties. Brr's [El.computed_style] reads the computed
    style object by property name, which never sees a custom property
    ([--paper]); this goes through [getPropertyValue] instead. *)

val get : Brr.El.t -> string -> string
(** [get el "--name"] is the computed value of the custom property [--name] on
    [el], trimmed (the browser keeps the whitespace after the colon). [""] when
    the property is not defined. A [var(...)] reference is resolved; a value
    that is not a [var] is returned as written in the CSS. *)

val root_names : unit -> string list
(** The custom properties ([--name]) declared by the [:root] rules of the
    document's stylesheets, in declaration order. Properties set by other
    selectors or inline styles are not listed. *)
