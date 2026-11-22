(** The reference fetch of one GBIF key (architecture §6): one program per
    branch, each giving the rows of its sources, and the rules that turn them
    into the rows to store next to what is already stored. Pure. *)

module Reference := Herbier_domain.Reference
module Source := Reference.Source

val sources : Source.t list
(** [[Gbif; Plantnet; Wikidata; Wikipedia; Taxref; Tela; Plantuse]]: the sources
    a fetch writes (taxref and tela by {!Regional.program}, plantuse by
    {!Uses_fetch.program}, after the {!branches}). A source added here makes
    every plant fetched before it due once ({!due}): that is its backfill. *)

type row = {
  source : Source.t;
  status : Reference.Status.t;
  payload : Yojson.Safe.t;
}
(** What one source said in this fetch. [payload] is built by the {!Payload}
    builder of [source] from the bodies of the calls that returned a
    {!Step.Body} that its {!Sources} decoder accepts; a call that failed, was
    absent, or whose body does not decode has no member. *)

val equal_row : row -> row -> bool
(** Payloads compared structurally ([Yojson.Safe.equal]). *)

val branches : gbif_key:int -> row list Step.t list
(** Three programs, in this order:
    - gbif: [Gbif.species], then [vernacular_names], [distributions],
      [occurrence_count] (each of [~key:gbif_key]) → [[gbif row]];
    - plantnet: [Gbif.plantnet_media ~key] → [[plantnet row]];
    - wiki: [Wikidata.search ~property:Gbif_key ~value:(string_of_int key)],
      then [Wikidata.entity] of the first Qid, then the Wikipedia summary of the
      entity's fr sitelink, else its en one → [[wikidata row; wikipedia row]].

    Status rules (a part "succeeds" when its body is a [Body] its decoder
    accepts):
    - gbif: species [Absent] → [Missing], payload [`Assoc []], and no other
      call; otherwise all four succeed → [Complete]; some → [Partial]; none →
      [Failed].
    - plantnet: media succeeds with no image → [Missing] (payload holds the
      media member); succeeds otherwise → [Complete]; else [Failed] ([Absent]
      counts as failed: GBIF does not 404 a search).
    - wikidata: search fails → wikidata [Failed] and wikipedia [Failed], both
      [`Assoc []] (the summary cannot be asked for, so it counts as failed and
      is retried like one). Search decodes to [[]] → wikidata [Missing]
      [{search}] and wikipedia [Missing] [`Assoc []]. Entity fails → wikidata
      [Partial] [{search}], wikipedia [Failed] [`Assoc []]. Entity decodes to
      [None] (missing) → wikidata [Missing] [{search, entity}], wikipedia
      [Missing]. Entity decodes → wikidata [Complete] [{search, entity}], then:
    - wikipedia: the summary requests of the fr then the en sitelink (those
      {!Sources.Wikipedia.summary} builds), tried in order: one that succeeds →
      [Complete] [{summary}]; [Absent] → the next one; none left (or none at
      all) → [Missing] [`Assoc []]; [Failed] or a body that does not decode →
      [Failed] (no en attempt after a fr failure). Then, unless that gave
      [Failed], the uses step: the {!Sources.Wikipedia.extract} requests of the
      fr then the en sitelink, tried in order: a body that [article_of_json]
      decodes to [Some a] with {!Sources.Wikipedia.has_uses} [a] → stop, member
      [uses] = that body; decodes to [None] or without uses → that body is the
      candidate member, the next request is tried; [Failed], [Absent] or a body
      that does not decode → stop, "uses failed", no [uses] member (the
      candidate dropped). No sitelink: no uses call. Status: summary [Complete]
      or [Missing] as above when the uses step did not fail; [Partial] when it
      failed. *)

val live_row : Reference.t list -> Source.t -> Reference.t option
(** The row of the source in the stored rows that is not soft-deleted. *)

val decide : previous:Reference.t list -> row list -> row list
(** The rows to store, given the plant's stored rows ([previous]; rows with
    [deleted_at = Some _] are ignored). Per row, in input order:
    - [Failed] with a live previous row of that source that is not [Failed] →
      dropped (the stored row stays as it is: a failing source leaves the others
      intact, and itself too);
    - [Failed] with a live previous [Failed] row → kept, payload merged as for
      [Partial] below: storing it dates the failure (its [fetched_at]), so the
      retry rules ({!due}, [Fetch_rule.unfinished]) wait from the last attempt;
    - [Failed] without one → kept as is;
    - [Partial] with a live previous row → payload = this row's members, plus,
      for each part of {!Payload.parts} of the source absent here, the previous
      payload's member when present, members in {!Payload.all} order; status
      stays [Partial];
    - [Complete], [Missing], or [Partial] without a previous row → as is. *)

val max_age : Ptime.Span.t
(** 90 days. *)

val retry_after : Ptime.Span.t
(** 1 day. *)

val due : now:Ptime.t -> Reference.t list -> bool
(** Whether opening the fiche (online) should fetch, over the plant's rows (dead
    rows and sources outside {!sources} ignored): [true] when a source of
    {!sources} has no live row, when a live row's status is [Failed] or
    [Partial] and its [fetched_at] is more than {!retry_after} before [now], or
    when any live row's [fetched_at] is more than {!max_age} before [now]
    (strictly). [false] otherwise, including for rows dated after [now] (clock
    skew). *)
