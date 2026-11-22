(* Herbier_refs.Fetch_rule: the one place that decides whether a plant's
   references are fetched (architecture §6). Pure. *)

module Value = Herbier_test_support.Value
module Text = Herbier_test_support.Text
module Ids = Herbier_domain.Ids
module Plant = Herbier_domain.Plant
module Reference = Herbier_domain.Reference
module Source = Herbier_domain.Reference.Source
module Status = Herbier_domain.Reference.Status
module Fanout = Herbier_refs.Fanout
module Step = Herbier_refs.Step
module Request = Herbier_refs.Request
module Wikidata = Herbier_refs.Sources.Wikidata
module Fetch_rule = Herbier_refs.Fetch_rule
module Regional = Herbier_refs.Regional
module Uses_fetch = Herbier_refs.Uses_fetch

(* ---------- testables ---------- *)

let action = Alcotest.testable Fetch_rule.pp_action Fetch_rule.equal_action
let status = Alcotest.testable Status.pp Status.equal

let trigger_name : Fetch_rule.trigger -> string = function
  | Fetch_rule.Linked -> "Linked"
  | Fetch_rule.Refresh -> "Refresh"
  | Fetch_rule.Opened _ -> "Opened"
  | Fetch_rule.Reconnected _ -> "Reconnected"

(* ---------- ids, time, builders ---------- *)

let time = Value.time
let now = time "2026-11-12T00:00:00Z"
let plant_id n = Value.id "plant id" Ids.Plant_id.of_string (Value.uuid4 n)
let plant_a = plant_id 1
let plant_b = plant_id 2

let reference_row ?(status = Status.Complete) ?deleted_at ?(plant = plant_a)
    ~source ~fetched_at payload : Reference.t =
  {
    id = Reference.id_of_key ~plant ~source;
    plant_id = plant;
    source;
    fetched_at;
    payload;
    status;
    created_at = fetched_at;
    updated_at = fetched_at;
    deleted_at;
  }

let plant ?(gbif_key = Some 1) ?(deleted_at = None) ?(updated_at = now) id :
    Plant.t =
  {
    id;
    display_name = "P";
    aliases = [];
    scientific_name = None;
    authorship = None;
    gbif_key;
    notes = "";
    notes_updated_at = None;
    cover_photo_id = None;
    created_at = now;
    updated_at;
    deleted_at;
  }

let states rows = List.filter_map Reference.Fetch_state.of_reference rows
let unfinished rows = Fetch_rule.unfinished ~now (states rows)

let pending ?(back_online = false) ~plants ~references () =
  Fetch_rule.pending ~back_online ~now ~plants ~states:(states references)

let minutes_before n =
  Option.get (Ptime.sub_span now (Ptime.Span.of_int_s (n * 60)))

let pending_pairs l = List.map (fun (id, k) -> (Ids.Plant_id.to_string id, k)) l

