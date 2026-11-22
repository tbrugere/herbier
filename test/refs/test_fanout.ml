(* Herbier_refs.Fanout: the three branches of one gbif_key's fetch, over
   Fake_net; the decide (keep/merge) rule; the due rule. *)

module Value = Herbier_test_support.Value
module Fanout = Herbier_refs.Fanout
module Step = Herbier_refs.Step
module Request = Herbier_refs.Request
module Decode = Herbier_refs.Decode
module Payload = Herbier_refs.Payload
module Projection = Herbier_refs.Projection
module Gbif = Herbier_refs.Sources.Gbif
module Wikidata = Herbier_refs.Sources.Wikidata
module Wikipedia = Herbier_refs.Sources.Wikipedia
module Qid = Herbier_refs.Qid
module Ids = Herbier_domain.Ids
module Reference = Herbier_domain.Reference
module Source = Herbier_domain.Reference.Source
module Status = Herbier_domain.Reference.Status
module Fixture = Herbier_test_support.Fixture

let some name = function
  | Some r -> r
  | None -> Alcotest.failf "%s: expected Some" name

let url (r : Request.t) = Request.(r.url)

(* ---------- time, plant, reference rows ---------- *)

let plant =
  match Ids.Plant_id.of_string "00000000-0000-4000-8000-000000000001" with
  | Some x -> x
  | None -> invalid_arg "plant id"

let time = Value.time
let now = time "2026-11-12T00:00:00Z"

let reference_row ?(status = Status.Complete) ?deleted_at ~source ~fetched_at
    payload : Reference.t =
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

let fixture_body file : Yojson.Safe.t =
  match Decode.json_of_string (Fixture.read file) with
  | Ok j -> j
  | Error e -> Alcotest.failf "%s: %s" file (Decode.error_to_string e)

(* ---------- testables ---------- *)

let status =
  Alcotest.testable
    (fun f s -> Format.pp_print_string f (Status.to_string s))
    (fun a b -> String.equal (Status.to_string a) (Status.to_string b))

let row_json (r : Fanout.row) =
  `Assoc
    [
      ("source", `String (Source.to_string r.source));
      ("status", `String (Status.to_string r.status));
      ("payload", r.payload);
    ]

let row =
  Alcotest.testable
    (fun f r ->
      Format.pp_print_string f (Yojson.Safe.pretty_to_string (row_json r)))
    Fanout.equal_row

let rows = Alcotest.list row

let sources (rs : Fanout.row list) =
  List.map (fun (r : Fanout.row) -> Source.to_string r.source) rs

let members = function `Assoc kvs -> List.map fst kvs | _ -> []

let find_row (rs : Fanout.row list) source =
  let name = Source.to_string source in
  match
    List.find_opt
      (fun (r : Fanout.row) -> String.equal (Source.to_string r.source) name)
      rs
  with
  | Some r -> r
  | None ->
      Alcotest.failf "no %s row among [%s]" name
        (String.concat ", " (sources rs))

let branches3 gbif_key =
  match Fanout.branches ~gbif_key with
  | [g; p; w] -> (g, p, w)
  | bs -> Alcotest.failf "expected 3 branches, got %d" (List.length bs)

let requests_of net prog =
  List.map (fun (r : Request.t) -> r.url) (Step.requests net prog)

(* ---------- full fetch of each spike species ---------- *)

let full_fetch ~gbif_key ~net ~entity_qid ~summary_title ~taxon_key ~extract_en
    ~empty_fields =
  let gbif_b, plantnet_b, wiki_b = branches3 gbif_key in
  let gbif_rows = Step.run net gbif_b in
  let plantnet_rows = Step.run net plantnet_b in
  let wiki_rows = Step.run net wiki_b in
  List.iter
    (fun (r : Fanout.row) ->
      Alcotest.check status
        (Source.to_string r.source ^ ": complete")
        Status.Complete r.status)
    (gbif_rows @ plantnet_rows @ wiki_rows);
  Alcotest.(check (list string))
    "gbif branch requests, in order"
    [
      url (Gbif.species ~key:gbif_key);
      url (Gbif.vernacular_names ~key:gbif_key);
      url (Gbif.distributions ~key:gbif_key);
      url (Gbif.occurrence_count ~key:gbif_key);
    ]
    (requests_of net gbif_b);
  Alcotest.(check (list string))
    "plantnet branch requests"
    [url (Gbif.plantnet_media ~key:gbif_key)]
    (requests_of net plantnet_b);
  Alcotest.(check (list string))
    "wiki branch requests, in order"
    ([
       url
         (some "search"
            (Wikidata.search ~property:Wikidata.Property.Gbif_key
               ~value:(string_of_int gbif_key)));
       url (Wikidata.entity (some "qid" (Qid.of_string entity_qid)));
       url (some "summary" (Wikipedia.summary ~lang:"fr" ~title:summary_title));
       url
         (some "extract fr" (Wikipedia.extract ~lang:"fr" ~title:summary_title));
     ]
    @
    match extract_en with
    | false -> []
    | true ->
        [
          url
            (some "extract en"
               (Wikipedia.extract ~lang:"en" ~title:summary_title));
        ])
    (requests_of net wiki_b);
  let all_rows = gbif_rows @ plantnet_rows @ wiki_rows in
  let decided = Fanout.decide ~previous:[] all_rows in
  let refs =
    List.map
      (fun (r : Fanout.row) ->
        reference_row ~source:r.source ~status:r.status
          ~fetched_at:(time "2026-11-01T10:00:00Z")
          r.payload)
      decided
  in
  let proj = Projection.project ~references:refs ~plant_refs:[] in
  (match proj.taxon with
  | Some {value; _} -> Alcotest.(check int) "taxon key" taxon_key value.key
  | None -> Alcotest.fail "taxon is None");
  Alcotest.(check (list string))
    "empty_fields"
    (List.map Projection.Field.to_string empty_fields)
    (List.map Projection.Field.to_string (Projection.empty_fields proj))

let digitalis_full_fetch () =
  full_fetch ~gbif_key:5414995 ~net:Fake_net.digitalis ~entity_qid:"Q157555"
    ~summary_title:"Digitalis purpurea" ~taxon_key:5414995 ~extract_en:true
    ~empty_fields:
      Projection.Field.
        [
          Life_form;
          Fr_status;
          Fr_protection;
          Red_list;
          Flowering_months;
          Habitat;
          Ecology;
        ]

let arnica_full_fetch () =
  full_fetch ~gbif_key:5405976 ~net:Fake_net.arnica ~entity_qid:"Q207848"
    ~summary_title:"Arnica des montagnes" ~taxon_key:5405976 ~extract_en:false
    ~empty_fields:
      Projection.Field.
        [
          Life_form;
          Fr_status;
          Fr_protection;
          Flowering_months;
          Habitat;
          Ecology;
          Toxicity;
        ]

(* ---------- payload equality ---------- *)

let payload_equality () =
  let gbif_b, plantnet_b, wiki_b = branches3 5414995 in
  let net = Fake_net.digitalis in
  let gbif_row = find_row (Step.run net gbif_b) Source.Gbif in
  let plantnet_row = find_row (Step.run net plantnet_b) Source.Plantnet in
  let wiki_rows = Step.run net wiki_b in
  let wikidata_row = find_row wiki_rows Source.Wikidata in
  let wikipedia_row = find_row wiki_rows Source.Wikipedia in
  Alcotest.(check bool)
    "gbif payload" true
    (Yojson.Safe.equal gbif_row.payload
       (Payload.gbif
          ~species:(Some (fixture_body "gbif_species_5414995.json"))
          ~vernacular_names:
            (Some (fixture_body "gbif_vernacular_names_5414995.json"))
          ~distributions:(Some (fixture_body "gbif_distributions_5414995.json"))
          ~occurrence_count:
            (Some (fixture_body "gbif_occurrence_count_5414995.json"))));
  Alcotest.(check bool)
    "plantnet payload" true
    (Yojson.Safe.equal plantnet_row.payload
       (Payload.plantnet
          ~media:(Some (fixture_body "gbif_plantnet_media_5414995.json"))));
  Alcotest.(check bool)
    "wikidata payload" true
    (Yojson.Safe.equal wikidata_row.payload
       (Payload.wikidata
          ~search:(Some (fixture_body "wikidata_search_p846_5414995.json"))
          ~entity:(Some (fixture_body "wikidata_entity_Q157555.json"))));
  Alcotest.(check bool)
    "wikipedia payload: summary fr, uses the en extract (fr has no section)"
    true
    (Yojson.Safe.equal wikipedia_row.payload
       (Payload.wikipedia
          ~summary:
            (Some (fixture_body "wikipedia_summary_fr_Digitalis_purpurea.json"))
          ~uses:
            (Some (fixture_body "wikipedia_extract_en_Digitalis_purpurea.json"))))

(* ---------- gbif branch degradation ---------- *)

let gbif_species_absent () =
  let gbif_b, _, _ = branches3 5414995 in
  let net =
    Fake_net.with_
      [(url (Gbif.species ~key:5414995), Step.Absent)]
      Fake_net.digitalis
  in
  match Step.run net gbif_b with
  | [r] ->
      Alcotest.check status "missing" Status.Missing r.status;
      Alcotest.(check bool)
        "empty payload" true
        (Yojson.Safe.equal r.payload (`Assoc []));
      Alcotest.(check int)
        "exactly one request" 1
        (List.length (requests_of net gbif_b))
  | rs -> Alcotest.failf "expected 1 row, got %d" (List.length rs)

let gbif_partial_distributions_failed () =
  let gbif_b, _, _ = branches3 5414995 in
  let net =
    Fake_net.with_
      [(url (Gbif.distributions ~key:5414995), Step.Failed "x")]
      Fake_net.digitalis
  in
  match Step.run net gbif_b with
  | [r] ->
      Alcotest.check status "partial" Status.Partial r.status;
      Alcotest.(check (list string))
        "species, vernacular_names, occurrence_count, no distributions"
        ["species"; "vernacular_names"; "occurrence_count"]
        (members r.payload)
  | rs -> Alcotest.failf "expected 1 row, got %d" (List.length rs)

let gbif_failed_others_unaffected () =
  let gbif_b, plantnet_b, wiki_b = branches3 5414995 in
  let fail u = (u, Step.Failed "x") in
  let net =
    Fake_net.with_
      [
        fail (url (Gbif.species ~key:5414995));
        fail (url (Gbif.vernacular_names ~key:5414995));
        fail (url (Gbif.distributions ~key:5414995));
        fail (url (Gbif.occurrence_count ~key:5414995));
      ]
      Fake_net.digitalis
  in
  (match Step.run net gbif_b with
  | [r] ->
      Alcotest.check status "failed" Status.Failed r.status;
      Alcotest.(check bool)
        "empty payload" true
        (Yojson.Safe.equal r.payload (`Assoc []))
  | rs -> Alcotest.failf "expected 1 row, got %d" (List.length rs));
  Alcotest.check rows "plantnet branch unchanged"
    (Step.run Fake_net.digitalis plantnet_b)
    (Step.run net plantnet_b);
  Alcotest.check rows "wiki branch unchanged"
    (Step.run Fake_net.digitalis wiki_b)
    (Step.run net wiki_b)

