(** Rules for showing the proposals (architecture §12). Pure. *)

val tiles : int
(** 4: the images shown per proposal. *)

val closest : Plantnet.proposal -> Plantnet.image list
(** The first {!tiles} images, Pl@ntNet's order (closest first). *)

val more : Plantnet.proposal -> int
(** The images beyond {!tiles}: [max 0 (length images - tiles)]. *)

val more_label : Plantnet.proposal -> string option
(** [Some "+N"] when {!more} is [N > 0], else [None]. *)

val same_organ_first :
  mine:Organ.t option -> Plantnet.image list -> Plantnet.image list
(** Display order of the enlarged images: the images whose [organ] is [mine]
    first, then the others, each group in the given order (a stable partition).
    [mine = None] → the list unchanged; images with [organ = None] never match.
*)

val licence_label : string -> string
(** ["cc-by-sa"] → ["CC BY-SA"]: a licence (trimmed) starting with ["cc-"]
    (case-insensitive) becomes ["CC "] followed by the rest upper-cased
    (["cc-by"] → ["CC BY"], ["cc-by-nc-sa"] → ["CC BY-NC-SA"]); ["cc0"]
    (case-insensitive) → ["CC0"]; anything else, a bare ["cc-"] included,
    trimmed, as sent. *)

val credit : Plantnet.image -> string
(** « © <author> · <licence_label licence> · Pl@ntNet » (U+00A9, U+00B7 with one
    space on each side), e.g. ["© Daniel Mardare · CC BY-SA · Pl@ntNet"]. *)

val min_best : float
(** 0.5: below it, the best proposal is uncertain. *)

val min_lead : float
(** 0.15: the lead the best proposal needs over the second. *)

val uncertain : Plantnet.proposal list -> bool
(** Uncertain when the first proposal's score is below {!min_best}, or it is
    less than {!min_lead} ahead of the second's ([best -. second < min_lead],
    compared in Pl@ntNet's units of 1e-5, so that a lead of exactly {!min_lead}
    is not below it; a single proposal has a second of 0). [[]] → [true]
    (nothing to be sure of). Pl@ntNet's order is taken as is: "best" is the
    first, not the maximum. *)
