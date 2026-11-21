(* Herbier_refs.Regional: input (from this fetch's gbif/wikidata rows and the
   stored rows) and program (the Tela + INPN calls), over Fake_net replaying
   the recorded fixtures of Digitalis purpurea and Arnica montana plus the bridge
   (Reynoutria/Fallopia) and no-TaxRef-id (Victoria amazonica) cases. *)

module Value = Herbier_test_support.Value
module Regional = Herbier_refs.Regional
module Fanout = Herbier_refs.Fanout
module Step = Herbier_refs.Step
module Request = Herbier_refs.Request
module Decode = Herbier_refs.Decode
module Payload = Herbier_refs.Payload
module Projection = Herbier_refs.Projection
module Tela = Herbier_refs.Sources.Tela
module Inpn = Herbier_refs.Sources.Inpn
module Ids = Herbier_domain.Ids
module Reference = Herbier_domain.Reference
module Source = Herbier_domain.Reference.Source
module Status = Herbier_domain.Reference.Status
module Fixture = Herbier_test_support.Fixture

let url (r : Request.t) = r.url

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

(* ---------- testables ---------- *)

let status =
  Alcotest.testable
    (fun f s -> Format.pp_print_string f (Status.to_string s))
    (fun a b -> String.equal (Status.to_string a) (Status.to_string b))

let input_t = Alcotest.testable Regional.pp_input Regional.equal_input
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
        (String.concat ", "
           (List.map (fun (r : Fanout.row) -> Source.to_string r.source) rs))

let requests_of net prog =
  List.map (fun (r : Request.t) -> r.url) (Step.requests net prog)

let fail_any (r : Request.t) = Alcotest.failf "unexpected request %s" (url r)

