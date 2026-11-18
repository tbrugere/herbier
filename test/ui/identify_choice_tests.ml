(* Choice.resolve driven through Step.run / Step.requests over a URL ->
   fixture table, as test/refs/test_resolve.ml drives Resolve.resolve. No DOM,
   no network. Choice.settle's Candidates and Observation_link branches are
   not reached: first_link only builds Gbif and Plantnet links. *)

module Identify = Herbier_ui_model.Identify
module Choice = Identify.Choice
module Plantnet = Herbier_identify.Plantnet
module Link = Herbier_domain.Link
module Plant = Herbier_domain.Plant
module Step = Herbier_refs.Step
module Request = Herbier_refs.Request
module Decode = Herbier_refs.Decode
module Gbif = Herbier_refs.Sources.Gbif
module Fixture = Herbier_test_support.Fixture

(* ---------- a fixed network, as test/refs/fake_net.ml ---------- *)

let url (r : Request.t) = Request.(r.url)

let body_of_fixture file : Step.response =
  match Decode.json_of_string (Fixture.read file) with
  | Ok json -> Body json
  | Error e -> Alcotest.failf "%s: %s" file (Decode.error_to_string e)

let base_fail (r : Request.t) : Step.response =
  Alcotest.failf "unexpected request %s" (url r)

(* Answers a request whose URL is a key of [table] with the parsed body of
   that fixture; any other URL fails the test, pinning the exact calls
   made. *)
let fixtures (table : (string * string) list) (r : Request.t) : Step.response =
  match List.assoc_opt (url r) table with
  | Some file -> body_of_fixture file
  | None -> base_fail r

(* [with_ overrides base]: a request whose URL is a key of [overrides]
   answers with the given response (typically [Absent] or [Failed _]); any
   other falls through to [base]. *)
let with_ (overrides : (string * Step.response) list) base (r : Request.t) :
    Step.response =
  match List.assoc_opt (url r) overrides with
  | Some resp -> resp
  | None -> base r

let some name = function
  | Some r -> r
  | None -> Alcotest.failf "%s: expected Some" name

let match_req name = some "match_name" (Gbif.match_name ~name)
let run_choice net p = Step.run net (Choice.resolve p)

let requests_of net p =
  List.map (fun (r : Request.t) -> r.url) (Step.requests net (Choice.resolve p))

(* ---------- the two proposals from the recorded answer ---------- *)

let decode name =
  match Plantnet.decode_answer (Fixture.read name) with
  | Ok a -> a
  | Error e -> Alcotest.failf "decode %s: %s" name (Plantnet.error_to_string e)

let uncertain_answer = lazy (decode "plantnet_identify_one_auto_200.json")

let nth n =
  match List.nth_opt (Lazy.force uncertain_answer).proposals n with
  | Some p -> p
  | None ->
      Alcotest.failf "plantnet_identify_one_auto_200.json has no proposal %d" n

(* P1: Hibiscus rosa-sinensis L., gbif 3152559, "Rose de Chine" first. *)
let p1 = lazy (nth 0)

(* P4: "Hibiscus spp." (genus-level), gbif null. *)
let p4 = lazy (nth 3)

