(** The reference photos of 4f's « Photos par organe » in the viewer (5e,
    read-only mode): which slides, in which order, with which texts. Pure. *)

module Reference := Herbier_domain.Reference

type slide = {
  organ : Reference.Organ.t;
  thumb_path : string;  (** under refthumbs/, shown first and offline *)
  full_url : string;
      (** The image's [remote_url], a wanted one hence
          {!Herbier_refs.Organ_photos.downloadable} (https://bs.plantnet.org/…):
          loaded over the thumbnail when online. *)
  label : string;  (** [Ref_text.organ_label organ]: ["fleur"]… *)
  credit : string;  (** {!credit} of the image *)
  alt : string;  (** ["Photo Pl@ntNet : fleur"] *)
}

val equal_slide : slide -> slide -> bool
val pp_slide : Format.formatter -> slide -> unit

val credit : Reference.Image.t -> string
(** ["<attribution> · <licence> · Pl@ntNet"], [attribution] and [licence]
    trimmed; an empty one is left out with its separator
    (["cc-by-sa · Pl@ntNet"]); both empty → ["Pl@ntNet"]. 5e's line; 4f's
    caption under the tiles is [Ref_text.credits], another format. *)

val slides :
  Herbier_refs.Projection.t -> stored:Reference.Image.t list -> slide list
(** One per row of
    [Organ_photos.shown ~wanted:(Projection.organ_photos_wanted p) ~stored],
    same order (organ order): exactly the tiles 4f shows. *)

val start : slide list -> Reference.Organ.t -> int
(** Index of the first slide of that organ; [0] when absent (or no slide). *)
