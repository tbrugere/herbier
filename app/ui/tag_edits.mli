(** The pure part of 5d « Gérer les tags »: edits are staged on a local model
    and turned into store operations only on « Terminé », so « Annuler »
    discards them. *)

module Tag_id := Herbier_domain.Ids.Tag_id
module Plant_id := Herbier_domain.Ids.Plant_id

type fate = Kept | Deleted | Merged_into of Tag_id.t

type entry = {
  id : Tag_id.t;
  original : string;  (** the name in the store *)
  name : string;  (** the name shown, after renames *)
  plants : Plant_id.t list;  (** the plants carrying it in the store *)
  fate : fate;
}

val init : (Tag_id.t * string * Plant_id.t list) list -> entry list

val visible : entry list -> entry list
(** The [Kept] entries, in order. *)

val plants : entry list -> entry -> Plant_id.t list
(** The plants an entry will carry: its own and those of every entry merged into
    it, each once. *)

val rename : Tag_id.t -> string -> entry list -> entry list
(** A blank name (after trimming) leaves the entry as it is. *)

val delete : Tag_id.t list -> entry list -> entry list
(** Deletes those kept entries and the entries merged into them. *)

val winner : Tag_id.t list -> entry list -> entry option
(** Among those kept entries, the one with the most {!plants}, ties to the first
    in model order: the tag a merge keeps (handoff 5d, « le nom le plus fréquent
    gagne »). [None] for fewer than two. *)

val merge : Tag_id.t list -> entry list -> entry list
(** Merges those entries into their {!winner}; entries already merged into one
    of the losers follow it to the winner. No change for fewer than two. *)

val followed : entry list -> Tag_id.t list -> Tag_id.t list
(** A tag filter once the model is saved: a merged tag becomes its winner, a
    deleted one is dropped, an unknown one stays. Sorted, without duplicates. *)

type op =
  | Rename of Tag_id.t * string
  | Delete of Tag_id.t
  | Link of {plant : Plant_id.t; tag : Tag_id.t}
  | Unlink of {plant : Plant_id.t; tag : Tag_id.t}

val plan : entry list -> op list
(** What to write: renames of kept entries whose name changed; for each merged
    entry, its plants linked to the winner, unlinked from it, then its deletion;
    deletions. In model order. *)