let gbif_undecodable_occurrence_count () =
  let gbif_b, _, _ = branches3 5414995 in
  let net =
    Fake_net.with_
      [(url (Gbif.occurrence_count ~key:5414995), Step.Body (`String "x"))]
      Fake_net.digitalis
  in
  match Step.run net gbif_b with
  | [r] ->
      Alcotest.check status "partial" Status.Partial r.status;
      Alcotest.(check (list string))
        "no occurrence_count member"
        ["species"; "vernacular_names"; "distributions"]
        (members r.payload)
  | rs -> Alcotest.failf "expected 1 row, got %d" (List.length rs)

(* ---------- plantnet ---------- *)

let plantnet_missing () =
  let _, plantnet_b, _ = branches3 1 in
  let net =
    Fake_net.fixtures
      [(url (Gbif.plantnet_media ~key:1), "gbif_plantnet_media_1.json")]
  in
  match Step.run net plantnet_b with
  | [r] ->
      Alcotest.check status "missing" Status.Missing r.status;
      Alcotest.(check bool)
        "payload holds the media member" true
        (Option.is_some (Payload.get Payload.Plantnet_media r.payload))
  | rs -> Alcotest.failf "expected 1 row, got %d" (List.length rs)

(* ---------- wikidata/wikipedia branch ---------- *)

let wikidata_search_failed () =
  let _, _, wiki_b = branches3 5414995 in
  let net =
    Fake_net.with_
      [
        ( url
            (some "search"
               (Wikidata.search ~property:Wikidata.Property.Gbif_key
                  ~value:"5414995")),
          Step.Failed "x" );
      ]
      Fake_net.digitalis
  in
  (match Step.run net wiki_b with
  | [r; w] ->
      Alcotest.(check string) "source" "wikidata" (Source.to_string r.source);
      Alcotest.check status "failed" Status.Failed r.status;
      Alcotest.(check string)
        "second source" "wikipedia"
        (Source.to_string w.source);
      Alcotest.check status "wikipedia failed" Status.Failed w.status;
      Alcotest.(check bool)
        "wikipedia payload empty" true
        (Yojson.Safe.equal w.payload (`Assoc []))
  | rs ->
      Alcotest.failf "expected [wikidata; wikipedia], got %d rows"
        (List.length rs));
  Alcotest.(check int)
    "the search alone" 1
    (List.length (requests_of net wiki_b))

