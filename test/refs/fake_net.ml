(* Runs a [Step.t] over a fixed table of recorded fixtures, standing in for
   the network answers of [Herbier_refs_io.Http.run]. A URL not in the table
   fails the test immediately, so every test using it pins the exact
   requests the program under test makes, in order. *)

module Step = Herbier_refs.Step
module Request = Herbier_refs.Request
module Decode = Herbier_refs.Decode
module Gbif = Herbier_refs.Sources.Gbif
module Wikidata = Herbier_refs.Sources.Wikidata
module Wikipedia = Herbier_refs.Sources.Wikipedia
module Tela = Herbier_refs.Sources.Tela
module Inpn = Herbier_refs.Sources.Inpn
module Plantuse = Herbier_refs.Sources.Plantuse
module Qid = Herbier_refs.Qid
module Fixture = Herbier_test_support.Fixture

let url (r : Request.t) = Request.(r.url)

let some name = function
  | Some r -> r
  | None -> Alcotest.failf "fake_net: %s: expected Some" name

(* A [_404.txt] fixture is a recorded 404 body: [Step.Absent], never parsed.
   Any other name must be JSON, so a stray file fails loudly. *)
let body_of_fixture file : Step.response =
  match Filename.check_suffix file "_404.txt" with
  | true -> Step.Absent
  | false -> (
      match Decode.json_of_string (Fixture.read file) with
      | Ok json -> Body json
      | Error e ->
          Alcotest.failf "fake_net: %s: %s" file (Decode.error_to_string e))

(* [fixtures table] answers a request whose URL is a key of [table] with the
   parsed body of that fixture file; any other URL fails the test. *)
let fixtures (table : (string * string) list) (r : Request.t) : Step.response =
  match List.assoc_opt (url r) table with
  | Some file -> body_of_fixture file
  | None -> Alcotest.failf "unexpected request %s" (url r)

(* [with_ overrides base] answers a request whose URL is a key of
   [overrides] with the given response (typically [Absent] or
   [Failed "x"]); any other URL falls through to [base]. *)
let with_ (overrides : (string * Step.response) list) base (r : Request.t) :
    Step.response =
  match List.assoc_opt (url r) overrides with
  | Some resp -> resp
  | None -> base r

(* The URL->fixture table of one species' full fetch (architecture §6): the
   four gbif calls, the plantnet media call, and the wikidata search +
   entity + wikipedia fr summary. *)
let full_fetch ~gbif_key ~species ~vernacular_names ~distributions
    ~occurrence_count ~plantnet_media ~wikidata_search ~entity_qid
    ~wikidata_entity ~summary_lang ~summary_title ~wikipedia_summary
    ~wikipedia_extract_fr ?wikipedia_extract_en () =
  let qid = some "entity_qid" (Qid.of_string entity_qid) in
  fixtures
    ([
       (url (Gbif.species ~key:gbif_key), species);
       (url (Gbif.vernacular_names ~key:gbif_key), vernacular_names);
       (url (Gbif.distributions ~key:gbif_key), distributions);
       (url (Gbif.occurrence_count ~key:gbif_key), occurrence_count);
       (url (Gbif.plantnet_media ~key:gbif_key), plantnet_media);
       ( url
           (some "search"
              (Wikidata.search ~property:Wikidata.Property.Gbif_key
                 ~value:(string_of_int gbif_key))),
         wikidata_search );
       (url (Wikidata.entity qid), wikidata_entity);
       ( url
           (some "summary"
              (Wikipedia.summary ~lang:summary_lang ~title:summary_title)),
         wikipedia_summary );
       ( url
           (some "extract fr"
              (Wikipedia.extract ~lang:summary_lang ~title:summary_title)),
         wikipedia_extract_fr );
     ]
    @
    match wikipedia_extract_en with
    | None -> []
    | Some file ->
        [
          ( url
              (some "extract en"
                 (Wikipedia.extract ~lang:"en" ~title:summary_title)),
            file );
        ])

(* Digitalis purpurea (gbif_key 5414995), every call Complete. *)
let digitalis =
  full_fetch ~gbif_key:5414995 ~species:"gbif_species_5414995.json"
    ~vernacular_names:"gbif_vernacular_names_5414995.json"
    ~distributions:"gbif_distributions_5414995.json"
    ~occurrence_count:"gbif_occurrence_count_5414995.json"
    ~plantnet_media:"gbif_plantnet_media_5414995.json"
    ~wikidata_search:"wikidata_search_p846_5414995.json" ~entity_qid:"Q157555"
    ~wikidata_entity:"wikidata_entity_Q157555.json" ~summary_lang:"fr"
    ~summary_title:"Digitalis purpurea"
    ~wikipedia_summary:"wikipedia_summary_fr_Digitalis_purpurea.json"
    ~wikipedia_extract_fr:"wikipedia_extract_fr_Digitalis_purpurea.json"
      (* fr has no uses section: the branch also tries en. *)
    ~wikipedia_extract_en:"wikipedia_extract_en_Digitalis_purpurea.json" ()

