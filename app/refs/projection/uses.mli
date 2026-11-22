(** The « Utilisations » row of 4f: Pl@ntUse's summary of the uses and the first
    paragraph of the Wikipedia article's uses section. *)

type wikipedia = {
  paragraph : string;
      (** The line {!Sources.Wikipedia.uses_line} picks (TextExtracts writes one
          paragraph per line). *)
  section : string;  (** The matched section title, as written. *)
  lang : string;
      (** The article's [pagelanguage] when it passes
          {!Herbier_domain.Link.valid_wikipedia_lang}, else the language of its
          URL, else ["fr"]. *)
  title : string;  (** The article's title. *)
  url : string;
      (** The article's [fullurl] when it is https and
          {!Herbier_domain.Link.classify} reads it as a Wikipedia page, else
          [Source_url.wikipedia ~lang title]. *)
}

val equal_wikipedia : wikipedia -> wikipedia -> bool
val pp_wikipedia : Format.formatter -> wikipedia -> unit

val wikipedia : Sources.Wikipedia.article -> wikipedia option
(** [None] when {!Sources.Wikipedia.uses_line} is [None]. *)

type plantuse = {
  summary : string list;
  text : string option;
  title : string;  (** The Pl@ntUse page's title. *)
  url : string;  (** [Source_url.plantuse title]. *)
}

val equal_plantuse : plantuse -> plantuse -> bool
val pp_plantuse : Format.formatter -> plantuse -> unit

val plantuse : Sources.Plantuse.page -> plantuse option
(** {!Sources.Plantuse.uses} of the page; [None] when it has no summary and no
    text. *)
