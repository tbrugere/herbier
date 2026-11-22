(** The rows of 4f's reference block (handoff 4f §6), from the projection and
    the thumbnails on the device. Pure. "Une ligne sans donnée disparaît": a row
    is in the list only when it has something to show. *)

module Projection := Herbier_refs.Projection
module Reference := Herbier_domain.Reference

type link = {label : string; url : string}
(** One anchor of the links row: [label = Ref_text.link_label source]. *)

type plantuse_uses = {
  chips : string list;  (** Pl@ntUse's summary bullets, as written. *)
  line : string option;
      (** The first two sentences of its « Usages » section. *)
  url : string;  (** The Pl@ntUse page. *)
  credit : string;  (** [Ref_text.plantuse_credit] *)
}

type wikipedia_uses = {
  paragraph : string;
  url : string;  (** The article. *)
  credit : string;  (** [Ref_text.wikipedia_uses_credit] *)
}

(** « Utilisations »: Pl@ntUse's part, Wikipedia's, or both; never neither. *)
type uses =
  | Plantuse_only of plantuse_uses
  | Wikipedia_only of wikipedia_uses
  | Both of plantuse_uses * wikipedia_uses

val uses_parts : uses -> plantuse_uses option * wikipedia_uses option
(** The two parts, at least one [Some]. *)

type row =
  | Names of {
      french : string list;
          (** The fr names (1 to 3), in vote order; [[]] when none. *)
      others : Projection.vernacular list;
          (** The other languages with names, in [Projection.Lang.all] order
              (en, de, it). *)
      sources : string;  (** [Ref_text.names_source_line ~family]. *)
    }
  | Life_form of {text : string; sources : string}  (** « Type » *)
  | Origin of {
      native : string option;  (** [Ref_text.origin_line], « Indigène : » *)
      introduced : string option;  (** « Introduite : » *)
      sources : string;
    }
  | En_france of {
      chips : string list;
          (** [Ref_text.fr_status], [fr_protection], [fr_red_list], in that
              order, those that exist. *)
      places : string option;  (** [Ref_text.fr_places] *)
      sources : string;
    }  (** « En France » *)
  | Red_list of {
      label : string;
          (** « Liste rouge mondiale » when an [En_france] row is shown, else «
              Liste rouge ». *)
      chip : string;
      sources : string;
    }
  | Flowering of {months : int list; text : string; sources : string}
      (** [text] = [Ref_text.months_text months]. *)
  | Habitat of {phrase : string option; chips : string list; sources : string}
  | Toxicity of {text : string; sources : string}
  | Uses of uses
      (** « Utilisations »: each part carries its own credit, so the row has no
          [sources]. *)
  | Organ_photos of {
      photos : (Reference.Organ.t * string) list;  (** organ, thumb path *)
      credits : string;  (** [Ref_text.credits] of the shown rows *)
      sources : string;  (** ["Pl@ntNet"] *)
    }
  | Links of link list

val rows :
  Projection.t -> organ_photos:(Reference.Image.t * string) list -> row list
(** In this order, each only when present:
    - [Names]: some vernacular language or a taxon family;
    - [Life_form]: [life_form = Some _];
    - [Origin]: native or introduced non-empty (a side that is empty is [None]),
      each side [Ref_text.origin_line (Ref_text.origin_names areas)]: French
      names, in French order;
    - [En_france]: at least one chip; [sources] is [Ref_text.sources_line] of
      the union of the three fields' sources;
    - [Red_list]: [red_list = Some c] and [Ref_text.red_list c = Some chip];
    - [Flowering]: [flowering_months = Some _];
    - [Habitat]: [habitat = Some _];
    - [Toxicity]: [toxicity = Some _];
    - [Uses]: [plantuse_uses] or [wikipedia_uses] is [Some]; [plantuse] is
      [Some] when the projection's Pl@ntUse part has a chip or a line, its
      [chips] the summary, its [line] the text; [wikipedia] carries the
      paragraph, the article URL and
      [Ref_text.wikipedia_uses_credit ~lang ~section];
    - [Organ_photos]: [organ_photos <> []] (the argument:
      [Herbier_refs.Organ_photos.shown]);
    - [Links]: [links <> []], [label = Ref_text.link_label source].

    Every [sources] is [Ref_text.sources_line] of the cited sources, except
    [Names] and [Organ_photos] as stated. [rows] of a projection of no rows with
    no photos is []. *)