let wikidata_no_item () =
  let _, _, wiki_b = branches3 999999999 in
  let net =
    Fake_net.fixtures
      [
        ( url
            (some "search"
               (Wikidata.search ~property:Wikidata.Property.Gbif_key
                  ~value:"999999999")),
          "wikidata_search_p846_999999999.json" );
      ]
  in
  match Step.run net wiki_b with
  | [wikidata_row; wikipedia_row] ->
      Alcotest.(check string)
        "first source" "wikidata"
        (Source.to_string wikidata_row.source);
      Alcotest.check status "wikidata missing" Status.Missing
        wikidata_row.status;
      Alcotest.(check string)
        "second source" "wikipedia"
        (Source.to_string wikipedia_row.source);
      Alcotest.check status "wikipedia missing" Status.Missing
        wikipedia_row.status;
      Alcotest.(check bool)
        "wikipedia payload empty" true
        (Yojson.Safe.equal wikipedia_row.payload (`Assoc []));
      Alcotest.(check int)
        "the search alone, no entity call" 1
        (List.length (requests_of net wiki_b))
  | rs ->
      Alcotest.failf "expected [wikidata; wikipedia], got %d rows"
        (List.length rs)

let wikidata_entity_failed () =
  let _, _, wiki_b = branches3 5414995 in
  let qid = some "qid" (Qid.of_string "Q157555") in
  let net =
    Fake_net.with_
      [(url (Wikidata.entity qid), Step.Failed "x")]
      Fake_net.digitalis
  in
  match Step.run net wiki_b with
  | [r; w] ->
      Alcotest.(check string) "source" "wikidata" (Source.to_string r.source);
      Alcotest.check status "partial" Status.Partial r.status;
      Alcotest.(check string)
        "second source" "wikipedia"
        (Source.to_string w.source);
      Alcotest.check status "wikipedia failed" Status.Failed w.status
  | rs ->
      Alcotest.failf "expected [wikidata; wikipedia], got %d rows"
        (List.length rs)

let fr_absent_falls_back_to_en () =
  let _, _, wiki_b = branches3 5414995 in
  let en_body = fixture_body "wikipedia_summary_en_Digitalis_purpurea.json" in
  let net =
    Fake_net.with_
      [
        ( url
            (some "fr"
               (Wikipedia.summary ~lang:"fr" ~title:"Digitalis purpurea")),
          Step.Absent );
        ( url
            (some "en"
               (Wikipedia.summary ~lang:"en" ~title:"Digitalis purpurea")),
          Step.Body en_body );
      ]
      Fake_net.digitalis
  in
  match Step.run net wiki_b with
  | [_wikidata_row; wikipedia_row] ->
      Alcotest.check status "complete" Status.Complete wikipedia_row.status;
      (* The summary outcome is Complete (not Failed), so the uses step still
         runs over the base digitalis fixtures: fr has no section, en does. *)
      Alcotest.(check bool)
        "payload summary is the en body, uses is the en extract" true
        (Yojson.Safe.equal wikipedia_row.payload
           (Payload.wikipedia ~summary:(Some en_body)
              ~uses:
                (Some
                   (fixture_body "wikipedia_extract_en_Digitalis_purpurea.json"))))
  | rs ->
      Alcotest.failf "expected [wikidata; wikipedia], got %d rows"
        (List.length rs)

let fr_and_en_absent_is_missing () =
  let _, _, wiki_b = branches3 5414995 in
  let net =
    Fake_net.with_
      [
        ( url
            (some "fr"
               (Wikipedia.summary ~lang:"fr" ~title:"Digitalis purpurea")),
          Step.Absent );
        ( url
            (some "en"
               (Wikipedia.summary ~lang:"en" ~title:"Digitalis purpurea")),
          Step.Absent );
      ]
      Fake_net.digitalis
  in
  match Step.run net wiki_b with
  | [_; wikipedia_row] ->
      Alcotest.check status "missing" Status.Missing wikipedia_row.status
  | rs ->
      Alcotest.failf "expected [wikidata; wikipedia], got %d rows"
        (List.length rs)

let fr_failed_no_en_attempt () =
  let _, _, wiki_b = branches3 5414995 in
  let net =
    Fake_net.with_
      [
        ( url
            (some "fr"
               (Wikipedia.summary ~lang:"fr" ~title:"Digitalis purpurea")),
          Step.Failed "x" );
      ]
      Fake_net.digitalis
  in
  (match Step.run net wiki_b with
  | [_; wikipedia_row] ->
      Alcotest.check status "failed" Status.Failed wikipedia_row.status
  | rs ->
      Alcotest.failf "expected [wikidata; wikipedia], got %d rows"
        (List.length rs));
  Alcotest.(check int)
    "search, entity, fr summary: no en request" 3
    (List.length (requests_of net wiki_b))

(* ---------- decide ---------- *)

let live_previous_for sources =
  List.map
    (fun source ->
      reference_row ~source
        ~fetched_at:(time "2026-10-01T00:00:00Z")
        (`Assoc []))
    sources

let decide_drops_failed_with_live_previous () =
  let gbif_b, plantnet_b, wiki_b = branches3 5414995 in
  let fail u = (u, Step.Failed "x") in
  let net =
    Fake_net.with_
      [
        fail (url (Gbif.species ~key:5414995));
        fail (url (Gbif.vernacular_names ~key:5414995));
        fail (url (Gbif.distributions ~key:5414995));
        fail (url (Gbif.occurrence_count ~key:5414995));
      ]
      Fake_net.digitalis
  in
  let all_rows =
    Step.run net gbif_b @ Step.run net plantnet_b @ Step.run net wiki_b
  in
  let previous =
    live_previous_for
      [Source.Gbif; Source.Plantnet; Source.Wikidata; Source.Wikipedia]
  in
  let decided = Fanout.decide ~previous all_rows in
  Alcotest.(check (list string))
    "plantnet, wikidata, wikipedia kept; gbif dropped"
    ["plantnet"; "wikidata"; "wikipedia"]
    (sources decided)