(* Arnica montana (gbif_key 5405976): its frwiki sitelink title is "Arnica
   des montagnes", not the scientific name. *)
let arnica =
  full_fetch ~gbif_key:5405976 ~species:"gbif_species_5405976.json"
    ~vernacular_names:"gbif_vernacular_names_5405976.json"
    ~distributions:"gbif_distributions_5405976.json"
    ~occurrence_count:"gbif_occurrence_count_5405976.json"
    ~plantnet_media:"gbif_plantnet_media_5405976.json"
    ~wikidata_search:"wikidata_search_p846_5405976.json" ~entity_qid:"Q207848"
    ~wikidata_entity:"wikidata_entity_Q207848.json" ~summary_lang:"fr"
    ~summary_title:"Arnica des montagnes"
    ~wikipedia_summary:"wikipedia_summary_fr_Arnica_des_montagnes.json"
    ~wikipedia_extract_fr:"wikipedia_extract_fr_Arnica_des_montagnes.json" ()
(* fr has a uses section: the branch stops there, no en extract call. *)

(* The regional layer's URL->fixture overrides for one taxon: Tela's
   name bridge (by scientific [name]), its taxon call (by [taxon_nn], the
   bridge's bdtfx id) and Baseflor call (by [baseflor_nn], the taxon's own
   accepted id: equal to [taxon_nn] unless the bridge nn is a synonym), and
   INPN's name call (by [cd_nom]) then status/red_list/protections (by
   [cd_ref], the valid TaxRef id: equal to [cd_nom] unless it is a synonym).
   Meant to be passed to [with_] over a base net (typically
   [digitalis]/[arnica]): any URL this does not cover falls through to the
   base, so an unexpected request still fails the test. [baseflor] is a
   fixture name ending in [_404.txt] for a Tela taxon with no Baseflor row. *)
let regional_fetch ~name ~taxon_nn ~baseflor_nn ~names ~taxon ~baseflor ~cd_nom
    ~cd_ref ~inpn_name ~status ~red_list ~protections =
  [
    (url (some "names" (Tela.names ~name)), names);
    (url (Tela.taxon ~nn:taxon_nn), taxon);
    (url (Tela.baseflor ~nn:baseflor_nn), baseflor);
    (url (Inpn.name ~cd_nom), inpn_name);
    (url (Inpn.status ~cd_ref), status);
    (url (Inpn.red_list ~cd_ref), red_list);
    (url (Inpn.protections ~cd_ref), protections);
  ]
  |> List.map (fun (u, file) -> (u, body_of_fixture file))

(* Digitalis purpurea's regional calls, from the recorded fixtures. *)
let digitalis_regional =
  regional_fetch ~name:"Digitalis purpurea" ~taxon_nn:22437 ~baseflor_nn:22437
    ~names:"tela_names_digitalis_purpurea.json" ~taxon:"tela_taxon_22437.json"
    ~baseflor:"tela_baseflor_22437.json" ~cd_nom:94959 ~cd_ref:94959
    ~inpn_name:"inpn_name_94959.json" ~status:"inpn_status_94959.json"
    ~red_list:"inpn_red_list_94959.json"
    ~protections:"inpn_protections_94959.json"

(* The URL->fixture entry of a [Plantuse.page] request for [titles],
   for [Uses_fetch.program] tests (the plantuse row, run beside Regional,
   not part of [Fanout.branches]). *)
let plantuse_table ~titles file =
  [(url (some "plantuse page" (Plantuse.page ~titles)), body_of_fixture file)]

(* [without path json]: [json] with the member at [path] (object keys from
   the root) removed, to build a variant of a recorded body in a test
   without editing the fixture file. A missing step fails the test. *)
let rec without path (json : Yojson.Safe.t) : Yojson.Safe.t =
  match (path, json) with
  | [], _ -> Alcotest.fail "fake_net: without: empty path"
  | [key], `Assoc kvs when List.mem_assoc key kvs ->
      `Assoc (List.remove_assoc key kvs)
  | key :: rest, `Assoc kvs when List.mem_assoc key kvs ->
      `Assoc
        (List.map
           (fun (k, v) ->
             match String.equal k key with
             | true -> (k, without rest v)
             | false -> (k, v))
           kvs)
  | key :: _, _ -> Alcotest.failf "fake_net: without: no member %s" key

(* The parsed body of a fixture file, as a JSON value. *)
let json_of_fixture file : Yojson.Safe.t =
  match body_of_fixture file with
  | Body json -> json
  | Absent | Failed _ -> Alcotest.failf "fake_net: %s: not a body" file