(* ---------- GBIF's own taxa, decoded from the recorded payloads ---------- *)

let json_of_fixture file =
  match Decode.json_of_string (Fixture.read file) with
  | Ok j -> j
  | Error e -> Alcotest.failf "%s: %s" file (Decode.error_to_string e)

let species_3152559 =
  lazy
    (match
       Gbif.species_of_json (json_of_fixture "gbif_species_3152559.json")
     with
    | Ok t -> t
    | Error e ->
        Alcotest.failf "gbif_species_3152559.json: %s"
          (Decode.error_to_string e))

let matched_rosa_sinensis =
  lazy
    (match
       Gbif.match_of_json
         (json_of_fixture "gbif_match_hibiscus_rosa_sinensis_l.json")
     with
    | Ok (Gbif.Matched {taxon; _}) -> taxon
    | Ok (Gbif.Higher_rank _ | Gbif.No_match) ->
        Alcotest.fail "gbif_match_hibiscus_rosa_sinensis_l.json: not Matched"
    | Error e ->
        Alcotest.failf "gbif_match_hibiscus_rosa_sinensis_l.json: %s"
          (Decode.error_to_string e))

(* ---------- testables ---------- *)

let taxon_t = Alcotest.testable Gbif.Taxon.pp Gbif.Taxon.equal
let taxon_opt_t = Alcotest.option taxon_t

let pp_resolution fmt = function
  | Choice.Resolved t -> Format.fprintf fmt "Resolved %a" Gbif.Taxon.pp t
  | Choice.Unknown -> Format.pp_print_string fmt "Unknown"
  | Choice.Unavailable m -> Format.fprintf fmt "Unavailable %S" m

let resolution_t = Alcotest.testable pp_resolution Choice.equal_resolution
let show_resolution r = Format.asprintf "%a" pp_resolution r

let link_t =
  Alcotest.testable
    (fun fmt l -> Format.pp_print_string fmt (Link.to_string l))
    Link.equal

let plant_opt_t = Alcotest.option (Alcotest.testable Plant.pp Plant.equal)

(* A taxon with no field in common with any fixture, so a pass-through check
   ("Resolved t -> Some t") cannot be satisfied by coincidence. *)
let stub_taxon : Gbif.Taxon.t =
  {
    key = 999999;
    scientific_name = "Stub sp.";
    canonical_name = None;
    authorship = None;
    rank = None;
    status = None;
    accepted_key = None;
    family = None;
    vernacular_name = None;
  }

(* ============================================================ *)
(* first_link *)
(* ============================================================ *)

let first_link_tests () =
  let p1 = Lazy.force p1 and p4 = Lazy.force p4 in
  Alcotest.(check link_t)
    "P1 (gbif = Some 3152559) -> Gbif 3152559" (Link.Gbif 3152559)
    (Choice.first_link p1);
  Alcotest.(check link_t)
    "P4 (gbif = None) -> Plantnet of its scientific_name"
    (Link.Plantnet "Hibiscus spp.") (Choice.first_link p4)

(* ============================================================ *)
(* resolve *)
(* ============================================================ *)

let resolve_by_id_only () =
  let p1 = Lazy.force p1 in
  let net =
    fixtures [(url (Gbif.species ~key:3152559), "gbif_species_3152559.json")]
  in
  Alcotest.(check resolution_t)
    "GBIF's own taxon, not Pl@ntNet's stand-in"
    (Choice.Resolved (Lazy.force species_3152559))
    (run_choice net p1);
  Alcotest.(check (list string))
    "requests: the species lookup only"
    [url (Gbif.species ~key:3152559)]
    (requests_of net p1)

let resolve_synonym_one_hop () =
  let p1 = Lazy.force p1 in
  let synonym = {p1 with gbif = Some 5334357} in
  let net =
    fixtures
      [
        (url (Gbif.species ~key:5334357), "gbif_species_5334357.json");
        (url (Gbif.species ~key:2889173), "gbif_species_2889173.json");
      ]
  in
  (match run_choice net synonym with
  | Choice.Resolved t ->
      Alcotest.(check int) "key: the accepted species, one hop" 2889173 t.key
  | r -> Alcotest.failf "expected Resolved, got %s" (show_resolution r));
  Alcotest.(check (list string))
    "requests: the synonym, then the accepted species"
    [url (Gbif.species ~key:5334357); url (Gbif.species ~key:2889173)]
    (requests_of net synonym)

let resolve_unknown_id_falls_back_to_name_match () =
  let p1 = Lazy.force p1 in
  let net =
    with_
      [(url (Gbif.species ~key:3152559), Step.Absent)]
      (fixtures
         [
           ( url (match_req p1.scientific_name),
             "gbif_match_hibiscus_rosa_sinensis_l.json" );
         ])
  in
  Alcotest.(check resolution_t)
    "GBIF's taxon from the name match, not Pl@ntNet's stand-in"
    (Choice.Resolved (Lazy.force matched_rosa_sinensis))
    (run_choice net p1);
  Alcotest.(check (list string))
    "requests: the id, then the name match (R12)"
    [url (Gbif.species ~key:3152559); url (match_req p1.scientific_name)]
    (requests_of net p1)

let resolve_no_id_genus_match_is_unknown () =
  let p4 = Lazy.force p4 in
  let net =
    fixtures
      [(url (match_req p4.scientific_name), "gbif_match_hibiscus_spp.json")]
  in
  Alcotest.(check resolution_t)
    "\"Hibiscus spp.\" (HIGHERRANK, genus) -> Unknown" Choice.Unknown
    (run_choice net p4);
  Alcotest.(check (list string))
    "requests: the name match only, no id to look up"
    [url (match_req p4.scientific_name)]
    (requests_of net p4)

let resolve_failed_id_lookup_is_unavailable_no_second_call () =
  let p1 = Lazy.force p1 in
  let net =
    with_ [(url (Gbif.species ~key:3152559), Step.Failed "x")] base_fail
  in
  Alcotest.(check resolution_t)
    "a failed id lookup -> Unavailable \"x\"" (Choice.Unavailable "x")
    (run_choice net p1);
  Alcotest.(check (list string))
    "requests: the id lookup only, no name match after a failed call"
    [url (Gbif.species ~key:3152559)]
    (requests_of net p1)

let resolve_failed_name_match_is_unavailable () =
  let p1 = Lazy.force p1 in
  let net =
    with_
      [
        (url (Gbif.species ~key:3152559), Step.Absent);
        (url (match_req p1.scientific_name), Step.Failed "y");
      ]
      base_fail
  in
  Alcotest.(check resolution_t)
    "the id unknown, then a failed name match -> Unavailable \"y\""
    (Choice.Unavailable "y") (run_choice net p1);
  Alcotest.(check (list string))
    "requests: the id, then the name match, once each"
    [url (Gbif.species ~key:3152559); url (match_req p1.scientific_name)]
    (requests_of net p1)

let resolve_no_id_species_match () =
  let no_id = {(Lazy.force p1) with gbif = None} in
  let net =
    fixtures
      [
        ( url (match_req no_id.scientific_name),
          "gbif_match_hibiscus_rosa_sinensis_l.json" );
      ]
  in
  Alcotest.(check resolution_t)
    "no id, a species-rank match -> Resolved, GBIF's taxon"
    (Choice.Resolved (Lazy.force matched_rosa_sinensis))
    (run_choice net no_id);
  Alcotest.(check (list string))
    "requests: the name match only"
    [url (match_req no_id.scientific_name)]
    (requests_of net no_id)

let resolve_no_id_failed_match () =
  let no_id = {(Lazy.force p1) with gbif = None} in
  let net =
    with_ [(url (match_req no_id.scientific_name), Step.Failed "z")] base_fail
  in
  Alcotest.(check resolution_t)
    "no id, a failed name match -> Unavailable \"z\"" (Choice.Unavailable "z")
    (run_choice net no_id);
  Alcotest.(check (list string))
    "requests: the name match only"
    [url (match_req no_id.scientific_name)]
    (requests_of net no_id)

let resolve_unknown_id_then_genus_match_is_unknown () =
  let p1 = Lazy.force p1 in
  (* The genus-level answer stands in for P1's name match: GBIF answered,
     and not at species rank. *)
  let net =
    with_
      [(url (Gbif.species ~key:3152559), Step.Absent)]
      (fixtures
         [(url (match_req p1.scientific_name), "gbif_match_hibiscus_spp.json")])
  in
  Alcotest.(check resolution_t)
    "the id unknown, then a match above species rank -> Unknown" Choice.Unknown
    (run_choice net p1)

(* ============================================================ *)
(* plantnet_taxon *)
(* ============================================================ *)

let plantnet_taxon_tests () =
  let p1 = Lazy.force p1 and p4 = Lazy.force p4 in
  let expected_p1 : Gbif.Taxon.t =
    {
      key = 3152559;
      scientific_name = "Hibiscus rosa-sinensis L.";
      canonical_name = Some "Hibiscus rosa-sinensis";
      authorship = Some "L.";
      rank = None;
      status = None;
      accepted_key = None;
      family = Some "Malvaceae";
      vernacular_name = None;
    }
  in
  Alcotest.(check taxon_opt_t)
    "P1 (gbif = Some k): plantnet_taxon from Pl@ntNet's own fields"
    (Some expected_p1) (Choice.plantnet_taxon p1);
  Alcotest.(check taxon_opt_t)
    "P4 (gbif = None) -> None" None (Choice.plantnet_taxon p4);
  let blank_author = {p1 with author = ""} in
  Alcotest.(check (option string))
    "author = \"\" -> authorship = None" None
    (Option.bind (Choice.plantnet_taxon blank_author) (fun (t : Gbif.Taxon.t) ->
         t.authorship))

(* ============================================================ *)
(* taxon *)
(* ============================================================ *)

let taxon_tests () =
  let p1 = Lazy.force p1 and p4 = Lazy.force p4 in
  let v_p1 = Choice.v p1 in
  Alcotest.(check taxon_opt_t)
    "no resolution yet (v) -> plantnet_taxon" (Choice.plantnet_taxon p1)
    (Choice.taxon v_p1);
  Alcotest.(check taxon_opt_t)
    "Unavailable -> plantnet_taxon (a save before/after a failed GBIF call)"
    (Choice.plantnet_taxon p1)
    (Choice.taxon (Choice.resolved v_p1 (Choice.Unavailable "x")));
  Alcotest.(check taxon_opt_t)
    "Resolved t -> Some t" (Some stub_taxon)
    (Choice.taxon (Choice.resolved v_p1 (Choice.Resolved stub_taxon)));
  Alcotest.(check taxon_opt_t)
    "Unknown -> None (GBIF knows no such species: a free name)" None
    (Choice.taxon (Choice.resolved v_p1 Choice.Unknown));
  Alcotest.(check taxon_opt_t)
    "P4 (gbif = None, no resolution) -> None" None
    (Choice.taxon (Choice.v p4))

(* ============================================================ *)
(* keys *)
(* ============================================================ *)

let keys_tests () =
  let p1 = Lazy.force p1 and p4 = Lazy.force p4 in
  Alcotest.(check (list int))
    "v P1 -> [3152559]" [3152559]
    (Choice.keys (Choice.v p1));
  let synonym = {p1 with gbif = Some 5334357} in
  let accepted = {stub_taxon with key = 2889173} in
  Alcotest.(check (list int))
    "synonym resolved: the proposal's key, then the accepted one"
    [5334357; 2889173]
    (Choice.keys
       (Choice.resolved (Choice.v synonym) (Choice.Resolved accepted)));
  Alcotest.(check (list int))
    "v P4 (gbif = None) -> []" []
    (Choice.keys (Choice.v p4));
  let same_key = {stub_taxon with key = 3152559} in
  Alcotest.(check (list int))
    "no duplicate when the resolved key equals the proposal's" [3152559]
    (Choice.keys (Choice.resolved (Choice.v p1) (Choice.Resolved same_key)));
  let with_accepted =
    {stub_taxon with key = 7971454; accepted_key = Some 5708907}
  in
  Alcotest.(check (list int))
    "a resolved taxon's accepted_key comes last"
    [3152559; 7971454; 5708907]
    (Choice.keys
       (Choice.resolved (Choice.v p1) (Choice.Resolved with_accepted)))

(* ============================================================ *)
(* owner *)
(* ============================================================ *)

let owner_tests () =
  let p1 = Lazy.force p1 and p4 = Lazy.force p4 in
  let live = Fixtures.plant_with ~gbif_key:(Some 3152559) () in
  Alcotest.(check plant_opt_t)
    "a live plant with that gbif_key" (Some live)
    (Choice.owner ~plants:[live] (Choice.v p1));
  let dead = {live with deleted_at = Some (Fixtures.utc 2026 1 1 0 0)} in
  Alcotest.(check plant_opt_t)
    "the same plant deleted -> None" None
    (Choice.owner ~plants:[dead] (Choice.v p1));
  let other = Fixtures.plant_with ~gbif_key:(Some 3152559) () in
  Alcotest.(check plant_opt_t)
    "two matching plants: the first in list order" (Some live)
    (Choice.owner ~plants:[live; other] (Choice.v p1));
  let synonym = {p1 with gbif = Some 5334357} in
  let accepted = {stub_taxon with key = 2889173} in
  let synonym_plant = Fixtures.plant_with ~gbif_key:(Some 2889173) () in
  Alcotest.(check plant_opt_t)
    "a synonym id, not yet resolved: the accepted key is not known yet" None
    (Choice.owner ~plants:[synonym_plant] (Choice.v synonym));
  Alcotest.(check plant_opt_t)
    "the same synonym, resolved: the plant with the accepted key matches"
    (Some synonym_plant)
    (Choice.owner ~plants:[synonym_plant]
       (Choice.resolved (Choice.v synonym) (Choice.Resolved accepted)));
  let on_synonym = Fixtures.plant_with ~gbif_key:(Some 5334357) () in
  let resolved =
    Choice.resolved (Choice.v synonym) (Choice.Resolved accepted)
  in
  Alcotest.(check plant_opt_t)
    "one plant on the proposal's id, another on the accepted key: the first in \
     list order"
    (Some synonym_plant)
    (Choice.owner ~plants:[synonym_plant; on_synonym] resolved);
  Alcotest.(check plant_opt_t)
    "the same two plants the other way round: the first in list order"
    (Some on_synonym)
    (Choice.owner ~plants:[on_synonym; synonym_plant] resolved);
  let unlinked = Fixtures.plant_with ~gbif_key:None () in
  Alcotest.(check plant_opt_t)
    "P4 (gbif = None) -> None even with an unlinked plant" None
    (Choice.owner ~plants:[unlinked] (Choice.v p4))

(* ============================================================ *)
(* new_name, label *)
(* ============================================================ *)

let new_name_and_label_tests () =
  let p1 = Lazy.force p1 in
  Alcotest.(check string)
    "new_name: the first common name" "Rose de Chine" (Choice.new_name p1);
  let no_common = {p1 with common_names = []} in
  Alcotest.(check string)
    "new_name: no common names -> the Latin name" "Hibiscus rosa-sinensis"
    (Choice.new_name no_common);
  let owner = Fixtures.plant_with () in
  Alcotest.(check string)
    "label, owned: the owner's display name" owner.display_name
    (Choice.label ~owner:(Some owner) p1);
  Alcotest.(check string)
    "label, not owned: new_name" "Rose de Chine"
    (Choice.label ~owner:None p1)

let identify_choice =
  [
    Alcotest.test_case
      "first_link: Gbif k when an id is given, else Plantnet of the Latin name"
      `Quick first_link_tests;
    Alcotest.test_case "resolve: an id resolves by itself" `Quick
      resolve_by_id_only;
    Alcotest.test_case
      "resolve: a synonym id is followed one hop to its accepted species" `Quick
      resolve_synonym_one_hop;
    Alcotest.test_case
      "resolve: an id GBIF does not know falls back to the name match (R12)"
      `Quick resolve_unknown_id_falls_back_to_name_match;
    Alcotest.test_case "resolve: no id, a genus-level match is Unknown" `Quick
      resolve_no_id_genus_match_is_unknown;
    Alcotest.test_case "resolve: no id, a species-rank match is Resolved" `Quick
      resolve_no_id_species_match;
    Alcotest.test_case "resolve: no id, a failed name match is Unavailable"
      `Quick resolve_no_id_failed_match;
    Alcotest.test_case
      "resolve: a failed id lookup is Unavailable, no name match attempted"
      `Quick resolve_failed_id_lookup_is_unavailable_no_second_call;
    Alcotest.test_case
      "resolve: the id unknown, then a failed name match, is Unavailable" `Quick
      resolve_failed_name_match_is_unavailable;
    Alcotest.test_case
      "resolve: the id unknown, then a match above species rank, is Unknown"
      `Quick resolve_unknown_id_then_genus_match_is_unknown;
    Alcotest.test_case
      "plantnet_taxon: Pl@ntNet's own fields, no network; a blank author is no \
       authorship"
      `Quick plantnet_taxon_tests;
    Alcotest.test_case "taxon: Resolved, Unknown, pending and Unavailable"
      `Quick taxon_tests;
    Alcotest.test_case
      "keys: the proposal's id then the resolved one, each once" `Quick
      keys_tests;
    Alcotest.test_case
      "owner: live, deleted, list order, a synonym before and after resolution"
      `Quick owner_tests;
    Alcotest.test_case
      "new_name and label: the first common name, else the Latin name, else \
       the owner's name"
      `Quick new_name_and_label_tests;
  ]