let decide_failed_soft_deleted_previous_kept () =
  let failed_row : Fanout.row =
    {Fanout.source = Source.Gbif; status = Status.Failed; payload = `Assoc []}
  in
  let previous =
    [
      reference_row ~source:Source.Gbif
        ~deleted_at:(time "2026-10-01T00:00:00Z")
        ~fetched_at:(time "2026-10-01T00:00:00Z")
        (`Assoc [("x", `Int 1)]);
    ]
  in
  match Fanout.decide ~previous [failed_row] with
  | [r] ->
      Alcotest.check status "failed" Status.Failed r.status;
      Alcotest.(check bool)
        "empty payload" true
        (Yojson.Safe.equal r.payload (`Assoc []))
  | rs -> Alcotest.failf "expected 1 row, got %d" (List.length rs)

let decide_failed_no_previous_kept () =
  let failed_row : Fanout.row =
    {Fanout.source = Source.Gbif; status = Status.Failed; payload = `Assoc []}
  in
  match Fanout.decide ~previous:[] [failed_row] with
  | [r] -> Alcotest.check status "failed" Status.Failed r.status
  | rs -> Alcotest.failf "expected 1 row, got %d" (List.length rs)

let decide_failed_over_failed_replaces_it () =
  let species = `Assoc [("k", `Int 1)] in
  let failed_row : Fanout.row =
    {Fanout.source = Source.Gbif; status = Status.Failed; payload = `Assoc []}
  in
  let previous =
    [
      reference_row ~status:Status.Failed ~source:Source.Gbif
        ~fetched_at:(time "2026-10-01T00:00:00Z")
        (Payload.gbif ~species:(Some species) ~vernacular_names:None
           ~distributions:None ~occurrence_count:None);
    ]
  in
  match Fanout.decide ~previous [failed_row] with
  | [r] ->
      Alcotest.check status "failed" Status.Failed r.status;
      Alcotest.(check bool)
        "the stored members are kept" true
        (Yojson.Safe.equal r.payload
           (Payload.gbif ~species:(Some species) ~vernacular_names:None
              ~distributions:None ~occurrence_count:None))
  | rs -> Alcotest.failf "expected 1 row, got %d" (List.length rs)

let decide_partial_merges_previous_distributions () =
  let previous_payload =
    Payload.gbif
      ~species:(Some (`Assoc [("k", `Int 1)]))
      ~vernacular_names:None
      ~distributions:(Some (`Assoc [("locationId", `String "X")]))
      ~occurrence_count:None
  in
  let previous =
    [
      reference_row ~source:Source.Gbif
        ~fetched_at:(time "2026-10-01T00:00:00Z")
        previous_payload;
    ]
  in
  let new_payload =
    Payload.gbif
      ~species:(Some (`Assoc [("k", `Int 2)]))
      ~vernacular_names:None ~distributions:None
      ~occurrence_count:(Some (`Int 5))
  in
  let partial_row : Fanout.row =
    {
      Fanout.source = Source.Gbif;
      status = Status.Partial;
      payload = new_payload;
    }
  in
  let expected =
    Payload.gbif
      ~species:(Some (`Assoc [("k", `Int 2)]))
      ~vernacular_names:None
      ~distributions:(Some (`Assoc [("locationId", `String "X")]))
      ~occurrence_count:(Some (`Int 5))
  in
  match Fanout.decide ~previous [partial_row] with
  | [r] ->
      Alcotest.check status "still partial" Status.Partial r.status;
      Alcotest.(check (list string))
        "new members plus previous distributions, Payload.all order"
        ["species"; "distributions"; "occurrence_count"]
        (members r.payload);
      Alcotest.(check bool)
        "the new species wins over the previous one" true
        (Yojson.Safe.equal r.payload expected)
  | rs -> Alcotest.failf "expected 1 row, got %d" (List.length rs)

let decide_partial_soft_deleted_previous_unchanged () =
  let previous =
    [
      reference_row ~source:Source.Gbif
        ~deleted_at:(time "2026-10-02T00:00:00Z")
        ~fetched_at:(time "2026-10-01T00:00:00Z")
        (Payload.gbif
           ~species:(Some (`Assoc [("k", `Int 1)]))
           ~vernacular_names:None
           ~distributions:(Some (`Assoc [("locationId", `String "X")]))
           ~occurrence_count:None);
    ]
  in
  let payload =
    Payload.gbif
      ~species:(Some (`Assoc [("k", `Int 2)]))
      ~vernacular_names:None ~distributions:None
      ~occurrence_count:(Some (`Int 5))
  in
  let partial_row : Fanout.row =
    {Fanout.source = Source.Gbif; status = Status.Partial; payload}
  in
  match Fanout.decide ~previous [partial_row] with
  | [r] ->
      Alcotest.(check bool)
        "payload unchanged" true
        (Yojson.Safe.equal r.payload payload);
      Alcotest.(check bool)
        "no distributions borrowed from the dead row" false
        (List.mem "distributions" (members r.payload))
  | rs -> Alcotest.failf "expected 1 row, got %d" (List.length rs)

let decide_partial_no_previous_unchanged () =
  let payload =
    Payload.gbif
      ~species:(Some (`Assoc []))
      ~vernacular_names:None ~distributions:None ~occurrence_count:None
  in
  let partial_row : Fanout.row =
    {Fanout.source = Source.Gbif; status = Status.Partial; payload}
  in
  match Fanout.decide ~previous:[] [partial_row] with
  | [r] ->
      Alcotest.(check bool)
        "payload unchanged" true
        (Yojson.Safe.equal r.payload payload)
  | rs -> Alcotest.failf "expected 1 row, got %d" (List.length rs)

let decide_complete_and_missing_ignore_previous () =
  let previous = live_previous_for [Source.Gbif; Source.Plantnet] in
  let complete : Fanout.row =
    {
      Fanout.source = Source.Gbif;
      status = Status.Complete;
      payload = `Assoc [("x", `Int 1)];
    }
  in
  let missing : Fanout.row =
    {
      Fanout.source = Source.Plantnet;
      status = Status.Missing;
      payload = `Assoc [];
    }
  in
  match Fanout.decide ~previous [complete; missing] with
  | [r1; r2] ->
      Alcotest.(check bool)
        "complete payload unchanged" true
        (Yojson.Safe.equal r1.payload complete.payload);
      Alcotest.(check bool)
        "missing payload unchanged" true
        (Yojson.Safe.equal r2.payload missing.payload)
  | rs -> Alcotest.failf "expected 2 rows, got %d" (List.length rs)

let decide_input_order_kept () =
  let r1 : Fanout.row =
    {
      Fanout.source = Source.Wikipedia;
      status = Status.Complete;
      payload = `Assoc [];
    }
  in
  let r2 : Fanout.row =
    {Fanout.source = Source.Gbif; status = Status.Complete; payload = `Assoc []}
  in
  Alcotest.(check (list string))
    "order kept, whatever previous's own order" ["wikipedia"; "gbif"]
    (sources
       (Fanout.decide ~previous:(live_previous_for [Source.Gbif]) [r1; r2]))

(* ---------- due ---------- *)

(* The four sources without the regional layer: a plant with no Taxref/Tela
   row at all is [due] on that alone (so it refetches once, picking up the
   regional layer). *)
let four_sources =
  [Source.Gbif; Source.Plantnet; Source.Wikidata; Source.Wikipedia]

let fresh_four () =
  List.map
    (fun source ->
      reference_row ~source
        ~fetched_at:(time "2026-11-11T00:00:00Z")
        (`Assoc []))
    four_sources

