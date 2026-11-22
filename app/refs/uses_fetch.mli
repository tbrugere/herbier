(** The Pl@ntUse program of one fetch (architecture §6): one GET to Pl@ntUse's
    MediaWiki API for the GBIF name, run by [refs_io/pipeline.ml] once the three
    {!Fanout.branches} have settled, concurrently with {!Regional.program} and
    on the same {!Regional.input}. Pure. *)

val program : Regional.input -> Fanout.row list Step.t
(** Always one row, [[plantuse row]], its payload built with
    {!Payload.plantuse}:
    - [name = None], or {!Sources.Plantuse.titles} gives [[]]: no call;
      [Missing] [{}] when [settled], else [Failed] [{}] (retried after a day, as
      the regional rows are);
    - [Sources.Plantuse.page ~titles:(Sources.Plantuse.titles name)]: [Failed],
      [Absent] (MediaWiki never 404s a query) or a body that does not decode →
      [Failed] [{}]; decodes and {!Sources.Plantuse.find} gives a page →
      [Complete] [{page}]; decodes and finds none → [Missing] [{page}].

    A page found without any use data is [Complete] (the source answered); the
    projection then shows no Pl@ntUse part. Never raises. *)
