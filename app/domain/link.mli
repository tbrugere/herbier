(** Classification of a shared or opened link: a bare URL or text containing
    one, on the hosts of architecture §7. Pure: no network.

    Parsing is deliberately small: scheme [http] or [https] (any case), host
    lowercased with userinfo, port and a trailing dot dropped and made only of
    letters, digits, [.] and [-], path split on [/] (or a backslash, as a
    browser does) with empty segments dropped and each segment percent-decoded
    (["+"] stays a plus: it is a path, not a form; a segment that would decode
    to invalid UTF-8 is kept as written). Query and fragment are ignored. A
    leading ["www."] is ignored on every host, before any other prefix
    (["www.m.gbif.org"] is ["m.gbif.org"]); any other host, a mobile ["m."] one
    included, matches only where a constructor below names it. A name, title or
    id that is blank once decoded and trimmed matches nothing.

    String payloads are decoded, untrusted text: they may contain [/], [?], [#]
    or control characters, so a caller re-encodes them as one path segment or
    passes them as a bound query parameter. *)

type t =
  | Gbif of int
      (** [www.gbif.org/species/<key>] or [/<lang>/species/<key>] (also
          [m.gbif.org]), with any trailing segments ([/metrics], [/verbatim]).
      *)
  | Plantnet of string
      (** [identify.plantnet.org/…/species/<name>/…]: the decoded scientific
          name with its authorship, as in the path (["Digitalis purpurea L."]).
      *)
  | Plantnet_observation of string
      (** [identify.plantnet.org/…/observations/<id>]: an observation id, which
          names no species by itself. *)
  | Plantuse of string
      (** [plantuse.plantnet.org/<lang>/<Page_name>], exactly two segments (also
          [uses.plantnet.org] and the old [uses.plantnet-project.org]), not
          [/w/…] nor a namespaced page (a [:] in the name): the wiki page name
          with underscores turned into spaces (["Digitalis purpurea"]). *)
  | Wikipedia of {lang : string; title : string}
      (** [<lang>.wikipedia.org/wiki/<title>] or [<lang>.m.wikipedia.org/…]
          ([lang] starts with a letter and is not [www]): [title] is every
          segment after [wiki] joined by [/], decoded, underscores turned into
          spaces. *)
  | Inpn of int
      (** [inpn.mnhn.fr/espece/cd_nom/<cd_nom>] or [/explorer/especes/<cd_nom>]:
          the TaxRef [cd_nom]. *)
  | Tela of int
      (** [www.tela-botanica.org/bdtfx-nn-<nn>] (with an optional [-<tab>]
          suffix, e.g. [-synthese]): the BDTFX [nn]. *)
  | Powo of string
      (** [powo.science.kew.org/taxon/<id>]: the POWO id as in the path, e.g.
          ["urn:lsid:ipni.org:names:30000174-2"] (the form of Wikidata P5037).
      *)
  | Inat of int
      (** [www.inaturalist.org/taxa/<id>] or [/taxa/<id>-<Name>] (also
          [m.inaturalist.org]): the taxon id. *)
  | Text of string
      (** Anything else: the input, trimmed, for a free-text search. A text
          whose URLs match none of the patterns above is [Text] of the whole
          text. *)

val classify : string -> t
(** [classify input] reads the [http://] or [https://] URLs in [input] in order
    and classifies the first that matches a pattern. A URL ends at whitespace, a
    no-break space, a [\]] directly followed by [(] (Markdown link text) or the
    end of the text; trailing sentence punctuation, closing quotes ([»], [”],
    [’]) and closing brackets that close nothing inside the URL are not part of
    it, except that dots ending a Pl@ntNet species URL are kept: they end the
    authorship, as in ["L."]. Without such a URL, or when no URL matches a
    pattern (a numeric id must parse as a positive [int]), the result is [Text]
    of the trimmed input. Never raises. *)

val equal : t -> t -> bool

val to_string : t -> string
(** A readable form for logs and test diffs, e.g. ["gbif 5414463"]. *)
