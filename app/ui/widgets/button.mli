(** Full-width buttons (handoff "Hauteurs"): [Primary] is filled [moss], 60 px,
    17/800 ("+ Noter ma première plante", "Valider"); [Secondary] is bordered
    [ink], 52 px, 15/700 ("Coller un lien"); [Danger] is bordered [danger]
    ("Supprimer"). Pressed: filled → [moss-dark], bordered → [sand]. *)

type kind = Primary | Secondary | Danger
type t = {el : Brr.El.t; click : unit React.event; bindings : Rb.binding list}

val v : ?kind:kind -> ?icon:Icon.t -> string -> t
(** Default [kind] is [Primary]. [icon] goes before the label. *)

val dynamic : ?kind:kind -> ?icon:Icon.t -> string React.signal -> t
(** Like {!v}, with a label that follows the signal. *)

val text : ?tone:[`Moss | `Ink | `Danger] -> string -> t
(** A bare text button for headers and links ("Terminé", "Annuler"), 15/700 (the
    neutral [`Ink] tone, « Annuler », « Retour »: 15/500 in ink-soft, as in the
    mockup's 5a), at least 44 px high. Default tone [`Moss]. *)