(* ---------- the two recorded species' input, via the existing branches ---------- *)

let branches3 gbif_key =
  match Fanout.branches ~gbif_key with
  | [g; p; w] -> (g, p, w)
  | bs -> Alcotest.failf "expected 3 branches, got %d" (List.length bs)

let input_of_full_fetch ~gbif_key ~net =
  let gbif_b, _, wiki_b = branches3 gbif_key in
  Regional.input ~previous:[] (Step.run net gbif_b @ Step.run net wiki_b)

(* ---------- regional_fetch tables for the two recorded species ---------- *)

let digitalis_regional_table = Fake_net.digitalis_regional

let arnica_regional_table =
  Fake_net.regional_fetch ~name:"Arnica montana" ~taxon_nn:6646
    ~baseflor_nn:6646 ~names:"tela_names_arnica_montana.json"
    ~taxon:"tela_taxon_6646.json" ~baseflor:"tela_baseflor_6646.json"
    ~cd_nom:83874 ~cd_ref:83874 ~inpn_name:"inpn_name_83874.json"
    ~status:"inpn_status_83874.json" ~red_list:"inpn_red_list_83874.json"
    ~protections:"inpn_protections_83874.json"

(* The regional overrides alone, with any other URL failing the test: for
   tests that call [Regional.program] directly on a hand-built [input]. *)
let net_of ?(overrides = []) table () =
  Fake_net.with_ overrides (Fake_net.with_ table fail_any)

let digitalis_net = net_of digitalis_regional_table
let arnica_net = net_of arnica_regional_table

(* The regional overrides layered over a full species fetch (gbif + wiki
   fixtures too): for the two "full fetch" tests, which run
   [Fanout.branches] and [Regional.program] against the very same net. *)
let full_net_of table base () = Fake_net.with_ table base
let digitalis_full_net = full_net_of digitalis_regional_table Fake_net.digitalis
let arnica_full_net = full_net_of arnica_regional_table Fake_net.arnica

(* ---------- Digitalis: full regional fetch ---------- *)

let digitalis_full () =
  let net = digitalis_full_net () in
  let input = input_of_full_fetch ~gbif_key:5414995 ~net in
  Alcotest.check input_t "input"
    {
      Regional.name = Some "Digitalis purpurea";
      taxref = Some 94959;
      settled = true;
    }
    input;
  let prog = Regional.program input in
  Alcotest.(check (list string))
    "requests, strictly in order"
    [
      url (Fake_net.some "Tela.names" (Tela.names ~name:"Digitalis purpurea"));
      url (Tela.taxon ~nn:22437);
      url (Tela.baseflor ~nn:22437);
      url (Inpn.name ~cd_nom:94959);
      url (Inpn.status ~cd_ref:94959);
      url (Inpn.red_list ~cd_ref:94959);
      url (Inpn.protections ~cd_ref:94959);
    ]
    (requests_of net prog);
  let rows = Step.run net prog in
  let taxref_row = find_row rows Source.Taxref in
  let tela_row = find_row rows Source.Tela in
  Alcotest.check status "taxref complete" Status.Complete taxref_row.status;
  Alcotest.(check (list string))
    "taxref members"
    ["name"; "status"; "red_list"; "protections"]
    (members taxref_row.payload);
  Alcotest.check status "tela complete" Status.Complete tela_row.status;
  Alcotest.(check (list string))
    "tela members"
    ["names"; "taxon"; "baseflor"]
    (members tela_row.payload)

(* ---------- Arnica: same, never Wikidata P3105's nn 6648 ---------- *)

let arnica_full () =
  let net = arnica_full_net () in
  let input = input_of_full_fetch ~gbif_key:5405976 ~net in
  Alcotest.check input_t "input"
    {Regional.name = Some "Arnica montana"; taxref = Some 83874; settled = true}
    input;
  let prog = Regional.program input in
  let rows = Step.run net prog in
  let taxref_row = find_row rows Source.Taxref in
  let tela_row = find_row rows Source.Tela in
  Alcotest.check status "taxref complete" Status.Complete taxref_row.status;
  Alcotest.check status "tela complete" Status.Complete tela_row.status;
  (* No request to Tela nn 6648 (Wikidata P3105's wrong value) was made: the
     net would have failed the test with "unexpected request" otherwise,
     since only nn 6646 is in [arnica_regional_table]. *)
  Alcotest.(check (list string))
    "no request to nn 6648" []
    (List.filter
       (fun u -> Herbier_test_support.Text.contains ~sub:"taxons/6648" u)
       (requests_of net prog))

(* ---------- bridge (no P3186): Reynoutria japonica / Fallopia japonica ---------- *)

let reynoutria_table =
  Fake_net.regional_fetch ~name:"Reynoutria japonica" ~taxon_nn:55763
    ~baseflor_nn:26478 ~names:"tela_names_reynoutria_japonica.json"
    ~taxon:"tela_taxon_55763.json" ~baseflor:"tela_baseflor_26478.json"
    ~cd_nom:97964 ~cd_ref:117503 ~inpn_name:"inpn_name_97964.json"
    ~status:"inpn_status_117503.json" ~red_list:"inpn_red_list_117503.json"
    ~protections:"inpn_protections_117503.json"

let bridge_no_p3186 () =
  let net = Fake_net.with_ reynoutria_table fail_any in
  let input : Regional.input =
    {Regional.name = Some "Reynoutria japonica"; taxref = None; settled = true}
  in
  let prog = Regional.program input in
  Alcotest.(check (list string))
    "requests: the bridge (nn 55763), its accepted baseflor (nn 26478), then \
     INPN on the valid id (117503)"
    [
      url (Fake_net.some "Tela.names" (Tela.names ~name:"Reynoutria japonica"));
      url (Tela.taxon ~nn:55763);
      url (Tela.baseflor ~nn:26478);
      url (Inpn.name ~cd_nom:97964);
      url (Inpn.status ~cd_ref:117503);
      url (Inpn.red_list ~cd_ref:117503);
      url (Inpn.protections ~cd_ref:117503);
    ]
    (requests_of net prog);
  let rows = Step.run net prog in
  let taxref_row = find_row rows Source.Taxref in
  Alcotest.check status "taxref complete" Status.Complete taxref_row.status;
  match Payload.get Payload.Inpn_status taxref_row.payload with
  | Some body -> (
      match Inpn.status_of_json body with
      | Ok [{status = "INVASIVE"; _}] -> ()
      | Ok l ->
          Alcotest.failf "expected [INVASIVE], got %d entries" (List.length l)
      | Error e -> Alcotest.failf "decode failed: %s" (Decode.error_to_string e)
      )
  | None -> Alcotest.fail "no status member"

(* ---------- no TaxRef id at all (Victoria amazonica) ---------- *)

let victoria_table =
  [
    ( url (Fake_net.some "Tela.names" (Tela.names ~name:"Victoria amazonica")),
      Step.Absent );
  ]

let no_taxref_id () =
  let net = Fake_net.with_ victoria_table fail_any in
  let input : Regional.input =
    {Regional.name = Some "Victoria amazonica"; taxref = None; settled = true}
  in
  let prog = Regional.program input in
  Alcotest.(check (list string))
    "the names call alone"
    [url (Fake_net.some "Tela.names" (Tela.names ~name:"Victoria amazonica"))]
    (requests_of net prog);
  let rows = Step.run net prog in
  let taxref_row = find_row rows Source.Taxref in
  let tela_row = find_row rows Source.Tela in
  Alcotest.check status "taxref missing" Status.Missing taxref_row.status;
  Alcotest.(check bool)
    "taxref empty payload" true
    (Yojson.Safe.equal taxref_row.payload (`Assoc []));
  Alcotest.check status "tela missing" Status.Missing tela_row.status;
  Alcotest.(check bool)
    "tela empty payload" true
    (Yojson.Safe.equal tela_row.payload (`Assoc []));
  (* Projected alongside the Digitalis gbif/wikidata rows: the six regional
     fields are all None, as if the regional layer had never run. *)
  let net = digitalis_full_net () in
  let gbif_b, plantnet_b, wiki_b = branches3 5414995 in
  let global_rows =
    Fanout.decide ~previous:[]
      (Step.run net gbif_b @ Step.run net plantnet_b @ Step.run net wiki_b)
  in
  let as_references (rs : Fanout.row list) =
    List.map
      (fun (r : Fanout.row) ->
        reference_row ~source:r.source ~status:r.status
          ~fetched_at:(time "2026-11-01T10:00:00Z")
          r.payload)
      rs
  in
  let proj =
    Projection.project
      ~references:(as_references global_rows @ as_references rows)
      ~plant_refs:[]
  in
  let value (c : _ Projection.cited) = c.value in
  let protection_t =
    Alcotest.testable Projection.pp_protection Projection.equal_protection
  in
  let fr_red_list_t =
    Alcotest.testable Projection.pp_fr_red_list Projection.equal_fr_red_list
  in
  Alcotest.(check (option string))
    "fr_status" None
    (Option.map value proj.fr_status);
  Alcotest.(check (option protection_t))
    "fr_protection" None
    (Option.map value proj.fr_protection);
  Alcotest.(check (option fr_red_list_t))
    "fr_red_list" None
    (Option.map value proj.fr_red_list);
  Alcotest.(check (option string))
    "life_form" None
    (Option.map value proj.life_form);
  Alcotest.(check (option (list int)))
    "flowering_months" None
    (Option.map value proj.flowering_months);
  Alcotest.(check (option (pair (option string) (list string))))
    "habitat" None
    (Option.map
       (fun (c : Projection.habitat Projection.cited) ->
         (c.value.phrase, c.value.chips))
       proj.habitat)

(* ---------- name = None ---------- *)

let inpn_94959_table =
  [
    (url (Inpn.name ~cd_nom:94959), "inpn_name_94959.json");
    (url (Inpn.status ~cd_ref:94959), "inpn_status_94959.json");
    (url (Inpn.red_list ~cd_ref:94959), "inpn_red_list_94959.json");
    (url (Inpn.protections ~cd_ref:94959), "inpn_protections_94959.json");
  ]
  |> List.map (fun (u, f) -> (u, Fake_net.body_of_fixture f))

let name_none_with_taxref ~settled () =
  let net = Fake_net.with_ inpn_94959_table fail_any in
  let input : Regional.input =
    {Regional.name = None; taxref = Some 94959; settled}
  in
  let prog = Regional.program input in
  Alcotest.(check (list string))
    "no Tela request, the four INPN calls"
    [
      url (Inpn.name ~cd_nom:94959);
      url (Inpn.status ~cd_ref:94959);
      url (Inpn.red_list ~cd_ref:94959);
      url (Inpn.protections ~cd_ref:94959);
    ]
    (requests_of net prog);
  let rows = Step.run net prog in
  let tela_row = find_row rows Source.Tela in
  let taxref_row = find_row rows Source.Taxref in
  Alcotest.check status "taxref complete (INPN still runs)" Status.Complete
    taxref_row.status;
  match settled with
  | true -> Alcotest.check status "tela missing" Status.Missing tela_row.status
  | false -> Alcotest.check status "tela failed" Status.Failed tela_row.status

(* ---------- name = None, taxref = None ---------- *)

let name_and_taxref_none ~settled () =
  let net = Fake_net.with_ [] fail_any in
  let input : Regional.input = {Regional.name = None; taxref = None; settled} in
  let prog = Regional.program input in
  Alcotest.(check (list string)) "no request" [] (requests_of net prog);
  let rows = Step.run net prog in
  let tela_row = find_row rows Source.Tela in
  let taxref_row = find_row rows Source.Taxref in
  match settled with
  | false ->
      Alcotest.check status "tela failed" Status.Failed tela_row.status;
      Alcotest.check status "taxref failed" Status.Failed taxref_row.status
  | true ->
      Alcotest.check status "tela missing" Status.Missing tela_row.status;
      Alcotest.check status "taxref missing" Status.Missing taxref_row.status

(* ---------- failures ---------- *)

let names_failed_override =
  ( url (Fake_net.some "Tela.names" (Tela.names ~name:"Digitalis purpurea")),
    Step.Failed "x" )

let names_failed_no_p3186_no_inpn_call () =
  let net =
    net_of digitalis_regional_table ~overrides:[names_failed_override] ()
  in
  let input : Regional.input =
    {Regional.name = Some "Digitalis purpurea"; taxref = None; settled = true}
  in
  let prog = Regional.program input in
  Alcotest.(check (list string))
    "the names call alone, no INPN call"
    [url (Fake_net.some "Tela.names" (Tela.names ~name:"Digitalis purpurea"))]
    (requests_of net prog);
  let rows = Step.run net prog in
  Alcotest.check status "tela failed" Status.Failed
    (find_row rows Source.Tela).status;
  Alcotest.check status "taxref failed (bridge failed, no P3186)" Status.Failed
    (find_row rows Source.Taxref).status

let names_failed_with_p3186_inpn_still_runs () =
  let net =
    net_of digitalis_regional_table ~overrides:[names_failed_override] ()
  in
  let input : Regional.input =
    {
      Regional.name = Some "Digitalis purpurea";
      taxref = Some 94959;
      settled = true;
    }
  in
  let prog = Regional.program input in
  let rows = Step.run net prog in
  Alcotest.check status "tela failed" Status.Failed
    (find_row rows Source.Tela).status;
  Alcotest.check status "taxref complete (INPN still runs on input.taxref)"
    Status.Complete (find_row rows Source.Taxref).status

let digitalis_input : Regional.input =
  {
    Regional.name = Some "Digitalis purpurea";
    taxref = Some 94959;
    settled = true;
  }

let baseflor_absent_tela_complete_without_member () =
  let net =
    net_of digitalis_regional_table
      ~overrides:[(url (Tela.baseflor ~nn:22437), Step.Absent)]
      ()
  in
  let rows = Step.run net (Regional.program digitalis_input) in
  let tela_row = find_row rows Source.Tela in
  Alcotest.check status "complete (Tela answered: no Baseflor row)"
    Status.Complete tela_row.status;
  Alcotest.(check (list string))
    "no baseflor member" ["names"; "taxon"] (members tela_row.payload)

let baseflor_failed_tela_partial () =
  let net =
    net_of digitalis_regional_table
      ~overrides:[(url (Tela.baseflor ~nn:22437), Step.Failed "x")]
      ()
  in
  let rows = Step.run net (Regional.program digitalis_input) in
  let tela_row = find_row rows Source.Tela in
  Alcotest.check status "partial" Status.Partial tela_row.status;
  Alcotest.(check (list string))
    "names, taxon" ["names"; "taxon"] (members tela_row.payload)

let inpn_name_absent_taxref_missing_no_further_call () =
  let net =
    net_of digitalis_regional_table
      ~overrides:[(url (Inpn.name ~cd_nom:94959), Step.Absent)]
      ()
  in
  let prog = Regional.program digitalis_input in
  Alcotest.(check (list string))
    "Tela's three calls then just inpn name, no status/red_list/protections"
    [
      url (Fake_net.some "Tela.names" (Tela.names ~name:"Digitalis purpurea"));
      url (Tela.taxon ~nn:22437);
      url (Tela.baseflor ~nn:22437);
      url (Inpn.name ~cd_nom:94959);
    ]
    (requests_of net prog);
  let rows = Step.run net prog in
  let taxref_row = find_row rows Source.Taxref in
  Alcotest.check status "missing" Status.Missing taxref_row.status;
  Alcotest.(check bool)
    "empty payload" true
    (Yojson.Safe.equal taxref_row.payload (`Assoc []));
  Alcotest.check status "tela unaffected, complete" Status.Complete
    (find_row rows Source.Tela).status

let inpn_red_list_failed_taxref_partial () =
  let net =
    net_of digitalis_regional_table
      ~overrides:[(url (Inpn.red_list ~cd_ref:94959), Step.Failed "x")]
      ()
  in
  let rows = Step.run net (Regional.program digitalis_input) in
  let taxref_row = find_row rows Source.Taxref in
  Alcotest.check status "partial" Status.Partial taxref_row.status;
  Alcotest.(check (list string))
    "name, status, protections (no red_list)"
    ["name"; "status"; "protections"]
    (members taxref_row.payload)

(* ---------- input rules ---------- *)

let digitalis_species_fixture = Check.json "gbif_species_5414995.json"

let gbif_payload_of species =
  Payload.gbif ~species:(Some species) ~vernacular_names:None
    ~distributions:None ~occurrence_count:None

(* ---------- the bridge's taxon call ---------- *)

let digitalis_names_url =
  url (Fake_net.some "Tela.names" (Tela.names ~name:"Digitalis purpurea"))

let digitalis_no_p3186 : Regional.input =
  {Regional.name = Some "Digitalis purpurea"; taxref = None; settled = true}

let bridge_taxon ~taxon ~requests ~tela ~tela_members ~taxref () =
  let net =
    net_of digitalis_regional_table
      ~overrides:[(url (Tela.taxon ~nn:22437), taxon)]
      ()
  in
  let prog = Regional.program digitalis_no_p3186 in
  Alcotest.(check (list string)) "requests" requests (requests_of net prog);
  let rows = Step.run net prog in
  let tela_row = find_row rows Source.Tela in
  let taxref_row = find_row rows Source.Taxref in
  Alcotest.check status "tela" tela tela_row.status;
  Alcotest.(check (list string))
    "tela members" tela_members (members tela_row.payload);
  Alcotest.check status "taxref" taxref taxref_row.status;
  Alcotest.(check (list string))
    "taxref members" []
    (members taxref_row.payload)

let names_then_taxon = [digitalis_names_url; url (Tela.taxon ~nn:22437)]

let taxon_failed =
  bridge_taxon ~taxon:(Step.Failed "x") ~requests:names_then_taxon
    ~tela:Status.Partial ~tela_members:["names"] ~taxref:Status.Failed

let taxon_undecodable =
  bridge_taxon
    ~taxon:(Step.Body (`Assoc []))
    ~requests:names_then_taxon ~tela:Status.Partial ~tela_members:["names"]
    ~taxref:Status.Failed

let taxon_absent =
  bridge_taxon ~taxon:Step.Absent ~requests:names_then_taxon
    ~tela:Status.Missing ~tela_members:["names"] ~taxref:Status.Missing

let taxon_without_cd_nom =
  bridge_taxon
    ~taxon:
      (Step.Body
         (Fake_net.without ["cd_nom"]
            (Fake_net.json_of_fixture "tela_taxon_22437.json")))
    ~requests:names_then_taxon ~tela:Status.Missing
    ~tela_members:["names"; "taxon"] ~taxref:Status.Missing

(* Arnica's names page holds no "Digitalis purpurea": [pick] finds nothing. *)
let pick_none_unmatched () =
  let net =
    net_of digitalis_regional_table
      ~overrides:
        [
          ( digitalis_names_url,
            Fake_net.body_of_fixture "tela_names_arnica_montana.json" );
        ]
      ()
  in
  let prog = Regional.program digitalis_no_p3186 in
  Alcotest.(check (list string))
    "the names call alone" [digitalis_names_url] (requests_of net prog);
  let rows = Step.run net prog in
  let tela_row = find_row rows Source.Tela in
  Alcotest.check status "tela missing" Status.Missing tela_row.status;
  Alcotest.(check (list string))
    "tela members" ["names"] (members tela_row.payload);
  Alcotest.check status "taxref missing" Status.Missing
    (find_row rows Source.Taxref).status

(* Wikidata failed with nothing stored: the TaxRef id may still come from it,
   so "no id" is a Failed row (retried after a day) whatever Tela said. *)
let unsettled_names_absent_taxref_failed () =
  let net =
    net_of digitalis_regional_table
      ~overrides:[(digitalis_names_url, Step.Absent)]
      ()
  in
  let input = {digitalis_no_p3186 with settled = false} in
  let rows = Step.run net (Regional.program input) in
  Alcotest.check status "tela missing (Tela answered)" Status.Missing
    (find_row rows Source.Tela).status;
  Alcotest.check status "taxref failed" Status.Failed
    (find_row rows Source.Taxref).status

(* ---------- INPN's name call and sub-calls ---------- *)

let inpn_name_not_decoded response () =
  let net =
    net_of digitalis_regional_table
      ~overrides:[(url (Inpn.name ~cd_nom:94959), response)]
      ()
  in
  let prog = Regional.program digitalis_input in
  Alcotest.(check (list string))
    "Tela's three calls then the name call alone"
    [
      digitalis_names_url;
      url (Tela.taxon ~nn:22437);
      url (Tela.baseflor ~nn:22437);
      url (Inpn.name ~cd_nom:94959);
    ]
    (requests_of net prog);
  let taxref_row = find_row (Step.run net prog) Source.Taxref in
  Alcotest.check status "taxref failed" Status.Failed taxref_row.status;
  Alcotest.(check (list string)) "no member" [] (members taxref_row.payload)

let inpn_protections_absent_partial () =
  let net =
    net_of digitalis_regional_table
      ~overrides:[(url (Inpn.protections ~cd_ref:94959), Step.Absent)]
      ()
  in
  let taxref_row =
    find_row (Step.run net (Regional.program digitalis_input)) Source.Taxref
  in
  Alcotest.check status "partial" Status.Partial taxref_row.status;
  Alcotest.(check (list string))
    "name, status, red_list"
    ["name"; "status"; "red_list"]
    (members taxref_row.payload)

(* ---------- P3186 over the bridge's cd_nom ---------- *)

(* Reynoutria's bridge finds cd_nom 97964; a P3186 of 94959 must win. *)
let p3186_wins_over_bridge_cd_nom () =
  let net = Fake_net.with_ (inpn_94959_table @ reynoutria_table) fail_any in
  let input : Regional.input =
    {
      Regional.name = Some "Reynoutria japonica";
      taxref = Some 94959;
      settled = true;
    }
  in
  let requests = requests_of net (Regional.program input) in
  Alcotest.(check bool)
    "INPN asked for 94959" true
    (List.mem (url (Inpn.name ~cd_nom:94959)) requests);
  Alcotest.(check bool)
    "never for the bridge's 97964" false
    (List.mem (url (Inpn.name ~cd_nom:97964)) requests)

(* ---------- a subspecies: GBIF's canonical name drops « subsp. » ---------- *)

let subspecies_bridges () =
  let gbif_row : Fanout.row =
    {
      Fanout.source = Source.Gbif;
      status = Status.Complete;
      payload = gbif_payload_of (Check.json "gbif_species_5708907.json");
    }
  in
  let input = Regional.input ~previous:[] [gbif_row] in
  let name = "Digitalis purpurea subsp. purpurea" in
  Alcotest.(check (option string))
    "name, rank marker kept" (Some name) input.name;
  let names_url = url (Fake_net.some "Tela.names" (Tela.names ~name)) in
  let net =
    Fake_net.with_
      [
        ( names_url,
          Fake_net.body_of_fixture
            "tela_names_digitalis_purpurea_subsp_purpurea.json" );
        ( url (Tela.taxon ~nn:76533),
          Fake_net.body_of_fixture "tela_taxon_76533.json" );
        (url (Tela.baseflor ~nn:76533), Step.Absent);
        (url (Inpn.name ~cd_nom:160468), Step.Absent);
      ]
      fail_any
  in
  let prog = Regional.program {input with settled = true} in
  Alcotest.(check (list string))
    "bridged to nn 76533, INPN on its cd_nom"
    [
      names_url;
      url (Tela.taxon ~nn:76533);
      url (Tela.baseflor ~nn:76533);
      url (Inpn.name ~cd_nom:160468);
    ]
    (requests_of net prog);
  Alcotest.check status "tela complete" Status.Complete
    (find_row (Step.run net prog) Source.Tela).status

let input_name_from_stored_gbif_when_this_fetch_failed () =
  let failed_gbif_row : Fanout.row =
    {Fanout.source = Source.Gbif; status = Status.Failed; payload = `Assoc []}
  in
  let previous =
    [
      reference_row ~source:Source.Gbif
        ~fetched_at:(time "2026-10-01T00:00:00Z")
        (gbif_payload_of digitalis_species_fixture);
    ]
  in
  let input = Regional.input ~previous [failed_gbif_row] in
  Alcotest.(check (option string))
    "name from the stored payload" (Some "Digitalis purpurea") input.name

let input_wikidata_failed_no_stored_is_unsettled () =
  let missing_gbif_row : Fanout.row =
    {Fanout.source = Source.Gbif; status = Status.Missing; payload = `Assoc []}
  in
  let failed_wikidata_row : Fanout.row =
    {
      Fanout.source = Source.Wikidata;
      status = Status.Failed;
      payload = `Assoc [];
    }
  in
  let input =
    Regional.input ~previous:[] [missing_gbif_row; failed_wikidata_row]
  in
  Alcotest.(check (option int)) "taxref" None input.taxref;
  Alcotest.(check bool)
    "not settled: the wikidata side never got an answer" false input.settled

let input_both_missing_is_settled () =
  let missing_gbif_row : Fanout.row =
    {Fanout.source = Source.Gbif; status = Status.Missing; payload = `Assoc []}
  in
  let missing_wikidata_row : Fanout.row =
    {
      Fanout.source = Source.Wikidata;
      status = Status.Missing;
      payload = `Assoc [];
    }
  in
  let input =
    Regional.input ~previous:[] [missing_gbif_row; missing_wikidata_row]
  in
  Alcotest.(check (option string)) "name" None input.name;
  Alcotest.(check bool) "settled" true input.settled

let missing_entity_json =
  `Assoc
    [
      ( "entities",
        `Assoc
          [
            ( "Q157555",
              `Assoc [("id", `String "Q157555"); ("missing", `String "")] );
          ] );
    ]

let input_entity_decoded_to_none_is_no_taxref () =
  let wikidata_row : Fanout.row =
    {
      Fanout.source = Source.Wikidata;
      status = Status.Complete;
      payload = Payload.wikidata ~search:None ~entity:(Some missing_entity_json);
    }
  in
  let input = Regional.input ~previous:[] [wikidata_row] in
  Alcotest.(check (option int)) "taxref" None input.taxref

let wikidata_entity_payload =
  Payload.wikidata ~search:None
    ~entity:(Some (Check.json "wikidata_entity_Q157555.json"))

let input_taxref_from_stored_entity_when_this_fetch_failed () =
  let failed_wikidata_row : Fanout.row =
    {
      Fanout.source = Source.Wikidata;
      status = Status.Failed;
      payload = `Assoc [];
    }
  in
  let previous =
    [
      reference_row ~source:Source.Wikidata
        ~fetched_at:(time "2026-10-01T00:00:00Z")
        wikidata_entity_payload;
    ]
  in
  let input = Regional.input ~previous [failed_wikidata_row] in
  Alcotest.(check (option int)) "taxref" (Some 94959) input.taxref

let input_settled_by_stored_missing_wikidata () =
  let missing_gbif_row : Fanout.row =
    {Fanout.source = Source.Gbif; status = Status.Missing; payload = `Assoc []}
  in
  let previous =
    [
      reference_row ~status:Status.Missing ~source:Source.Wikidata
        ~fetched_at:(time "2026-10-01T00:00:00Z")
        (`Assoc []);
    ]
  in
  let input = Regional.input ~previous [missing_gbif_row] in
  Alcotest.(check bool) "settled" true input.settled

(* ---------- Fanout.decide applies to the new sources too ---------- *)

let decide_drops_failed_tela_row_with_live_previous () =
  let failed_row : Fanout.row =
    {Fanout.source = Source.Tela; status = Status.Failed; payload = `Assoc []}
  in
  let previous =
    [
      reference_row ~source:Source.Tela
        ~fetched_at:(time "2026-10-01T00:00:00Z")
        (`Assoc [("names", `Assoc [])]);
    ]
  in
  Alcotest.(check int)
    "dropped (not included in what decide upserts)" 0
    (List.length (Fanout.decide ~previous [failed_row]))

let decide_partial_taxref_merges_previous_red_list () =
  let previous_payload =
    Payload.taxref
      ~name:(Some (`Assoc [("k", `Int 1)]))
      ~status:(Some (`Assoc []))
      ~red_list:(Some (`Assoc [("category", `String "LC")]))
      ~protections:(Some (`Assoc []))
  in
  let previous =
    [
      reference_row ~source:Source.Taxref
        ~fetched_at:(time "2026-10-01T00:00:00Z")
        previous_payload;
    ]
  in
  let partial_payload =
    Payload.taxref
      ~name:(Some (`Assoc [("k", `Int 2)]))
      ~status:(Some (`Assoc [("x", `Int 1)]))
      ~red_list:None
      ~protections:(Some (`Assoc [("y", `Int 1)]))
  in
  let partial_row : Fanout.row =
    {
      Fanout.source = Source.Taxref;
      status = Status.Partial;
      payload = partial_payload;
    }
  in
  match Fanout.decide ~previous [partial_row] with
  | [r] ->
      Alcotest.check status "still partial" Status.Partial r.status;
      Alcotest.(check (list string))
        "new members plus the previous row's red_list, Payload.all order"
        ["name"; "status"; "red_list"; "protections"]
        (members r.payload)
  | rs -> Alcotest.failf "expected 1 row, got %d" (List.length rs)

