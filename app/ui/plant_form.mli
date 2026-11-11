(** The pure part of 5a « Modifier la fiche » and of the fiche's « + tag »: what
    the form holds and the store operations it amounts to. *)

module Tag_id := Herbier_domain.Ids.Tag_id

(** A tag on the form: one of the store's, or a name typed that matches none
    (created on save). *)
type tag = Existing of Herbier_domain.Tag.t | Created of string

type t = {name : string; aliases : string list; tags : tag list}

val of_plant : Herbier_domain.Plant.t -> Herbier_domain.Tag.t list -> t
(** The form as the plant is now, with its live tags. *)

val add_alias : string -> t -> t
(** Trimmed; ignored when blank or already there. Comparisons here fold ASCII
    case only, like the store's [collate nocase]: « FORÊT » and « forêt »
    differ. *)

val remove_alias : string -> t -> t

val add_tag : all:Herbier_domain.Tag.t list -> string -> t -> t
(** [add_tag ~all name]: the store's tag of that name (case-insensitive,
    trimmed) if there is one, else [Created name]. Ignored when blank or when
    the form already has it. *)

val remove_tag : tag -> t -> t

val valid : t -> bool
(** The display name is not blank. *)

val tag_name : tag -> string

type change = {
  plant : Herbier_domain.Plant.t option;
      (** the record to upsert, if changed *)
  create_tags : string list;  (** new tags, in form order *)
  link : Tag_id.t list;  (** existing tags to put on the plant *)
  unlink : Tag_id.t list;  (** tags to take off *)
}

val diff :
  before:Herbier_domain.Plant.t ->
  before_tags:Herbier_domain.Tag.t list ->
  t ->
  change
(** What saving the form changes, the plant's [updated_at] left to the caller:
    [plant] is [Some] when the trimmed name or the aliases differ. *)