let six_sources =
  [
    Source.Gbif;
    Source.Plantnet;
    Source.Wikidata;
    Source.Wikipedia;
    Source.Taxref;
    Source.Tela;
  ]

let fresh_six () =
  List.map
    (fun source ->
      reference_row ~source
        ~fetched_at:(time "2026-11-11T00:00:00Z")
        (`Assoc []))
    six_sources

(* [Fanout.sources] has Plantuse after Tela. A plant fetched before Plantuse
   was a source only has the six rows of [fresh_six]; [fresh_seven] is the
   up-to-date baseline used where a test wants "every source fresh" to mean
   genuinely not due. *)
let seven_sources = six_sources @ [Source.Plantuse]

let fresh_seven () =
  List.map
    (fun source ->
      reference_row ~source
        ~fetched_at:(time "2026-11-11T00:00:00Z")
        (`Assoc []))
    seven_sources

let set_first f rows =
  List.mapi (fun i (r : Reference.t) -> match i with 0 -> f r | _ -> r) rows

let due_no_rows () = Alcotest.(check bool) "due" true (Fanout.due ~now [])

let due_four_sources_alone () =
  Alcotest.(check bool)
    "the four old sources alone: due (Taxref/Tela have no live row)" true
    (Fanout.due ~now (fresh_four ()))

let due_missing_a_source () =
  let five = List.filteri (fun i _ -> i < 5) (fresh_six ()) in
  Alcotest.(check bool) "a source has no live row" true (Fanout.due ~now five)

let due_max_age () =
  Alcotest.(check bool)
    "all fresh (1 day)" false
    (Fanout.due ~now (fresh_seven ()));
  Alcotest.(check bool)
    "one row 91 days old" true
    (Fanout.due ~now
       (set_first
          (fun r -> {r with Reference.fetched_at = time "2026-08-13T00:00:00Z"})
          (fresh_seven ())));
  Alcotest.(check bool)
    "exactly 90 days: not strictly over" false
    (Fanout.due ~now
       (set_first
          (fun r -> {r with Reference.fetched_at = time "2026-08-14T00:00:00Z"})
          (fresh_seven ())))

let due_failed_or_partial_retry () =
  let aged st age rows =
    set_first
      (fun r -> {r with Reference.status = st; fetched_at = time age})
      rows
  in
  Alcotest.(check bool)
    "failed 2 days old" true
    (Fanout.due ~now
       (aged Status.Failed "2026-11-10T00:00:00Z" (fresh_seven ())));
  Alcotest.(check bool)
    "failed 1 hour old" false
    (Fanout.due ~now
       (aged Status.Failed "2026-11-11T23:00:00Z" (fresh_seven ())));
  Alcotest.(check bool)
    "partial 2 days old" true
    (Fanout.due ~now
       (aged Status.Partial "2026-11-10T00:00:00Z" (fresh_seven ())));
  Alcotest.(check bool)
    "partial 1 hour old" false
    (Fanout.due ~now
       (aged Status.Partial "2026-11-11T23:00:00Z" (fresh_seven ())));
  Alcotest.(check bool)
    "failed exactly 1 day old: not strictly over" false
    (Fanout.due ~now
       (aged Status.Failed "2026-11-11T00:00:00Z" (fresh_seven ())));
  Alcotest.(check bool)
    "failed 1 day and 1 s old" true
    (Fanout.due ~now
       (aged Status.Failed "2026-11-10T23:59:59Z" (fresh_seven ())));
  Alcotest.(check bool)
    "partial exactly 1 day old: not strictly over" false
    (Fanout.due ~now
       (aged Status.Partial "2026-11-11T00:00:00Z" (fresh_seven ())));
  Alcotest.(check bool)
    "partial 1 day and 1 s old" true
    (Fanout.due ~now
       (aged Status.Partial "2026-11-10T23:59:59Z" (fresh_seven ())))

let due_missing_tela_not_due () =
  let rows =
    List.map
      (fun (r : Reference.t) ->
        match r.source with
        | Source.Tela ->
            {
              r with
              Reference.status = Status.Missing;
              fetched_at = time "2026-11-02T00:00:00Z";
            }
        | _ -> r)
      (fresh_seven ())
  in
  Alcotest.(check bool)
    "a Missing tela row 10 days old is not due on its own" false
    (Fanout.due ~now rows)

(* A fetch whose Wikidata search failed stores every source (none had a
   row), so the plant is not due again before the one-day retry. *)
