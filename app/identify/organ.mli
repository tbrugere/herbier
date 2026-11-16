(** Pl@ntNet's organs, as Herbier sends and shows them (architecture §12): the
    wire set, bark included, separate from the stored
    {!Herbier_domain.Reference.Organ} lookup (no bark). *)

type t = Flower | Leaf | Fruit | Bark | Habit

val equal : t -> t -> bool

val pp : Format.formatter -> t -> unit
(** Prints {!to_string} (tests' printer). *)

val all : t list
(** [[Flower; Leaf; Fruit; Bark; Habit]]. *)

val to_string : t -> string
(** Pl@ntNet's names: ["flower"], ["leaf"], ["fruit"], ["bark"], ["habit"]. *)

val of_string : string -> t option
(** Exact inverse of {!to_string} (case-sensitive, no trimming). Every other
    name — ["auto"], ["other"], ["scan"], ["branch"], [""], ["Flower"], … —
    gives [None]: an organ Herbier does not offer. *)

val label : t -> string
(** « fleur », « feuille », « fruit », « écorce », « port » (the same words as
    [Ref_text.organ_label] for the stored organs). *)

(** The organ sent with a photo: [Auto] unless the user set one (« fleur ▾ »
    corrected, or a photo taken for « + feuille »). *)
type sent = Auto | Given of t

val equal_sent : sent -> sent -> bool

val sent_to_string : sent -> string
(** ["auto"], or {!to_string}: the [organs] value of the form. *)

val max_photos : int
(** 5: Pl@ntNet takes at most five images per request. *)

val effective : sent -> detected:t option -> t option
(** What a photo counts as for {!suggest}: [Given o] → [Some o] (whatever was
    detected); [Auto] → [detected] (Pl@ntNet's [predictedOrgans], [None] when
    not detected or an organ Herbier does not offer). *)

type suggestion = Add of t | Add_photo

val equal_suggestion : suggestion -> suggestion -> bool

val suggest : t option list -> suggestion option
(** The « + <organe> » tile, from each photo's {!effective} organ:
    - {!max_photos} photos or more → [None];
    - no [Some Flower] → [Some (Add Flower)];
    - else no [Some Leaf] → [Some (Add Leaf)];
    - else [Some Add_photo].

    [[]] → [Some (Add Flower)]. *)

val suggestion_label : suggestion -> string
(** « + fleur », « + feuille », … (« + », a space, {!label}); [Add_photo] → « +
    photo ». *)

val sent_of_suggestion : suggestion -> sent
(** The organ a photo taken for the tile is sent with: [Add o] → [Given o];
    [Add_photo] → [Auto]. *)
