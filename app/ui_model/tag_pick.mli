(** The pure part of the tag picker (fiche « + tag », 5a « Tags »): the entries
    it lists under its field for the text typed. Names compare with
    {!Herbier_domain.Fold.fold} (case and accents folded, trimmed), so the
    picker never offers a second tag that only differs by them. *)

module Tag := Herbier_domain.Tag

type entry =
  | Pick of Tag.t  (** an existing tag, put on the plant as it is *)
  | Create of string
      (** « Créer « <text> » »: the trimmed text, a tag created then put on *)

val suggestions :
  tags:(Tag.t * int) list -> current:string list -> string -> entry list
(** [suggestions ~tags ~current text]: [tags] are the live tags with the number
    of plants carrying each, in the store's order (name, case-insensitive);
    [current] the names of the tags already on the plant.
    + A tag whose folded name is one of [current]'s is never listed.
    + Blank [text]: every other tag, most used first (ties in [tags] order), no
      [Create].
    + Otherwise the tag whose folded name equals the folded text, if listed,
      then the tags whose name {!Herbier_domain.Fold.matches} the text, most
      used first (ties in [tags] order).
    + [Create] (the trimmed text) ends the list exactly when the folded text is
      no tag's folded name, listed or not, and no name of [current]. *)

val name : entry -> string
(** The name the plant gets: the tag's, or the trimmed text. *)

val label : entry -> string
(** What the row shows: the tag's name, or [Créer « <text> »]. *)