let due_after_wikidata_search_failed () =
  let gbif_b, plantnet_b, wiki_b = branches3 5414995 in
  let net =
    Fake_net.with_
      [
        ( url
            (some "search"
               (Wikidata.search ~property:Wikidata.Property.Gbif_key
                  ~value:"5414995")),
          Step.Failed "x" );
      ]
      Fake_net.digitalis
  in
  let fetched_at = time "2026-11-11T23:00:00Z" in
  (* A real fetch always runs the regional program and Uses_fetch too: add
     the Taxref/Tela/Plantuse rows they would also have stored. *)
  let regional_rows =
    List.map
      (fun source -> reference_row ~source ~fetched_at (`Assoc []))
      [Source.Taxref; Source.Tela; Source.Plantuse]
  in
  let stored =
    List.map
      (fun (r : Fanout.row) ->
        reference_row ~status:r.status ~source:r.source ~fetched_at r.payload)
      (Fanout.decide ~previous:[]
         (Step.run net gbif_b @ Step.run net plantnet_b @ Step.run net wiki_b))
    @ regional_rows
  in
  Alcotest.(check bool) "not due 1 hour later" false (Fanout.due ~now stored)

let due_missing_row_not_due () =
  let rows =
    set_first
      (fun r ->
        {
          r with
          Reference.status = Status.Missing;
          fetched_at = time "2026-11-02T00:00:00Z";
        })
      (fresh_seven ())
  in
  Alcotest.(check bool) "a missing row 10 days old" false (Fanout.due ~now rows)

let due_soft_deleted_ignored () =
  let rows =
    set_first
      (fun r ->
        {r with Reference.deleted_at = Some (time "2026-11-11T00:00:00Z")})
      (fresh_seven ())
  in
  Alcotest.(check bool)
    "a soft-deleted gbif row: due as if that source were absent" true
    (Fanout.due ~now rows)

let due_future_fetched_at_ignored () =
  let rows =
    set_first
      (fun r -> {r with Reference.fetched_at = time "2026-11-12T01:00:00Z"})
      (fresh_seven ())
  in
  Alcotest.(check bool)
    "a fresh row dated after now is not due because of it" false
    (Fanout.due ~now rows)

let due_other_source_ignored () =
  let powo =
    reference_row ~source:Source.Powo
      ~fetched_at:(time "2026-04-26T00:00:00Z")
      (`Assoc [])
  in
  Alcotest.(check bool)
    "an extra Powo row (outside Fanout.sources) is ignored" false
    (Fanout.due ~now (powo :: fresh_seven ()))

(* A plant fetched before Plantuse was a source has no plantuse row at all:
   it is due once, even though every other source is fresh. *)
let due_backfill_no_plantuse_row () =
  Alcotest.(check bool)
    "every other source fresh, no plantuse row: due" true
    (Fanout.due ~now (fresh_six ()))

let case name f = (name, `Quick, f)

(* ---------- remaining status paths ---------- *)

let qid157555 () = some "qid" (Qid.of_string "Q157555")
let entity_url () = url (Wikidata.entity (qid157555 ()))

let fr_summary_url () =
  url (some "fr" (Wikipedia.summary ~lang:"fr" ~title:"Digitalis purpurea"))

let en_summary_url () =
  url (some "en" (Wikipedia.summary ~lang:"en" ~title:"Digitalis purpurea"))

let entity_body () = Fake_net.json_of_fixture "wikidata_entity_Q157555.json"
let sitelink lang = ["entities"; "Q157555"; "sitelinks"; lang ^ "wiki"]

let plantnet_media_not_decoded_is_failed () =
  let _, plantnet_b, _ = branches3 5414995 in
  List.iter
    (fun (what, response) ->
      let net =
        Fake_net.with_
          [(url (Gbif.plantnet_media ~key:5414995), response)]
          Fake_net.digitalis
      in
      match Step.run net plantnet_b with
      | [r] ->
          Alcotest.check status (what ^ ": failed") Status.Failed r.status;
          Alcotest.(check bool)
            (what ^ ": empty payload") true
            (Yojson.Safe.equal r.payload (`Assoc []))
      | rs -> Alcotest.failf "%s: expected 1 row, got %d" what (List.length rs))
    [
      ("Failed", Step.Failed "x");
      ("Absent (GBIF does not 404 a search)", Step.Absent);
      ("undecodable body", Step.Body (`String "x"));
    ]

let wikidata_search_failed_payload_empty () =
  let _, _, wiki_b = branches3 5414995 in
  let net =
    Fake_net.with_
      [
        ( url
            (some "search"
               (Wikidata.search ~property:Wikidata.Property.Gbif_key
                  ~value:"5414995")),
          Step.Failed "x" );
      ]
      Fake_net.digitalis
  in
  match Step.run net wiki_b with
  | [r; _] ->
      Alcotest.(check bool)
        "empty payload" true
        (Yojson.Safe.equal r.payload (`Assoc []))
  | rs -> Alcotest.failf "expected 2 rows, got %d" (List.length rs)

let wikidata_entity_failed_keeps_search () =
  let _, _, wiki_b = branches3 5414995 in
  let net =
    Fake_net.with_ [(entity_url (), Step.Failed "x")] Fake_net.digitalis
  in
  (match Step.run net wiki_b with
  | [r; _] ->
      Alcotest.(check (list string))
        "payload {search}" ["search"] (members r.payload)
  | rs -> Alcotest.failf "expected 2 rows, got %d" (List.length rs));
  Alcotest.(check int)
    "search and entity, no summary" 2
    (List.length (requests_of net wiki_b))

let wikidata_entity_missing () =
  let _, _, wiki_b = branches3 5414995 in
  let missing =
    `Assoc
      [
        ( "entities",
          `Assoc
            [
              ( "Q157555",
                `Assoc [("id", `String "Q157555"); ("missing", `String "")] );
            ] );
      ]
  in
  let net =
    Fake_net.with_ [(entity_url (), Step.Body missing)] Fake_net.digitalis
  in
  (match Step.run net wiki_b with
  | [wikidata_row; wikipedia_row] ->
      Alcotest.check status "wikidata missing" Status.Missing
        wikidata_row.status;
      Alcotest.(check (list string))
        "wikidata payload {search, entity}" ["search"; "entity"]
        (members wikidata_row.payload);
      Alcotest.check status "wikipedia missing" Status.Missing
        wikipedia_row.status;
      Alcotest.(check bool)
        "wikipedia payload empty" true
        (Yojson.Safe.equal wikipedia_row.payload (`Assoc []))
  | rs ->
      Alcotest.failf "expected [wikidata; wikipedia], got %d rows"
        (List.length rs));
  Alcotest.(check int)
    "no summary call" 2
    (List.length (requests_of net wiki_b))