let every_source_live ~status ~fetched_at =
  List.map
    (fun source -> reference_row ~status ~source ~fetched_at (`Assoc []))
    Fanout.sources

(* ---------- a creation triggers the full fan-out ---------- *)

let branches3 gbif_key =
  match Fanout.branches ~gbif_key with
  | [g; p; w] -> (g, p, w)
  | bs -> Alcotest.failf "expected 3 branches, got %d" (List.length bs)

(* A whole fetch, as the pipeline runs it: the three branches, then the
   regional program and Uses_fetch on their rows. *)
let fetch_all net =
  let gbif_b, plantnet_b, wiki_b = branches3 5414995 in
  let rows =
    Step.run net gbif_b @ Step.run net plantnet_b @ Step.run net wiki_b
  in
  let input = Regional.input ~previous:[] rows in
  rows
  @ Step.run net (Regional.program input)
  @ Step.run net (Uses_fetch.program input)

let digitalis_net =
  Fake_net.with_
    (Fake_net.digitalis_regional
    @ Fake_net.plantuse_table ~titles:["Digitalis purpurea"]
        "plantuse_page_digitalis_purpurea.json")
    Fake_net.digitalis

let has_request ~host reqs =
  List.exists
    (fun (r : Request.t) -> Text.contains ~sub:host r.Request.url)
    reqs

let linked_fetches_and_the_fan_out_covers_every_source () =
  Alcotest.(check action)
    "Linked, no fetch running, online: Fetch" Fetch_rule.Fetch
    (Fetch_rule.decide Fetch_rule.Linked ~online:true ~running:false ~now);
  let gbif_b, plantnet_b, wiki_b = branches3 5414995 in
  let net = digitalis_net in
  let all_rows = fetch_all net in
  List.iter
    (fun (r : Fanout.row) ->
      Alcotest.check status
        (Source.to_string r.source ^ ": Complete")
        Status.Complete r.status)
    all_rows;
  Alcotest.(check (list string))
    "the union of the fetched rows' sources is Fanout.sources"
    (List.sort compare (List.map Source.to_string Fanout.sources))
    (List.sort compare
       (List.map (fun (r : Fanout.row) -> Source.to_string r.source) all_rows));
  Alcotest.(check bool)
    "the gbif branch hits api.gbif.org" true
    (has_request ~host:"api.gbif.org" (Step.requests net gbif_b));
  Alcotest.(check bool)
    "the plantnet branch hits api.gbif.org (Pl@ntNet media via GBIF)" true
    (has_request ~host:"api.gbif.org" (Step.requests net plantnet_b));
  Alcotest.(check bool)
    "the wiki branch hits www.wikidata.org" true
    (has_request ~host:"www.wikidata.org" (Step.requests net wiki_b));
  Alcotest.(check bool)
    "the wiki branch hits fr.wikipedia.org" true
    (has_request ~host:"fr.wikipedia.org" (Step.requests net wiki_b));
  let decided = Fanout.decide ~previous:[] all_rows in
  let refs =
    List.map
      (fun (r : Fanout.row) ->
        reference_row ~status:r.status ~source:r.source ~fetched_at:now
          r.payload)
      decided
  in
  Alcotest.(check bool)
    "unfinished is false once the fan-out has fetched every source" false
    (unfinished refs);
  Alcotest.(check action)
    "Reconnected over a finished fetch does nothing" Fetch_rule.Nothing
    (Fetch_rule.decide
       (Fetch_rule.Reconnected {states = states refs; back_online = true})
       ~online:true ~running:false ~now);
  Alcotest.(check (list (pair string int)))
    "pending is [] once finished" []
    (pending_pairs
       (pending
          ~plants:[plant ~gbif_key:(Some 5414995) plant_a]
          ~references:refs ()))

(* ---------- decide: running and offline, for every trigger ---------- *)

let decide_running_and_offline () =
  Alcotest.(check action)
    "Linked, running: still Fetch (the caller supersedes)" Fetch_rule.Fetch
    (Fetch_rule.decide Fetch_rule.Linked ~online:true ~running:true ~now);
  List.iter
    (fun trigger ->
      Alcotest.(check action)
        (trigger_name trigger ^ " offline, not running: Nothing")
        Fetch_rule.Nothing
        (Fetch_rule.decide trigger ~online:false ~running:false ~now);
      Alcotest.(check action)
        (trigger_name trigger ^ " offline, running: Nothing")
        Fetch_rule.Nothing
        (Fetch_rule.decide trigger ~online:false ~running:true ~now))
    Fetch_rule.
      [
        Linked;
        Refresh;
        Opened [];
        Reconnected {states = []; back_online = false};
        Reconnected {states = []; back_online = true};
      ]

(* ---------- offline creation, then reconnection ---------- *)

let offline_creation_then_reconnection () =
  Alcotest.(check action)
    "Linked offline: Nothing" Fetch_rule.Nothing
    (Fetch_rule.decide Fetch_rule.Linked ~online:false ~running:false ~now);
  let p = plant ~gbif_key:(Some 5414995) plant_a in
  Alcotest.(check (list (pair string int)))
    "a never-fetched linked, live plant is pending"
    [(Ids.Plant_id.to_string p.id, 5414995)]
    (pending_pairs (pending ~plants:[p] ~references:[] ()));
  Alcotest.(check action)
    "Reconnected, online, not running: Fetch" Fetch_rule.Fetch
    (Fetch_rule.decide
       (Fetch_rule.Reconnected {states = []; back_online = false})
       ~online:true ~running:false ~now);
  Alcotest.(check action)
    "Reconnected, online, running: Nothing" Fetch_rule.Nothing
    (Fetch_rule.decide
       (Fetch_rule.Reconnected {states = []; back_online = true})
       ~online:true ~running:true ~now)

(* ---------- unfinished ---------- *)

let unfinished_true_when_a_source_has_no_live_row () =
  Alcotest.(check bool) "no rows at all: unfinished" true (unfinished []);
  Alcotest.(check bool)
    "every Fanout.sources row live and Complete: finished" false
    (unfinished (every_source_live ~status:Status.Complete ~fetched_at:now))

let a_failed_wiki_branch_is_pending_after_the_backoff () =
  let search_url =
    match
      Wikidata.search ~property:Wikidata.Property.Gbif_key ~value:"5414995"
    with
    | Some (r : Request.t) -> r.url
    | None -> Alcotest.fail "no search request"
  in
  let net = Fake_net.with_ [(search_url, Step.Failed "x")] digitalis_net in
  let all_rows = fetch_all net in
  let decided = Fanout.decide ~previous:[] all_rows in
  let is_source want (r : Fanout.row) =
    String.equal (Source.to_string r.source) (Source.to_string want)
  in
  let wikidata_row = List.find (is_source Source.Wikidata) decided in
  let wikipedia_row = List.find (is_source Source.Wikipedia) decided in
  Alcotest.check status "wikidata row is Failed" Status.Failed
    wikidata_row.status;
  Alcotest.check status "wikipedia row is Failed" Status.Failed
    wikipedia_row.status;
  let stored ~fetched_at =
    List.map
      (fun (r : Fanout.row) ->
        reference_row ~status:r.status ~source:r.source ~fetched_at r.payload)
      decided
  in
  let p = plant ~gbif_key:(Some 5414995) plant_a in
  let just_now = stored ~fetched_at:(minutes_before 1) in
  Alcotest.(check bool)
    "Failed rows fetched a minute ago: not unfinished yet" false
    (unfinished just_now);
  Alcotest.(check (list (pair string int)))
    "nor pending at startup" []
    (pending_pairs (pending ~plants:[p] ~references:just_now ()));
  Alcotest.(check (list (pair string int)))
    "but pending when the network came back"
    [(Ids.Plant_id.to_string p.id, 5414995)]
    (pending_pairs
       (pending ~back_online:true ~plants:[p] ~references:just_now ()));
  Alcotest.(check action)
    "and fetched by that pass" Fetch_rule.Fetch
    (Fetch_rule.decide
       (Fetch_rule.Reconnected {states = states just_now; back_online = true})
       ~online:true ~running:false ~now);
  Alcotest.(check action)
    "not by the startup pass" Fetch_rule.Nothing
    (Fetch_rule.decide
       (Fetch_rule.Reconnected {states = states just_now; back_online = false})
       ~online:true ~running:false ~now);
  Alcotest.(check action)
    "nor fetched on opening (not due either): Sync_thumbs"
    Fetch_rule.Sync_thumbs
    (Fetch_rule.decide (Fetch_rule.Opened just_now) ~online:true ~running:false
       ~now);
  let at_the_limit = stored ~fetched_at:(minutes_before 10) in
  Alcotest.(check bool)
    "Failed rows exactly failed_retry_after old: not yet (strictly)" false
    (unfinished at_the_limit);
  let earlier = stored ~fetched_at:(minutes_before 11) in
  Alcotest.(check bool)
    "Failed rows older than failed_retry_after: unfinished" true
    (unfinished earlier);
  Alcotest.(check (list (pair string int)))
    "and pending"
    [(Ids.Plant_id.to_string p.id, 5414995)]
    (pending_pairs (pending ~plants:[p] ~references:earlier ()));
  Alcotest.(check action)
    "and fetched on opening, a day before Fanout.due would" Fetch_rule.Fetch
    (Fetch_rule.decide (Fetch_rule.Opened earlier) ~online:true ~running:false
       ~now)

let partial_row_is_not_unfinished () =
  let rows =
    reference_row ~status:Status.Partial ~source:Source.Gbif ~fetched_at:now
      (`Assoc [])
    :: List.filter_map
         (fun source ->
           match source with
           | Source.Gbif -> None
           | _ ->
               Some
                 (reference_row ~status:Status.Complete ~source ~fetched_at:now
                    (`Assoc [])))
         Fanout.sources
  in
  Alcotest.(check bool)
    "a Partial gbif row among otherwise-Complete rows: finished" false
    (unfinished rows)

let missing_row_is_not_unfinished () =
  let rows =
    List.map
      (fun source ->
        match source with
        | Source.Wikipedia ->
            reference_row ~status:Status.Missing ~source ~fetched_at:now
              (`Assoc [])
        | _ ->
            reference_row ~status:Status.Complete ~source ~fetched_at:now
              (`Assoc []))
      Fanout.sources
  in
  Alcotest.(check bool)
    "a Missing wikipedia row among otherwise-Complete rows: finished" false
    (unfinished rows)

let dead_rows_do_not_count_as_live () =
  let rows =
    List.map
      (fun source ->
        match source with
        | Source.Gbif ->
            reference_row ~status:Status.Complete ~source ~fetched_at:now
              ~deleted_at:now (`Assoc [])
        | _ ->
            reference_row ~status:Status.Complete ~source ~fetched_at:now
              (`Assoc []))
      Fanout.sources
  in
  Alcotest.(check bool)
    "a dead (soft-deleted) gbif row leaves gbif without a live row: unfinished"
    true (unfinished rows);
  Alcotest.(check action)
    "Opened reads only the live rows: Fetch" Fetch_rule.Fetch
    (Fetch_rule.decide (Fetch_rule.Opened rows) ~online:true ~running:false ~now)

let powo_rows_are_ignored () =
  let rows =
    every_source_live ~status:Status.Complete ~fetched_at:now
    @ [
        reference_row ~status:Status.Failed ~source:Source.Powo
          ~fetched_at:(minutes_before 60) (`Assoc []);
      ]
  in
  Alcotest.(check bool)
    "every Fanout.sources row live and Complete, plus an old Failed Powo row: \
     still finished"
    false (unfinished rows)

(* ---------- pending ---------- *)

let deleted_or_keyless_plants_never_pending () =
  let deleted = plant ~gbif_key:(Some 1) ~deleted_at:(Some now) (plant_id 3) in
  let keyless = plant ~gbif_key:None (plant_id 4) in
  let ok = plant ~gbif_key:(Some 2) (plant_id 5) in
  Alcotest.(check (list (pair string int)))
    "only the live plant with a gbif_key is pending"
    [(Ids.Plant_id.to_string ok.id, 2)]
    (pending_pairs (pending ~plants:[deleted; keyless; ok] ~references:[] ()))

let pending_orders_by_updated_at_desc_then_id_asc () =
  let p1 =
    plant ~gbif_key:(Some 10)
      ~updated_at:(time "2026-11-10T00:00:00Z")
      (plant_id 1)
  in
  let p3 =
    plant ~gbif_key:(Some 30)
      ~updated_at:(time "2026-11-10T00:00:00Z")
      (plant_id 3)
  in
  let p2 =
    plant ~gbif_key:(Some 20)
      ~updated_at:(time "2026-11-11T00:00:00Z")
      (plant_id 2)
  in
  Alcotest.(check (list (pair string int)))
    "newest updated_at first; a tie broken by id, ascending"
    [
      (Ids.Plant_id.to_string p2.id, 20);
      (Ids.Plant_id.to_string p1.id, 10);
      (Ids.Plant_id.to_string p3.id, 30);
    ]
    (pending_pairs (pending ~plants:[p3; p1; p2] ~references:[] ()))

let references_of_another_plant_are_not_this_plant_s () =
  let p1 = plant ~gbif_key:(Some 1) plant_a in
  let p2 = plant ~gbif_key:(Some 2) plant_b in
  let p2_refs =
    List.map
      (fun source ->
        reference_row ~plant:plant_b ~source ~fetched_at:now (`Assoc []))
      Fanout.sources
  in
  Alcotest.(check (list (pair string int)))
    "p1 has no rows of its own (p2's rows don't count for it): p1 pending, p2 \
     finished"
    [(Ids.Plant_id.to_string p1.id, 1)]
    (pending_pairs (pending ~plants:[p1; p2] ~references:p2_refs ()))

(* ---------- Opened, Refresh ---------- *)

let opened_due_not_due_and_running () =
  Alcotest.(check action)
    "Opened, due (no rows), not running: Fetch" Fetch_rule.Fetch
    (Fetch_rule.decide (Fetch_rule.Opened []) ~online:true ~running:false ~now);
  let fresh = every_source_live ~status:Status.Complete ~fetched_at:now in
  Alcotest.(check bool)
    "sanity: these rows are not due" false (Fanout.due ~now fresh);
  Alcotest.(check action)
    "Opened, fresh complete rows (not due), not running: Sync_thumbs"
    Fetch_rule.Sync_thumbs
    (Fetch_rule.decide (Fetch_rule.Opened fresh) ~online:true ~running:false
       ~now);
  Alcotest.(check action)
    "Opened, running (due rows): Nothing" Fetch_rule.Nothing
    (Fetch_rule.decide (Fetch_rule.Opened []) ~online:true ~running:true ~now);
  Alcotest.(check action)
    "Opened, running (fresh rows): Nothing" Fetch_rule.Nothing
    (Fetch_rule.decide (Fetch_rule.Opened fresh) ~online:true ~running:true ~now)

let refresh_fetches_unless_running () =
  Alcotest.(check action)
    "Refresh, not running: Fetch" Fetch_rule.Fetch
    (Fetch_rule.decide Fetch_rule.Refresh ~online:true ~running:false ~now);
  Alcotest.(check action)
    "Refresh, running: Nothing" Fetch_rule.Nothing
    (Fetch_rule.decide Fetch_rule.Refresh ~online:true ~running:true ~now)

(* ---------- run ---------- *)

let case name f = (name, `Quick, f)

let suite =
  ( "fetch_rule",
    [
      case
        "Linked decides Fetch, the fan-out covers every source and its hosts, \
         and the plant is no longer pending once it settles"
        linked_fetches_and_the_fan_out_covers_every_source;
      case
        "decide: running supersedes for Linked; offline is Nothing for every \
         trigger, running or not"
        decide_running_and_offline;
      case
        "offline creation then reconnection: pending, then Fetch unless running"
        offline_creation_then_reconnection;
      case
        "unfinished: [] is unfinished; every Fanout.sources row live and \
         Complete is finished"
        unfinished_true_when_a_source_has_no_live_row;
      case
        "a fetch whose wiki branch failed: pending when the network came back; \
         at startup and on opening once older than failed_retry_after, not \
         before"
        a_failed_wiki_branch_is_pending_after_the_backoff;
      case "a Partial row among Complete ones is not unfinished"
        partial_row_is_not_unfinished;
      case "a Missing row among Complete ones is not unfinished"
        missing_row_is_not_unfinished;
      case "a dead (soft-deleted) row does not count as a live row"
        dead_rows_do_not_count_as_live;
      case "a row of a source outside Fanout.sources (Powo) is ignored"
        powo_rows_are_ignored;
      case "a deleted plant or one without a gbif_key is never pending"
        deleted_or_keyless_plants_never_pending;
      case "pending orders by updated_at descending, ties by id ascending"
        pending_orders_by_updated_at_desc_then_id_asc;
      case "pending reads each plant's own rows only, by plant_id"
        references_of_another_plant_are_not_this_plant_s;
      case
        "Opened: Fetch when due, Sync_thumbs when fresh, Nothing when running"
        opened_due_not_due_and_running;
      case "Refresh: Fetch unless running" refresh_fetches_unless_running;
    ] )
