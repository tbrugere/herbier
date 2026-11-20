(** The pure part of 4l's tag editing: one tag at a time, each change saved at
    once. Names compare with {!Plant_form.same_text} (trimmed,
    ASCII-case-folded, like the store's [collate nocase]). *)

module Tag := Herbier_domain.Tag
module Tag_id := Herbier_domain.Ids.Tag_id
module Plant_id := Herbier_domain.Ids.Plant_id

(** What the editor box is open on. *)
type editor =
  | New  (** the « + » button *)
  | Edit of {tag : Tag.t; plants : Plant_id.t list}
      (** the pencil or a long-press; [plants]: the live plants carrying it *)

type name_check =
  | Blank  (** empty once trimmed *)
  | Same  (** [Edit] only: the trimmed text is exactly the tag's own name *)
  | Taken of Tag.t
      (** another live tag has that name ({!Plant_form.same_text}); the first in
          [tags] order; never the edited tag itself *)
  | Free of string  (** the trimmed name, usable *)

val check : tags:Tag.t list -> editor -> string -> name_check
(** Order: [Blank], then [Same] (Edit, exact match with its own name), then
    [Taken] (any other tag of [tags] with a [same_text] name), else [Free]. A
    case-only change of its own name (« bois » → « Bois ») is [Free "Bois"]. *)

type primary = {
  label : string;  (** « Créer », « Enregistrer » or « Fusionner » *)
  enabled : bool;
  line : string option;  (** the line under the field *)
}

val primary : editor -> name_check -> primary
(** - [New], [Blank] → « Créer », disabled, no line
    - [New], [Taken t] → « Créer », disabled, [« <t.name> » existe déjà.]
    - [New], [Free _] → « Créer », enabled, no line
    - [Edit _], [Blank | Same] → « Enregistrer », disabled, no line
    - [Edit _], [Free _] → « Enregistrer », enabled, no line
    - [Edit {tag}], [Taken t] → « Fusionner », enabled,
      [« <t.name> » existe déjà : « <tag.name> » y sera fusionné.]

    ([New], [Same] cannot happen; answered as [Blank].) Total. *)

val title : editor -> string
(** « Nouveau tag » / « Modifier le tag ». *)

type change =
  | Create of string  (** trimmed name *)
  | Rename of {tag : Tag.t; name : string}
  | Merge of {from : Tag_id.t; into : Tag_id.t; plants : Plant_id.t list}
      (** [plants]: [from]'s *)
  | Delete of Tag_id.t

val submit : tags:Tag.t list -> editor -> string -> change option
(** The primary button's change: [None] exactly when {!primary} is disabled.
    [New] + [Free n] → [Create n]; [Edit {tag}] + [Free n] →
    [Rename {tag; name = n}]; [Edit {tag; plants}] + [Taken t] →
    [Merge {from = tag.id; into = t.id; plants}]. *)

val delete : editor -> change option
(** [Edit {tag}] → [Some (Delete tag.id)]; [New] → [None]. *)

val delete_title : Tag.t -> string
(** [Supprimer « <name> » ?] *)

val delete_text : plants:int -> string
(** n ≤ 0 → [Aucune plante ne le porte.]; n ≥ 1 →
    [Il sera retiré de <Fr_text.plural n "plante" "plantes">. Les plantes
     restent.] *)

val subtitle : (int, 'e) result -> string
(** 4l's line under its title, from the number of live tags read: an error →
    [Lecture impossible]; 0 →
    [Aucun tag pour l’instant. Touchez + pour en créer un.]; n →
    [<Fr_text.plural n "tag" "tags"> · touchez pour filtrer la collection]. *)

val edit_label : Tag.t -> string
(** The pencil's accessible name: [Modifier « <name> »]. *)

type op =
  | Insert_tag of string
      (** a new tag of that name; id and times are the caller's *)
  | Rename_tag of Tag.t * string
  | Delete_tag of Tag_id.t
  | Link of {plant : Plant_id.t; tag : Tag_id.t}
  | Unlink of {plant : Plant_id.t; tag : Tag_id.t}

val plan : change -> op list
(** [Create n] → [[Insert_tag n]]; [Rename {tag; name}] →
    [[Rename_tag (tag, name)]]; [Merge {from; into; plants}] → every plant
    [Link]ed to [into] (in [plants] order), then every plant [Unlink]ed from
    [from], then [Delete_tag from]; [Delete id] → [[Delete_tag id]] (links left
    as they are: queries ignore links to a deleted tag). *)

val followed : change -> Tag_id.t list -> Tag_id.t list
(** {!State.filters}'s tags after the change is saved: [Delete id] drops [id];
    [Merge {from; into}] turns [from] into [into]; [Create]/[Rename] change
    nothing. Sorted ([Tag_id.compare]) without duplicates. *)
