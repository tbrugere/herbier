(** 6d Comparer as a pure value (architecture §12): which proposal and which of
    its images are shown, in 6d's order (my photos' organs first, see
    {!Herbier_identify.Proposal.display_order}), which of my photos is on top, ‹
    › and swipe. No request, no IO. Never raises. *)

module Organ := Herbier_identify.Organ
module Plantnet := Herbier_identify.Plantnet

type t
(** Invariants: at least one proposal; at least one photo of mine; the image
    position in range of the current proposal's images, or 0 when it has none.
*)

val equal : t -> t -> bool

val open_ :
  proposals:Plantnet.proposal list ->
  mine:Organ.t option list ->
  proposal:int ->
  tile:int ->
  t option
(** 6d opened from 6c's tile [tile] (0-based, in
    {!Herbier_identify.Proposal.closest}'s order) of proposal [proposal]
    (0-based, Pl@ntNet's order). [mine]: the effective organ of each of my
    photos in photo order ({!Layer.effective_organs}). The image shown first is
    the tapped one: Pl@ntNet index [tile], except for the « +N » tile (the last
    tile, [tile = Proposal.tiles - 1], when [Proposal.more p > 0]), which opens
    on the first image 6c does not show (Pl@ntNet index
    {!Herbier_identify.Proposal.tiles}); {!image_index} is that image's position
    in {!images}. [None] (6d does not open) when [proposals = []], [mine = []],
    [proposal] out of range, or [tile] outside
    [0 .. length (Proposal.closest p) - 1] (so never for a proposal without
    images). *)

type event =
  | Previous  (** ‹ *)
  | Next  (** › *)
  | Shown of int
      (** the swipe track settled on this 0-based position of {!images} *)

val step : t -> event -> t
(** - [Previous]: [index > 0] → proposal [index - 1], image 0; else unchanged.
    - [Next]: [index < count - 1] → proposal [index + 1], image 0; else
      unchanged.
    - [Shown k]: [k] clamped to [0 .. length images - 1] (0 when there are none)
      becomes the image; the proposal is unchanged. *)

val index : t -> int
(** 0-based proposal shown. *)

val count : t -> int
(** Proposals (≥ 1). *)

val proposal : t -> Plantnet.proposal

val can_previous : t -> bool
(** [index > 0]. *)

val can_next : t -> bool
(** [index < count - 1]. *)

val images : t -> Plantnet.image list
(** The current proposal's images (all of them, not only 6c's four) in
    {!Herbier_identify.Proposal.display_order} [~mine]. [[]] for a proposal
    without images (reached by ‹ ›). *)

val image_index : t -> int
(** 0-based position in {!images}; 0 when there are none. *)

val image : t -> Plantnet.image option
(** The image at {!image_index}; [None] when there are none. *)

val mine_index : t -> int
(** Which of my photos is on top: the first photo whose organ in [mine] is the
    current image's organ ([Some o]); else 0 (no image, an image of organ
    [None], or an organ none of my photos has). *)

val mine_organ : t -> Organ.t option
(** [mine]'s organ at {!mine_index}. *)

val to_load : t -> int list
(** Positions of {!images} whose [m] URL should be set now: {!image_index} and
    its neighbours ([image_index - 1], [image_index + 1]) that exist, ascending.
    [[]] without images. The screen sets an image's [src] the first time it
    appears here and never unsets it. *)
