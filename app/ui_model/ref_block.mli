(** The rows of 4f's reference block (handoff 4f §6), from the projection and
    the thumbnails on the device. Pure. "Une ligne sans donnée disparaît": a row
    is in the list only when it has something to show. *)

module Projection := Herbier_refs.Projection
module Reference := Herbier_domain.Reference

type link = {label : string; url : string}
(** One anchor of the links row: [label = Ref_text.link_label source]. *)

type row =
  | Names of {languages : Projection.vernacular list; sources : string}
      (** [sources] = [Ref_text.names_source_line ~family]. *)
  | Life_form of {text : string; sources : string}  (** « Type » *)
  | Origin of {
      native : string option;  (** [Ref_text.origin_line], « Indigène : » *)
      introduced : string option;  (** « Introduite : » *)
      sources : string;
    }
  | Red_list of {chip : string; sources : string}
  | Flowering of {months : int list; text : string; sources : string}
      (** [text] = [Ref_text.months_text months]. *)
  | Habitat of {phrase : string option; chips : string list; sources : string}
  | Toxicity of {text : string; sources : string}
  | Organ_photos of {
      photos : (Reference.Organ.t * string) list;  (** organ, thumb path *)
      credits : string;  (** [Ref_text.credits] of the shown rows *)
      sources : string;  (** ["Pl@ntNet · disponibles hors-ligne"] *)
    }
  | Links of link list

val rows :
  Projection.t -> organ_photos:(Reference.Image.t * string) list -> row list
(** In this order, each only when present:
    - [Names]: some vernacular language or a taxon family;
    - [Life_form]: [life_form = Some _];
    - [Origin]: native or introduced non-empty (a side that is empty is [None]);
    - [Red_list]: [red_list = Some c] and [Ref_text.red_list c = Some chip];
    - [Flowering]: [flowering_months = Some _];
    - [Habitat]: [habitat = Some _];
    - [Toxicity]: [toxicity = Some _];
    - [Organ_photos]: [organ_photos <> []] (the argument:
      [Herbier_refs.Organ_photos.shown]);
    - [Links]: [links <> []], [label = Ref_text.link_label source].

    Every [sources] is [Ref_text.sources_line] of the cited sources, except
    [Names] and [Organ_photos] as stated. [rows] of a projection of no rows with
    no photos is []. *)
