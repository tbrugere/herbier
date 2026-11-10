(** The bottom tab bar (4a, 4b, 4c, 4m): four tabs with an icon above a 12 px
    label, and the round [moss] "Noter" button raised in the middle. *)

type tab = Collection | Map | Journal | Settings

val equal : tab -> tab -> bool

type t = {
  el : Brr.El.t;  (** a [nav] *)
  select : tab React.event;  (** a tab was pressed, even the active one *)
  record : unit React.event;  (** the "Noter" button was pressed *)
  bindings : Rb.binding list;
}

val v : active:tab React.signal -> t
(** The bar only shows [active]; the router decides what a press changes. *)

val label : tab -> string
(** ["Collection"], ["Carte"], ["Journal"], ["Réglages"]. *)
