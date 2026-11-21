(** The regional layer of one fetch (architecture §6): Tela Botanica and INPN,
    only for a taxon that has a TaxRef id (Wikidata P3186, else the cd_nom of
    Tela's BDTFX taxon found by exact scientific name). A sans-IO program like
    the {!Fanout.branches}, run by [refs_io/pipeline.ml] once the three branches
    have settled: it reads the name and TaxRef id of the gbif and wiki rows.
    Pure. *)

module Reference := Herbier_domain.Reference

type input = {
  name : string option;
      (** The GBIF taxon's name without authorship but with its rank markers
          ({!Sources.Gbif.Taxon.without_authorship}): the form of Tela's
          [nom_sci]. *)
  taxref : int option;  (** Wikidata P3186. *)
  settled : bool;
      (** [true] when both questions got an answer, now or before: the GBIF
          species decoded or GBIF said [Missing], and the Wikidata entity
          decoded (to an item or to "missing") or Wikidata said [Missing].
          [false] makes "no TaxRef id found" a [Failed] row (retried after a
          day), not a [Missing] one. *)
}

val equal_input : input -> input -> bool
val pp_input : Format.formatter -> input -> unit

val input : previous:Reference.t list -> Fanout.row list -> input
(** From this fetch's rows (the gbif and wiki branches' rows, before
    [Fanout.decide]; any other source ignored) and the plant's stored rows
    ([previous]; dead rows ignored):
    - [name]: {!Sources.Gbif.Taxon.without_authorship} of this fetch's gbif
      row's [species] member when it decodes, else of the live stored gbif
      row's; else [None];
    - [taxref]: the [taxref] of this fetch's wikidata row's [entity] member when
      it decodes, else (this fetch has no decodable entity) the stored live
      wikidata row's; [None] when the decoded entity is [None] (missing item) or
      has no P3186;
    - [settled]: as documented on the field ("GBIF said Missing" = this fetch's
      gbif row has status [Missing]; "Wikidata said Missing" = this fetch's
      wikidata row, else the stored one, has status [Missing]).

    Never raises; payloads that are not objects count as not decodable. *)

val program : input -> Fanout.row list Step.t
(** Always two rows, [[taxref row; tela row]] (in [Reference.Source.all] order),
    payloads built with {!Payload.taxref} / {!Payload.tela} from the bodies
    their decoders accept. Requests, strictly in this order, each made only when
    the rule reaches it:

    Tela (only when [name = Some n] and [Tela.names ~name:n] is [Some _]):
    + [Tela.names]: [Failed] or a body that does not decode → tela [Failed] [{}]
      ("bridge failed"); [Absent], or decodes but {!Sources.Tela.pick} finds
      nothing → tela [Missing] ([{}] / [{names}]), no more Tela calls.
    + [Tela.taxon ~nn:picked.nn]: [Failed]/undecodable → tela [Partial]
      [{names}] ("bridge failed"); [Absent] → tela [Missing] [{names}]; decodes
      → [t].

    Otherwise no Tela call; tela [Missing] [{}] when [settled], else [Failed]
    [{}] ("bridge failed").

    TaxRef id = [input.taxref], else [t.cd_nom]. When there is none: no more
    calls (neither Baseflor nor INPN); tela keeps the status reached above
    ([Missing] [{names; taxon}] when the taxon decoded); taxref row [Failed]
    [{}] when the bridge failed or [input] is not [settled] (the id may still
    come from Wikidata), else [Missing] [{}].

    With a TaxRef id [id]:
    + (only when [t] decoded) [Tela.baseflor ~nn:t.id]: a body that decodes →
      tela [Complete] [{names; taxon; baseflor}]; [Absent] → tela [Complete]
      [{names; taxon}] (Tela answered: no Baseflor row); [Failed]/undecodable →
      tela [Partial] [{names; taxon}]. Without [t], tela keeps the status
      reached above.
    + [Inpn.name ~cd_nom:id]: [Absent] → taxref [Missing] [{}], no more calls;
      [Failed]/undecodable → taxref [Failed] [{}], no more calls; decodes →
      [cd_ref].
    + [Inpn.status ~cd_ref], [Inpn.red_list ~cd_ref],
      [Inpn.protections ~cd_ref], all three made whatever each answers: all
      three decode → taxref [Complete] [{name; status; red_list; protections}];
      otherwise [Partial] with [name] and the members that decoded ([Absent]
      counts as not decoded).

    So a species without a TaxRef id makes at most the two bridge calls, and
    none to Baseflor or INPN. Never raises. *)