(* ---------- run ---------- *)

let case name f = (name, `Quick, f)

let suite =
  ( "regional",
    [
      case
        "Digitalis: input, requests strictly in order, taxref and tela both \
         Complete with every member"
        digitalis_full;
      case
        "Arnica: input uses P3186 (83874), not P3105's 6648; no request to nn \
         6648"
        arnica_full;
      case
        "bridge (no P3186): Reynoutria's bdtfx nn resolves to Fallopia \
         japonica, INPN runs on the valid id 117503 (INVASIVE)"
        bridge_no_p3186;
      case
        "no TaxRef id at all (Victoria amazonica): only the names call, both \
         rows Missing {}, the six regional fields project to None"
        no_taxref_id;
      case "name = None, taxref = Some: no Tela call, INPN runs, tela missing"
        (name_none_with_taxref ~settled:true);
      case "name = None, taxref = Some, not settled: tela failed (not missing)"
        (name_none_with_taxref ~settled:false);
      case "name = None, taxref = None, not settled: no request, both failed"
        (name_and_taxref_none ~settled:false);
      case "name = None, taxref = None, settled: no request, both missing"
        (name_and_taxref_none ~settled:true);
      case
        "names Failed, no P3186: tela failed, taxref failed (bridge failed), \
         no INPN call"
        names_failed_no_p3186_no_inpn_call;
      case "names Failed, with P3186: INPN still runs, taxref complete"
        names_failed_with_p3186_inpn_still_runs;
      case "baseflor Absent: tela complete without the baseflor member"
        baseflor_absent_tela_complete_without_member;
      case "baseflor Failed: tela partial, keeps names and taxon"
        baseflor_failed_tela_partial;
      case "inpn name Absent: taxref missing {}, no further INPN call"
        inpn_name_absent_taxref_missing_no_further_call;
      case "inpn red_list Failed: taxref partial, keeps name/status/protections"
        inpn_red_list_failed_taxref_partial;
      case "taxon Failed: tela partial {names}, taxref failed" taxon_failed;
      case "taxon undecodable: tela partial {names}, taxref failed"
        taxon_undecodable;
      case "taxon Absent: tela missing {names}, taxref missing" taxon_absent;
      case
        "taxon without cd_nom, no P3186: tela missing {names; taxon}, taxref \
         missing, no INPN call"
        taxon_without_cd_nom;
      case "pick finds no exact name: tela missing {names}, taxref missing"
        pick_none_unmatched;
      case
        "not settled, names Absent: taxref failed (the id may still come from \
         Wikidata)"
        unsettled_names_absent_taxref_failed;
      case "inpn name Failed: taxref failed {}, no further INPN call"
        (inpn_name_not_decoded (Step.Failed "x"));
      case "inpn name undecodable: taxref failed {}, no further INPN call"
        (inpn_name_not_decoded (Step.Body (`Assoc [])));
      case "inpn protections Absent: taxref partial without protections"
        inpn_protections_absent_partial;
      case "P3186 wins over the bridge's cd_nom" p3186_wins_over_bridge_cd_nom;
      case
        "a subspecies bridges by its name with « subsp. » (recorded Tela \
         payloads)"
        subspecies_bridges;
      case
        "input: name falls back to a stored live gbif row when this fetch's \
         gbif row failed"
        input_name_from_stored_gbif_when_this_fetch_failed;
      case
        "input: taxref falls back to the stored entity when this fetch's \
         wikidata row failed"
        input_taxref_from_stored_entity_when_this_fetch_failed;
      case "input: a stored Missing wikidata row settles the wikidata side"
        input_settled_by_stored_missing_wikidata;
      case
        "input: a Failed wikidata row with no stored row leaves the plant \
         unsettled"
        input_wikidata_failed_no_stored_is_unsettled;
      case "input: gbif and wikidata both Missing is settled"
        input_both_missing_is_settled;
      case
        "input: an entity that decodes to None (missing item) gives taxref None"
        input_entity_decoded_to_none_is_no_taxref;
      case
        "Fanout.decide: a Failed Tela row with a live previous row is dropped"
        decide_drops_failed_tela_row_with_live_previous;
      case
        "Fanout.decide: a Partial Taxref row merges the previous row's missing \
         members"
        decide_partial_taxref_merges_previous_red_list;
    ] )