let no_fr_nor_en_sitelink_is_missing_without_call () =
  let _, _, wiki_b = branches3 5414995 in
  let entity =
    Fake_net.without (sitelink "en")
      (Fake_net.without (sitelink "fr") (entity_body ()))
  in
  let net =
    Fake_net.with_ [(entity_url (), Step.Body entity)] Fake_net.digitalis
  in
  (match Step.run net wiki_b with
  | [wikidata_row; wikipedia_row] ->
      Alcotest.check status "wikidata complete" Status.Complete
        wikidata_row.status;
      Alcotest.check status "wikipedia missing" Status.Missing
        wikipedia_row.status;
      Alcotest.(check bool)
        "wikipedia payload empty" true
        (Yojson.Safe.equal wikipedia_row.payload (`Assoc []))
  | rs ->
      Alcotest.failf "expected [wikidata; wikipedia], got %d rows"
        (List.length rs));
  Alcotest.(check int)
    "no summary call" 2
    (List.length (requests_of net wiki_b))

let fr_absent_without_en_sitelink_is_missing () =
  let _, _, wiki_b = branches3 5414995 in
  let entity = Fake_net.without (sitelink "en") (entity_body ()) in
  let net =
    Fake_net.with_
      [(entity_url (), Step.Body entity); (fr_summary_url (), Step.Absent)]
      Fake_net.digitalis
  in
  (match Step.run net wiki_b with
  | [_; wikipedia_row] ->
      Alcotest.check status "missing" Status.Missing wikipedia_row.status
  | rs ->
      Alcotest.failf "expected [wikidata; wikipedia], got %d rows"
        (List.length rs));
  (* The summary outcome (Missing) is not Failed, so the uses step still
     runs over the fr sitelink (same title); no en sitelink, so no en
     extract call either. *)
  Alcotest.(check int)
    "search, entity, fr summary, fr extract: no en request" 4
    (List.length (requests_of net wiki_b))

let fr_absent_en_failed_is_failed () =
  let _, _, wiki_b = branches3 5414995 in
  let net =
    Fake_net.with_
      [(fr_summary_url (), Step.Absent); (en_summary_url (), Step.Failed "x")]
      Fake_net.digitalis
  in
  match Step.run net wiki_b with
  | [_; wikipedia_row] ->
      Alcotest.check status "failed" Status.Failed wikipedia_row.status;
      Alcotest.(check bool)
        "empty payload" true
        (Yojson.Safe.equal wikipedia_row.payload (`Assoc []))
  | rs ->
      Alcotest.failf "expected [wikidata; wikipedia], got %d rows"
        (List.length rs)

let fr_undecodable_summary_is_failed () =
  let _, _, wiki_b = branches3 5414995 in
  let net =
    Fake_net.with_
      [(fr_summary_url (), Step.Body (`String "x"))]
      Fake_net.digitalis
  in
  (match Step.run net wiki_b with
  | [_; wikipedia_row] ->
      Alcotest.check status "failed" Status.Failed wikipedia_row.status
  | rs ->
      Alcotest.failf "expected [wikidata; wikipedia], got %d rows"
        (List.length rs));
  Alcotest.(check int) "no en request" 3 (List.length (requests_of net wiki_b))

(* ---------- run ---------- *)

let status_path_tests =
  [
    case "plantnet media Failed, Absent or undecodable: Failed, empty payload"
      plantnet_media_not_decoded_is_failed;
    case "wikidata search Failed: the wikidata row's payload is empty"
      wikidata_search_failed_payload_empty;
    case "wikidata entity Failed: payload {search}, no summary call"
      wikidata_entity_failed_keeps_search;
    case
      "wikidata entity missing: wikidata Missing {search, entity}, wikipedia \
       Missing, no summary call"
      wikidata_entity_missing;
    case "no fr nor en sitelink: wikipedia Missing without a call"
      no_fr_nor_en_sitelink_is_missing_without_call;
    case "fr summary Absent and no en sitelink: wikipedia Missing, no en call"
      fr_absent_without_en_sitelink_is_missing;
    case "fr summary Absent, en Failed: wikipedia Failed"
      fr_absent_en_failed_is_failed;
    case "an undecodable fr summary: wikipedia Failed, no en attempt"
      fr_undecodable_summary_is_failed;
  ]

let full_fetch_tests =
  [
    case
      "Digitalis full fetch: all Complete, requests pinned per branch, \
       projection's empty fields as measured"
      digitalis_full_fetch;
    case
      "Arnica full fetch: wiki ends with the fr sitelink title (Arnica des \
       montagnes), not the scientific name"
      arnica_full_fetch;
    case
      "payload equality: each row's payload equals Payload.<source> of its \
       parsed fixtures"
      payload_equality;
  ]

let gbif_branch_tests =
  [
    case "gbif species Absent: Missing, empty payload, one request"
      gbif_species_absent;
    case "gbif distributions Failed: Partial, keeps the other three members"
      gbif_partial_distributions_failed;
    case
      "gbif all four Failed: Failed, empty payload; the other branches are \
       unaffected"
      gbif_failed_others_unaffected;
    case
      "an undecodable occurrence_count counts as a failed part: Partial \
       without that member"
      gbif_undecodable_occurrence_count;
  ]

let plantnet_branch_tests =
  [
    case "plantnet media with results []: Missing, payload holds media"
      plantnet_missing;
  ]

(* ---------- wiki branch: the uses step ---------- *)

let digitalis_uses_fr_then_en () =
  let _, _, wiki_b = branches3 5414995 in
  let net = Fake_net.digitalis in
  Alcotest.(check (list string))
    "search, entity, summary fr, extract fr, extract en (fr has no section)"
    [
      url
        (some "search"
           (Wikidata.search ~property:Wikidata.Property.Gbif_key
              ~value:"5414995"));
      url (Wikidata.entity (some "qid" (Qid.of_string "Q157555")));
      url
        (some "summary"
           (Wikipedia.summary ~lang:"fr" ~title:"Digitalis purpurea"));
      url
        (some "extract fr"
           (Wikipedia.extract ~lang:"fr" ~title:"Digitalis purpurea"));
      url
        (some "extract en"
           (Wikipedia.extract ~lang:"en" ~title:"Digitalis purpurea"));
    ]
    (requests_of net wiki_b);
  match Step.run net wiki_b with
  | [_; wikipedia_row] ->
      Alcotest.check status "complete" Status.Complete wikipedia_row.status;
      Alcotest.(check bool)
        "member uses is the en extract body" true
        (Yojson.Safe.equal wikipedia_row.payload
           (Payload.wikipedia
              ~summary:
                (Some
                   (fixture_body "wikipedia_summary_fr_Digitalis_purpurea.json"))
              ~uses:
                (Some
                   (fixture_body "wikipedia_extract_en_Digitalis_purpurea.json"))))
  | rs ->
      Alcotest.failf "expected [wikidata; wikipedia], got %d rows"
        (List.length rs)

let arnica_uses_fr_only () =
  let _, _, wiki_b = branches3 5405976 in
  let net = Fake_net.arnica in
  Alcotest.(check (list string))
    "search, entity, summary fr, extract fr only (fr has the section)"
    [
      url
        (some "search"
           (Wikidata.search ~property:Wikidata.Property.Gbif_key
              ~value:"5405976"));
      url (Wikidata.entity (some "qid" (Qid.of_string "Q207848")));
      url
        (some "summary"
           (Wikipedia.summary ~lang:"fr" ~title:"Arnica des montagnes"));
      url
        (some "extract fr"
           (Wikipedia.extract ~lang:"fr" ~title:"Arnica des montagnes"));
    ]
    (requests_of net wiki_b);
  match Step.run net wiki_b with
  | [_; wikipedia_row] ->
      Alcotest.check status "complete" Status.Complete wikipedia_row.status
  | rs ->
      Alcotest.failf "expected [wikidata; wikipedia], got %d rows"
        (List.length rs)

let extract_fr_failed_is_partial_no_en_call () =
  let _, _, wiki_b = branches3 5414995 in
  let net =
    Fake_net.with_
      [
        ( url
            (some "extract fr"
               (Wikipedia.extract ~lang:"fr" ~title:"Digitalis purpurea")),
          Step.Failed "x" );
      ]
      Fake_net.digitalis
  in
  (match Step.run net wiki_b with
  | [_; wikipedia_row] ->
      Alcotest.check status "partial" Status.Partial wikipedia_row.status;
      Alcotest.(check bool)
        "member summary kept, no uses member" true
        (Yojson.Safe.equal wikipedia_row.payload
           (Payload.wikipedia
              ~summary:
                (Some
                   (fixture_body "wikipedia_summary_fr_Digitalis_purpurea.json"))
              ~uses:None))
  | rs ->
      Alcotest.failf "expected [wikidata; wikipedia], got %d rows"
        (List.length rs));
  Alcotest.(check bool)
    "no extract en request" false
    (List.exists
       (fun u ->
         Herbier_test_support.Text.contains ~sub:"lang=en" u
         || Herbier_test_support.Text.contains ~sub:"en.wikipedia" u)
       (requests_of net wiki_b))

let extract_url lang =
  url
    (some ("extract " ^ lang)
       (Wikipedia.extract ~lang ~title:"Digitalis purpurea"))

let summary_fr = "wikipedia_summary_fr_Digitalis_purpurea.json"

let wikipedia_row_of net wiki_b =
  match Step.run net wiki_b with
  | [_; wikipedia_row] -> wikipedia_row
  | rs ->
      Alcotest.failf "expected [wikidata; wikipedia], got %d rows"
        (List.length rs)

let extract_en_failed_after_fr_without_section () =
  let _, _, wiki_b = branches3 5414995 in
  let net =
    Fake_net.with_ [(extract_url "en", Step.Failed "x")] Fake_net.digitalis
  in
  let row = wikipedia_row_of net wiki_b in
  Alcotest.check status "partial" Status.Partial row.status;
  Alcotest.(check bool)
    "summary kept, the fr candidate dropped" true
    (Yojson.Safe.equal row.payload
       (Payload.wikipedia ~summary:(Some (fixture_body summary_fr)) ~uses:None))

let extract_fr_undecodable_is_partial_no_en_call () =
  let _, _, wiki_b = branches3 5414995 in
  let net =
    Fake_net.with_
      [(extract_url "fr", Step.Body (`Assoc []))]
      Fake_net.digitalis
  in
  let row = wikipedia_row_of net wiki_b in
  Alcotest.check status "partial" Status.Partial row.status;
  Alcotest.(check bool)
    "no extract en request" false
    (List.mem (extract_url "en") (requests_of net wiki_b))

let neither_extract_has_a_section () =
  let _, _, wiki_b = branches3 5414995 in
  let urtica_en = fixture_body "wikipedia_extract_en_Urtica_dioica.json" in
  let net =
    Fake_net.with_ [(extract_url "en", Step.Body urtica_en)] Fake_net.digitalis
  in
  let row = wikipedia_row_of net wiki_b in
  Alcotest.check status "complete" Status.Complete row.status;
  Alcotest.(check bool)
    "uses is the last body read, the en one" true
    (Yojson.Safe.equal row.payload
       (Payload.wikipedia
          ~summary:(Some (fixture_body summary_fr))
          ~uses:(Some urtica_en)))

let wiki_branch_tests =
  [
    case "fr extract without a section, en extract Failed: Partial, no uses"
      extract_en_failed_after_fr_without_section;
    case "fr extract undecodable: Partial, no en call"
      extract_fr_undecodable_is_partial_no_en_call;
    case "fr and en extracts both without a section: Complete, the en body"
      neither_extract_has_a_section;
    case "wikidata search Failed: [wikidata Failed] only, no wikipedia row"
      wikidata_search_failed;
    case
      "wikidata search finds nothing: wikidata Missing, wikipedia Missing, no \
       entity call"
      wikidata_no_item;
    case "wikidata entity Failed: wikidata Partial, no wikipedia row"
      wikidata_entity_failed;
    case
      "fr summary Absent falls back to en: wikipedia Complete with the en body"
      fr_absent_falls_back_to_en;
    case "fr and en summary both Absent: wikipedia Missing"
      fr_and_en_absent_is_missing;
    case "fr summary Failed: wikipedia Failed, no en attempt"
      fr_failed_no_en_attempt;
    case
      "Digitalis: uses step tries fr then en (fr has no section), member uses \
       is the en extract"
      digitalis_uses_fr_then_en;
    case "Arnica: uses step tries fr only (fr has the section), no en call"
      arnica_uses_fr_only;
    case
      "extract fr Failed after summary Complete: wikipedia Partial {summary}, \
       no en attempt"
      extract_fr_failed_is_partial_no_en_call;
  ]

let decide_tests =
  [
    case
      "Done criterion: a Failed source with a live previous row is dropped, \
       the others kept"
      decide_drops_failed_with_live_previous;
    case "Failed with only a soft-deleted previous row is kept as is"
      decide_failed_soft_deleted_previous_kept;
    case "Failed with no previous row is kept as is"
      decide_failed_no_previous_kept;
    case
      "Failed over a live Failed row replaces it, its stored members kept (the \
       failure is dated anew)"
      decide_failed_over_failed_replaces_it;
    case
      "Partial with a live previous row merges the previous row's missing \
       members, in Payload.all order"
      decide_partial_merges_previous_distributions;
    case "Partial with no previous row is unchanged"
      decide_partial_no_previous_unchanged;
    case "Partial with only a soft-deleted previous row is unchanged"
      decide_partial_soft_deleted_previous_unchanged;
    case "Complete or Missing rows are unchanged, previous ignored"
      decide_complete_and_missing_ignore_previous;
    case "decide keeps the input order of the rows given"
      decide_input_order_kept;
  ]

let sources_test =
  case
    "Fanout.sources is the seven sources, Gbif/Plantnet/Wikidata/Wikipedia \
     then Taxref/Tela/Plantuse (Plantuse last)" (fun () ->
      Alcotest.(check (list string))
        "sources"
        [
          "gbif";
          "plantnet";
          "wikidata";
          "wikipedia";
          "taxref";
          "tela";
          "plantuse";
        ]
        (List.map Source.to_string Fanout.sources))

let due_tests =
  [
    case "no rows: due" due_no_rows;
    case "the four sources without the regional layer: due (no Taxref/Tela row)"
      due_four_sources_alone;
    case "a Missing tela row 10 days old is not due on its own"
      due_missing_tela_not_due;
    case "a source has no live row: due" due_missing_a_source;
    case "max_age: fresh false, 91 days true, exactly 90 days false" due_max_age;
    case "Failed/Partial rows retry after 1 day (strictly), not after 1 hour"
      due_failed_or_partial_retry;
    case "after a fetch whose Wikidata search failed: not due 1 hour later"
      due_after_wikidata_search_failed;
    case "a Missing row 10 days old is not due on its own"
      due_missing_row_not_due;
    case "a soft-deleted row counts as no live row: due"
      due_soft_deleted_ignored;
    case "a row dated after now does not make the plant due"
      due_future_fetched_at_ignored;
    case "a row of a source outside Fanout.sources is ignored"
      due_other_source_ignored;
    case "backfill: every source fresh except no plantuse row at all: due"
      due_backfill_no_plantuse_row;
  ]

let suite =
  ( "fanout",
    [sources_test]
    @ full_fetch_tests
    @ gbif_branch_tests
    @ plantnet_branch_tests
    @ wiki_branch_tests
    @ decide_tests
    @ due_tests
    @ status_path_tests )
