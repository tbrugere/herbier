(** Dev-only page for [Herbier_refs_io.Http]: queues ten GETs, five to GBIF and
    five to Wikidata, then four to GBIF, Wikidata, Wikipedia and iNaturalist,
    then a missing GBIF species (expect [HTTP 404]), a Wikidata call with a 1 ms
    timeout (expect [timeout]) and one more Wikidata call (expect [ok]: the
    timed-out slot was freed). It logs each call when queued and when it
    settles, with the sources in flight at that moment, so the limits (one per
    source, at most three overall) can be read off the log, and ends with a
    [done] line counting the results. Reached with the URL fragment
    [#dev/refs-http]. *)

val el : unit -> Brr.El.t
