(** Pl@ntUse, Pl@ntNet's wiki of plant uses (architecture §6), through the
    MediaWiki action API of its French wiki (the populated one; the English
    wiki's species pages are empty robot stubs). One request gives the wikitext
    of the asked pages, following redirects. Requests are [Source.Plantuse]; no
    custom header (the API answers CORS [*] with [origin=*]). Content: Creative
    Commons (CC BY-SA, cited « Pl@ntUse · CC BY-SA »).

    Decoders follow the field rules of {!Decode}. *)

val titles : string -> string list
(** The page titles to ask for a GBIF name without authorship (the
    [Regional.input.name] form): the trimmed name, then its first two words when
    it has more than two (["Digitalis purpurea subsp. purpurea"] →
    [["Digitalis purpurea subsp. purpurea"; "Digitalis purpurea"]]); [[]] when
    blank. *)

val page : titles:string list -> Request.t option
(** [Source_url.plantuse_wiki ^ "/api.php"] with, in this order: [action=query],
    [prop=revisions], [rvprop=content], [rvslots=main], [redirects=1],
    [titles=<the trimmed non-blank titles joined with '|'>], [format=json],
    [formatversion=2], [origin=*] (['|'] and ['*'] percent-encoded, which
    MediaWiki accepts). [None] when no title is left. *)

type page = {title : string; wikitext : string}

val equal_page : page -> page -> bool
val pp_page : Format.formatter -> page -> unit

type answer = {
  normalized : (string * string) list;  (** [query.normalized], from → to. *)
  redirects : (string * string) list;  (** [query.redirects], from → to. *)
  pages : page list;
      (** The [query.pages] that are not [missing] nor [invalid], with their
          [revisions[0].slots.main.content], in payload order (not the order
          asked). *)
}

val equal_answer : answer -> answer -> bool
val pp_answer : Format.formatter -> answer -> unit

val answer_of_json : Yojson.Safe.t -> (answer, Decode.error) result
(** A root [error] object (MediaWiki's API error) → [Api_error {code; info}];
    else a required [query] object ([Unexpected "/query" "object"]) holding a
    required [pages] array ([Unexpected "/query/pages" "array"]). [normalized]
    and [redirects] missing or not arrays → [[]]. A page element that is not an
    object, or has no string [title], is dropped. A page that exists (not
    [missing] nor [invalid]) without a string [revisions[0].slots.main.content]
    (a hidden revision) →
    [Unexpected "/query/pages/<i>/revisions/0/slots/main/content" "string"]: an
    unreadable page is a failure, not a missing one. An unknown page is
    [{"title", "missing": true}] in a 200 answer (never a 404). *)

val pick : titles:string list -> answer -> page option
(** For each trimmed title in order: [normalized] applied once (else the title
    with ['_'] turned into [' ']), then [redirects] once; the first page whose
    [title] equals the result. [None] when none does. *)

val find : name:string option -> answer -> page option
(** [pick ~titles:(titles name)]; [None] without a name. The one rule for the
    page of a name, used by the fetch (Complete or Missing) and the projection.
*)

type uses = {summary : string list; text : string option}

val equal_uses : uses -> uses -> bool
val pp_uses : Format.formatter -> uses -> unit

val uses : page -> uses
(** [summary]: the {!Wiki_text.bullets} of the [texte] parameter of every
    [Encadré] template whose [titre], {!Wiki_text.strip}ped, is
    ["Résumé des usages"] (case-insensitive), duplicates dropped
    (case-insensitive, the first spelling kept): Pl@ntUse's own short summary of
    the uses.

    [text]: in the bodies of the level-2 sections titled ["Usages"]
    (case-insensitive), in order, the first paragraph left once these lines are
    dropped: template blocks (a line starting with [{{] up to the line closing
    it: Pl@ntUse's [Citation encadré] holds English PFAF quotes),
    [<gallery>…</gallery>] blocks, list lines (starting with ['*'] or ['#']: the
    « Voir les … » cross-references), table delimiters (lines starting with
    [{|], [|}], [|-] or ['!']); a table cell line ([|…]) keeps its text: its
    cells split on [||] (outside links and templates), each without its
    attributes (the part before the first ['|'] when it holds ['=']), joined
    with spaces. Paragraphs are separated by blank or dropped lines; the first
    one that is not blank once {!Wiki_text.strip}ped, cut to
    [Wiki_text.first_sentences ~n:2]; [None] when there is none. *)

val page_url : string -> string
(** [Source_url.plantuse title]. *)
