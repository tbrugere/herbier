(* Intercept: 4j's pure state (incoming text, the sheet's state machine, card
   texts, recent tags, the first observation), without network, timers or
   DOM. *)

module Gps = Herbier_ui_model.Gps
module Intercept = Herbier_ui_model.Intercept
module Plant_id = Herbier_domain.Ids.Plant_id
module Plant = Herbier_domain.Plant
module Gbif = Herbier_refs.Sources.Gbif
module Resolve = Herbier_refs.Resolve
module Link = Herbier_domain.Link
module Ids = Herbier_domain.Ids
module Observation = Herbier_domain.Observation
module Tag = Herbier_domain.Tag

let utc = Fixtures.utc
let base_plant = Fixtures.base_plant
let digitalis_taxon = Fixtures.digitalis_taxon
let plant_with = Fixtures.plant_with
let tag_id = Fixtures.tag_id
let plant_id = Fixtures.plant_id

(* ---------- of_url / of_share ---------- *)

let intercept_of_url_and_share () =
  Alcotest.(check (option string))
    "of_url: trimmed" (Some "https://www.gbif.org/species/1")
    (Intercept.of_url "  https://www.gbif.org/species/1 \n");
  Alcotest.(check (option string))
    "of_url: blank is None" None (Intercept.of_url "  ");
  let plantnet_url =
    "Digitalis purpurea L. \
     https://identify.plantnet.org/fr/k-world-flora/species/Digitalis%20purpurea%20L./data"
  in
  Alcotest.(check (option string))
    "of_share: the trimmed non-blank text, title not added" (Some plantnet_url)
    (Intercept.of_share ~title:"Pl@ntNet" ~texts:[" " ^ plantnet_url ^ " "]);
  Alcotest.(check (option string))
    "of_share: no texts, the trimmed title" (Some "Digitale")
    (Intercept.of_share ~title:" Digitale " ~texts:[]);
  Alcotest.(check (option string))
    "of_share: blank texts fall back to the title" (Some "x")
    (Intercept.of_share ~title:"x" ~texts:[" "; ""]);
  Alcotest.(check (option string))
    "of_share: non-blank texts joined with \\n, blank ones dropped"
    (Some "a\nb")
    (Intercept.of_share ~title:"" ~texts:["a"; " "; "b "]);
  Alcotest.(check (option string))
    "of_share: blank title and blank texts is None" None
    (Intercept.of_share ~title:" " ~texts:[" "])

(* ---------- header, query ---------- *)

let intercept_header_per_constructor () =
  let case what expected link =
    Alcotest.(check string) what expected (Intercept.header link)
  in
  case "Gbif" "lien GBIF reconnu" (Link.Gbif 5414995);
  case "Plantnet" "lien Pl@ntNet reconnu"
    (Link.Plantnet "Digitalis purpurea L.");
  case "Plantnet_observation" "lien Pl@ntNet reconnu"
    (Link.Plantnet_observation "1012345678");
  case "Plantuse" "lien Pl@ntUse reconnu" (Link.Plantuse "Digitalis purpurea");
  case "Wikipedia" "lien Wikipédia reconnu"
    (Link.Wikipedia {lang = "fr"; title = "Digitale pourpre"});
  case "Inpn" "lien INPN reconnu" (Link.Inpn 94959);
  case "Tela" "lien Tela Botanica reconnu" (Link.Tela 22437);
  case "Powo" "lien POWO reconnu" (Link.Powo "urn:lsid:ipni.org:names:802077-1");
  case "Inat" "lien iNaturalist reconnu" (Link.Inat 53983);
  case "Text" "partage reçu" (Link.Text "digitale pourpre")

let intercept_query_per_constructor () =
  Alcotest.(check string)
    "Plantnet" "Digitalis purpurea L."
    (Intercept.query (Link.Plantnet "Digitalis purpurea L."));
  Alcotest.(check string)
    "Plantuse" "Digitalis purpurea"
    (Intercept.query (Link.Plantuse "Digitalis purpurea"));
  Alcotest.(check string)
    "Wikipedia: the title" "Digitale pourpre"
    (Intercept.query (Link.Wikipedia {lang = "fr"; title = "Digitale pourpre"}));
  Alcotest.(check string)
    "Text: trimmed" "digitale"
    (Intercept.query (Link.Text "  digitale "));
  Alcotest.(check string) "Gbif: empty" "" (Intercept.query (Link.Gbif 5));
  Alcotest.(check string)
    "Plantnet_observation: empty" ""
    (Intercept.query (Link.Plantnet_observation "1012345678"));
  Alcotest.(check string) "Inpn: empty" "" (Intercept.query (Link.Inpn 94959));
  Alcotest.(check string) "Tela: empty" "" (Intercept.query (Link.Tela 22437));
  Alcotest.(check string)
    "Powo: empty" ""
    (Intercept.query (Link.Powo "urn:lsid:ipni.org:names:802077-1"));
  Alcotest.(check string) "Inat: empty" "" (Intercept.query (Link.Inat 53983))

(* ---------- the state machine ---------- *)

let intercept_status_str = function
  | Intercept.Offline -> "Offline"
  | Intercept.Resolving -> "Resolving"
  | Intercept.Failed m -> "Failed " ^ m
  | Intercept.Found {candidate; existing} ->
      Printf.sprintf "Found {candidate = %d; existing = %s}"
        candidate.Resolve.Candidate.taxon.key
        (match existing with
        | None -> "None"
        | Some (p : Plant.t) -> "Some " ^ Plant_id.to_string p.id)
  | Intercept.Search q -> Printf.sprintf "Search %S" q

let intercept_status =
  Alcotest.testable
    (fun f s -> Format.pp_print_string f (intercept_status_str s))
    Intercept.equal_status

let intercept_effect_str = function
  | Intercept.No_effect -> "No_effect"
  | Intercept.Resolve {seq} -> Printf.sprintf "Resolve {seq = %d}" seq
  | Intercept.Name {seq; taxon} ->
      Printf.sprintf "Name {seq = %d; taxon = %d}" seq taxon.Gbif.Taxon.key

let check_intercept_effect what expected eff =
  Alcotest.(check string) what expected (intercept_effect_str eff)

let candidate_of ?(french = []) taxon : Resolve.Candidate.t = {taxon; french}

let resolving_state () =
  fst
    (Intercept.init ~online:true ~plants:[]
       "https://www.gbif.org/species/5414995")

let found_state () =
  let t0 = resolving_state () in
  let t1, _ = Intercept.resolved ~seq:0 (Resolve.Taxon digitalis_taxon) t0 in
  Intercept.named ~seq:0 (candidate_of digitalis_taxon) t1

let search_state () = fst (Intercept.init ~online:true ~plants:[] "digitale")

let failed_state () =
  let t0 = resolving_state () in
  fst
    (Intercept.resolved ~seq:0
       (Resolve.Unresolved {query = "q"; why = Resolve.Unavailable "timeout"})
       t0)

let intercept_init () =
  let t0, eff0 =
    Intercept.init ~online:true ~plants:[]
      "https://www.gbif.org/species/5414995"
  in
  Alcotest.(check intercept_status)
    "online: Resolving" Intercept.Resolving (Intercept.status t0);
  check_intercept_effect "online: Resolve {seq=0}" "Resolve {seq = 0}" eff0;
  Alcotest.(check int) "seq 0" 0 (Intercept.seq t0);
  let off, eff_off =
    Intercept.init ~online:false ~plants:[]
      "https://www.gbif.org/species/5414995"
  in
  Alcotest.(check intercept_status)
    "offline: Offline" Intercept.Offline (Intercept.status off);
  check_intercept_effect "offline: No_effect" "No_effect" eff_off;
  List.iter
    (fun online ->
      let t, eff = Intercept.init ~online ~plants:[] " digitale " in
      Alcotest.(check intercept_status)
        (Printf.sprintf "Text, online=%b: Search, trimmed" online)
        (Intercept.Search "digitale") (Intercept.status t);
      check_intercept_effect
        (Printf.sprintf "Text, online=%b: No_effect" online)
        "No_effect" eff)
    [true; false];
  let t, eff =
    Intercept.init ~online:true ~plants:[]
      "https://identify.plantnet.org/fr/observations/1012345678"
  in
  Alcotest.(check intercept_status)
    "observation link: Search \"\"" (Intercept.Search "") (Intercept.status t);
  check_intercept_effect "observation link: No_effect" "No_effect" eff

let intercept_resolved_taxon_is_resolving_with_name_effect () =
  let t0 = resolving_state () in
  let t1, eff = Intercept.resolved ~seq:0 (Resolve.Taxon digitalis_taxon) t0 in
  Alcotest.(check intercept_status)
    "still Resolving" Intercept.Resolving (Intercept.status t1);
  check_intercept_effect "Name {seq=0; taxon=d}"
    (Printf.sprintf "Name {seq = 0; taxon = %d}" digitalis_taxon.key)
    eff

let intercept_named_no_match () =
  let t0 = resolving_state () in
  let t1, _ = Intercept.resolved ~seq:0 (Resolve.Taxon digitalis_taxon) t0 in
  let found =
    Intercept.named ~seq:0
      (candidate_of digitalis_taxon ~french:["Digitale pourpre"])
      t1
  in
  match Intercept.status found with
  | Intercept.Found {candidate; existing} ->
      Alcotest.(check int) "candidate's taxon key" 5414995 candidate.taxon.key;
      Alcotest.(check (list string))
        "candidate's french" ["Digitale pourpre"] candidate.french;
      Alcotest.(check bool) "no existing plant" true (Option.is_none existing)
  | s -> Alcotest.failf "expected Found, got %s" (intercept_status_str s)

let intercept_named_matches_live_plant () =
  let p = plant_with ~gbif_key:(Some digitalis_taxon.key) () in
  let t0 =
    fst
      (Intercept.init ~online:true ~plants:[p]
         "https://www.gbif.org/species/5414995")
  in
  let t1, _ = Intercept.resolved ~seq:0 (Resolve.Taxon digitalis_taxon) t0 in
  let found = Intercept.named ~seq:0 (candidate_of digitalis_taxon) t1 in
  match Intercept.status found with
  | Intercept.Found {existing = Some (ep : Plant.t); _} ->
      Alcotest.(check bool)
        "existing is the matching live plant" true
        (Plant_id.equal ep.id p.id)
  | s ->
      Alcotest.failf "expected Found with existing, got %s"
        (intercept_status_str s)

let intercept_named_ignores_deleted_plant () =
  let p =
    plant_with ~gbif_key:(Some digitalis_taxon.key)
      ~deleted_at:(Some (utc 2026 1 1 0 0))
      ()
  in
  let t0 =
    fst
      (Intercept.init ~online:true ~plants:[p]
         "https://www.gbif.org/species/5414995")
  in
  let t1, _ = Intercept.resolved ~seq:0 (Resolve.Taxon digitalis_taxon) t0 in
  let found = Intercept.named ~seq:0 (candidate_of digitalis_taxon) t1 in
  match Intercept.status found with
  | Intercept.Found {existing; _} ->
      Alcotest.(check bool)
        "soft-deleted plant ignored" true (Option.is_none existing)
  | s -> Alcotest.failf "expected Found, got %s" (intercept_status_str s)

let intercept_named_matches_via_synonym_accepted_key () =
  let synonym =
    {
      digitalis_taxon with
      Gbif.Taxon.key = 7971454;
      accepted_key = Some digitalis_taxon.key;
    }
  in
  let p = plant_with ~gbif_key:(Some digitalis_taxon.key) () in
  let t0 =
    fst
      (Intercept.init ~online:true ~plants:[p]
         "https://www.gbif.org/species/7971454")
  in
  let t1, _ = Intercept.resolved ~seq:0 (Resolve.Taxon synonym) t0 in
  let found = Intercept.named ~seq:0 (candidate_of synonym) t1 in
  match Intercept.status found with
  | Intercept.Found {existing = Some (ep : Plant.t); _} ->
      Alcotest.(check bool)
        "matches via the synonym's accepted_key" true
        (Plant_id.equal ep.id p.id)
  | s ->
      Alcotest.failf "expected Found with existing, got %s"
        (intercept_status_str s)

let intercept_resolved_fallback_paths () =
  let t0 = resolving_state () in
  let t1, eff1 =
    Intercept.resolved ~seq:0
      (Resolve.Unresolved
         {query = "Digitalis purpurea L."; why = Resolve.No_species})
      t0
  in
  Alcotest.(check intercept_status)
    "No_species -> Search query" (Intercept.Search "Digitalis purpurea L.")
    (Intercept.status t1);
  check_intercept_effect "No_species: No_effect" "No_effect" eff1;
  let t2, eff2 =
    Intercept.resolved ~seq:0
      (Resolve.Unresolved {query = ""; why = Resolve.Observation_link})
      t0
  in
  Alcotest.(check intercept_status)
    "Observation_link -> Search \"\"" (Intercept.Search "")
    (Intercept.status t2);
  check_intercept_effect "Observation_link: No_effect" "No_effect" eff2;
  let t3, eff3 =
    Intercept.resolved ~seq:0
      (Resolve.Unresolved {query = "q"; why = Resolve.Unavailable "timeout"})
      t0
  in
  Alcotest.(check intercept_status)
    "Unavailable -> Failed" (Intercept.Failed "timeout") (Intercept.status t3);
  check_intercept_effect "Unavailable: No_effect" "No_effect" eff3

let intercept_resolved_candidates_falls_back_to_search () =
  let t0 =
    fst
      (Intercept.init ~online:true ~plants:[]
         "https://plantuse.plantnet.org/fr/Digitalis_purpurea")
  in
  let t1, eff = Intercept.resolved ~seq:0 (Resolve.Candidates []) t0 in
  Alcotest.(check intercept_status)
    "Search (query of the link)" (Intercept.Search "Digitalis purpurea")
    (Intercept.status t1);
  check_intercept_effect "No_effect" "No_effect" eff

(* Offline then online: Resolving again, with a newer seq than the answer
   still pending for seq 0. *)
let intercept_stale_seq_ignored () =
  let off = fst (Intercept.network ~online:false (resolving_state ())) in
  let t, _ = Intercept.network ~online:true off in
  let n = Intercept.seq t in
  Alcotest.(check int) "seq after offline then online" 2 n;
  let t1, eff1 = Intercept.resolved ~seq:0 (Resolve.Taxon digitalis_taxon) t in
  Alcotest.(check intercept_status)
    "resolved with seq 0: still Resolving" Intercept.Resolving
    (Intercept.status t1);
  check_intercept_effect "resolved with seq 0: No_effect" "No_effect" eff1;
  let t2, _ =
    Intercept.resolved ~seq:0
      (Resolve.Unresolved {query = "q"; why = Resolve.Unavailable "late"})
      t
  in
  Alcotest.(check intercept_status)
    "a late Unavailable with seq 0: still Resolving" Intercept.Resolving
    (Intercept.status t2);
  let _, eff3 = Intercept.resolved ~seq:n (Resolve.Taxon digitalis_taxon) t in
  check_intercept_effect "resolved with the current seq: Name"
    (Printf.sprintf "Name {seq = %d; taxon = %d}" n digitalis_taxon.key)
    eff3;
  let t4 = Intercept.named ~seq:0 (candidate_of digitalis_taxon) t in
  Alcotest.(check intercept_status)
    "named with seq 0: still Resolving" Intercept.Resolving
    (Intercept.status t4);
  let t5 = Intercept.named ~seq:n (candidate_of digitalis_taxon) t in
  Alcotest.(check intercept_status)
    "named with the current seq: Found"
    (Intercept.Found {candidate = candidate_of digitalis_taxon; existing = None})
    (Intercept.status t5)

let intercept_resolved_while_found_unchanged () =
  let f = found_state () in
  let t, eff = Intercept.resolved ~seq:0 (Resolve.Taxon digitalis_taxon) f in
  Alcotest.(check bool)
    "unchanged" true
    (Intercept.equal_status (Intercept.status f) (Intercept.status t));
  check_intercept_effect "No_effect" "No_effect" eff

let intercept_network_offline_drops_in_flight () =
  let t0 = resolving_state () in
  let off, eff = Intercept.network ~online:false t0 in
  Alcotest.(check intercept_status)
    "Offline" Intercept.Offline (Intercept.status off);
  check_intercept_effect "No_effect" "No_effect" eff;
  Alcotest.(check int) "seq bumped" (Intercept.seq t0 + 1) (Intercept.seq off)

let intercept_network_offline_from_failed () =
  let f = failed_state () in
  let off, eff = Intercept.network ~online:false f in
  Alcotest.(check intercept_status)
    "Offline" Intercept.Offline (Intercept.status off);
  check_intercept_effect "No_effect" "No_effect" eff;
  Alcotest.(check int) "seq bumped" (Intercept.seq f + 1) (Intercept.seq off)

let intercept_network_online_from_offline () =
  let off = fst (Intercept.network ~online:false (resolving_state ())) in
  let n = Intercept.seq off in
  let onl, eff = Intercept.network ~online:true off in
  Alcotest.(check intercept_status)
    "Resolving" Intercept.Resolving (Intercept.status onl);
  check_intercept_effect "Resolve {seq = n+1}"
    (Printf.sprintf "Resolve {seq = %d}" (n + 1))
    eff;
  Alcotest.(check int) "seq" (n + 1) (Intercept.seq onl)

let intercept_network_online_unaffected_states () =
  List.iter
    (fun (what, state) ->
      let t, eff = Intercept.network ~online:true state in
      check_intercept_effect (what ^ ": No_effect") "No_effect" eff;
      Alcotest.(check bool)
        (what ^ ": status unchanged")
        true
        (Intercept.equal_status (Intercept.status state) (Intercept.status t));
      Alcotest.(check int)
        (what ^ ": seq unchanged") (Intercept.seq state) (Intercept.seq t))
    [
      ("Found", found_state ());
      ("Search", search_state ());
      ("Resolving", resolving_state ());
      ("Failed", failed_state ());
    ]

let intercept_network_offline_unaffected_states () =
  let offline =
    fst
      (Intercept.init ~online:false ~plants:[]
         "https://www.gbif.org/species/5414995")
  in
  List.iter
    (fun (what, state) ->
      let t, eff = Intercept.network ~online:false state in
      check_intercept_effect (what ^ ": No_effect") "No_effect" eff;
      Alcotest.(check bool)
        (what ^ ": status unchanged")
        true
        (Intercept.equal_status (Intercept.status state) (Intercept.status t));
      Alcotest.(check int)
        (what ^ ": seq unchanged") (Intercept.seq state) (Intercept.seq t))
    [
      ("Found", found_state ());
      ("Search", search_state ());
      ("Offline", offline);
    ]

let intercept_named_outside_resolving_unchanged () =
  List.iter
    (fun (what, state) ->
      let t = Intercept.named ~seq:0 (candidate_of digitalis_taxon) state in
      Alcotest.(check bool)
        (what ^ ": unchanged") true
        (Intercept.equal_status (Intercept.status state) (Intercept.status t)))
    [
      ("Search", search_state ());
      ("Failed", failed_state ());
      ( "Offline",
        fst
          (Intercept.init ~online:false ~plants:[]
             "https://www.gbif.org/species/5414995") );
    ]

let intercept_retry () =
  let f = failed_state () in
  let n = Intercept.seq f in
  let onl, eff = Intercept.retry ~online:true f in
  Alcotest.(check intercept_status)
    "online: Resolving" Intercept.Resolving (Intercept.status onl);
  check_intercept_effect "online: Resolve {seq = n+1}"
    (Printf.sprintf "Resolve {seq = %d}" (n + 1))
    eff;
  Alcotest.(check int) "online: seq + 1" (n + 1) (Intercept.seq onl);
  let off, eff2 = Intercept.retry ~online:false f in
  Alcotest.(check intercept_status)
    "offline: Offline" Intercept.Offline (Intercept.status off);
  check_intercept_effect "offline: No_effect" "No_effect" eff2;
  List.iter
    (fun (what, state) ->
      List.iter
        (fun online ->
          let what = Printf.sprintf "%s, online=%b" what online in
          let t, eff = Intercept.retry ~online state in
          check_intercept_effect (what ^ ": No_effect") "No_effect" eff;
          Alcotest.(check intercept_status)
            (what ^ ": status unchanged")
            (Intercept.status state) (Intercept.status t);
          Alcotest.(check int)
            (what ^ ": seq unchanged") (Intercept.seq state) (Intercept.seq t))
        [true; false])
    [
      ("Resolving", resolving_state ());
      ( "Offline",
        fst
          (Intercept.init ~online:false ~plants:[]
             "https://www.gbif.org/species/5414995") );
      ("Found", found_state ());
      ("Search", search_state ());
    ]

let intercept_search_query () =
  Alcotest.(check string)
    "Found, canonical_name" "Digitalis purpurea"
    (Intercept.search_query (found_state ()));
  let no_canon = {digitalis_taxon with Gbif.Taxon.canonical_name = None} in
  let t0 =
    fst
      (Intercept.init ~online:true ~plants:[]
         "https://www.gbif.org/species/5414995")
  in
  let t1, _ = Intercept.resolved ~seq:0 (Resolve.Taxon no_canon) t0 in
  let found_no_canon = Intercept.named ~seq:0 (candidate_of no_canon) t1 in
  Alcotest.(check string)
    "Found, no canonical: scientific_name" no_canon.scientific_name
    (Intercept.search_query found_no_canon);
  Alcotest.(check string)
    "Search q" "digitale"
    (Intercept.search_query (search_state ()));
  let offline_plantuse =
    fst
      (Intercept.init ~online:false ~plants:[]
         "https://plantuse.plantnet.org/fr/Digitalis_purpurea")
  in
  Alcotest.(check string)
    "Offline on Plantuse: the link's query" "Digitalis purpurea"
    (Intercept.search_query offline_plantuse);
  let offline_gbif =
    fst
      (Intercept.init ~online:false ~plants:[] "https://www.gbif.org/species/5")
  in
  Alcotest.(check string)
    "Offline on Gbif: empty" ""
    (Intercept.search_query offline_gbif)

(* ---------- the card ---------- *)

let intercept_name () =
  Alcotest.(check string)
    "first french" "Digitale pourpre"
    (Intercept.name
       (candidate_of digitalis_taxon ~french:["Digitale pourpre"; "Gantelée"])
       ~existing:None);
  Alcotest.(check string)
    "no french: canonical_name" "Digitalis purpurea"
    (Intercept.name (candidate_of digitalis_taxon) ~existing:None);
  let no_canon = {digitalis_taxon with Gbif.Taxon.canonical_name = None} in
  Alcotest.(check string)
    "no french, no canonical: scientific_name" "Digitalis purpurea L."
    (Intercept.name (candidate_of no_canon) ~existing:None);
  let p = {base_plant with Plant.display_name = "Ma digitale"} in
  Alcotest.(check string)
    "existing plant's display_name" "Ma digitale"
    (Intercept.name (candidate_of digitalis_taxon) ~existing:(Some p))

let intercept_latin () =
  Alcotest.(check string)
    "canonical_name" "Digitalis purpurea"
    (Gbif.Taxon.latin digitalis_taxon);
  let no_canon = {digitalis_taxon with Gbif.Taxon.canonical_name = None} in
  Alcotest.(check string)
    "no canonical: scientific_name" "Digitalis purpurea L."
    (Gbif.Taxon.latin no_canon)

let intercept_meta () =
  Alcotest.(check string)
    "family" "Plantaginaceae · GBIF"
    (Intercept.meta digitalis_taxon);
  let no_family = {digitalis_taxon with Gbif.Taxon.family = None} in
  Alcotest.(check string) "no family" "GBIF" (Intercept.meta no_family)

let intercept_place_line () =
  Alcotest.(check string)
    "Searching" "Position… · maintenant"
    (Intercept.place_line Gps.Searching);
  Alcotest.(check string)
    "Fix" "48.0331, 7.0028 · maintenant"
    (Intercept.place_line
       (Gps.Fix
          {Observation.lat = 48.03314; lon = 7.00276; accuracy_m = Some 8.}));
  Alcotest.(check string)
    "Fix, negative lat, lon near 180" "-0.5000, 180.0000 · maintenant"
    (Intercept.place_line
       (Gps.Fix {Observation.lat = -0.5; lon = 179.99999; accuracy_m = None}));
  Alcotest.(check string)
    "No_fix" "Sans position · maintenant"
    (Intercept.place_line Gps.No_fix)

let intercept_constants () =
  Alcotest.(check int) "recent_count" 6 Intercept.recent_count;
  Alcotest.(check (float 0.)) "session_s" 43_200. Intercept.session_s

(* ---------- recent_tags ---------- *)

let rt_now = utc 2026 11 12 12 0

let utc_s y m d h mi s =
  match Ptime.of_date_time ((y, m, d), ((h, mi, s), 0)) with
  | Some t -> t
  | None -> failwith "bad date"

let mk_tag name : Tag.t =
  {
    id = tag_id ();
    name;
    created_at = rt_now;
    updated_at = rt_now;
    deleted_at = None;
  }

let mk_link ?(deleted_at = None) tag_id plant_id ~at : Tag.Plant_tag.t =
  {
    id = Ids.Plant_tag_id.of_key ~plant:plant_id ~tag:tag_id;
    plant_id;
    tag_id;
    created_at = at;
    updated_at = at;
    deleted_at;
  }

let rt_names got = List.map (fun ((t : Tag.t), _) -> t.name) got
let rt_pairs got = List.map (fun ((t : Tag.t), flag) -> (t.name, flag)) got

let intercept_recent_tags_basic () =
  let a = mk_tag "a" and b = mk_tag "b" and c = mk_tag "c" in
  let p = plant_id () in
  let links =
    [
      mk_link a.id p ~at:(utc 2026 11 12 11 0) (* now - 1h *);
      mk_link b.id p ~at:(utc 2026 11 10 12 0) (* now - 2 days *);
    ]
  in
  let got =
    Intercept.recent_tags ~now:rt_now ~tags:[a; b; c] ~links ~except:[]
  in
  Alcotest.(check (list (pair string bool)))
    "a true, b false, c absent (no link)"
    [("a", true); ("b", false)]
    (rt_pairs got)

let intercept_recent_tags_top_six () =
  let p = plant_id () in
  let tags = List.init 8 (fun i -> mk_tag (Printf.sprintf "t%d" i)) in
  let links =
    List.mapi
      (fun i (t : Tag.t) -> mk_link t.id p ~at:(utc 2026 11 12 (11 - i) 0))
      tags
  in
  let got = Intercept.recent_tags ~now:rt_now ~tags ~links ~except:[] in
  Alcotest.(check int) "exactly 6" 6 (List.length got);
  Alcotest.(check (list string))
    "newest first"
    ["t0"; "t1"; "t2"; "t3"; "t4"; "t5"]
    (rt_names got)

let intercept_recent_tags_newest_deleted_falls_back_to_live () =
  let a = mk_tag "a" in
  let p1 = plant_id () and p2 = plant_id () in
  let newest_deleted =
    mk_link a.id p1 ~at:(utc 2026 11 12 11 0) ~deleted_at:(Some rt_now)
  in
  let older_live = mk_link a.id p2 ~at:(utc 2026 11 9 12 0) in
  let got =
    Intercept.recent_tags ~now:rt_now ~tags:[a]
      ~links:[newest_deleted; older_live]
      ~except:[]
  in
  Alcotest.(check (list (pair string bool)))
    "ordered and flagged by the live (older) link"
    [("a", false)]
    (rt_pairs got)

let intercept_recent_tags_only_deleted_links_not_listed () =
  let a = mk_tag "a" in
  let p = plant_id () in
  let link =
    mk_link a.id p ~at:(utc 2026 11 12 11 0) ~deleted_at:(Some rt_now)
  in
  let got =
    Intercept.recent_tags ~now:rt_now ~tags:[a] ~links:[link] ~except:[]
  in
  Alcotest.(check (list string)) "not listed" [] (rt_names got)

let intercept_recent_tags_deleted_tag_not_listed () =
  let a = mk_tag "a" in
  let deleted_tag = {a with Tag.deleted_at = Some rt_now} in
  let p = plant_id () in
  let link = mk_link deleted_tag.id p ~at:(utc 2026 11 12 11 0) in
  let got =
    Intercept.recent_tags ~now:rt_now ~tags:[deleted_tag] ~links:[link]
      ~except:[]
  in
  Alcotest.(check (list string)) "not listed" [] (rt_names got)

let intercept_recent_tags_except () =
  let a = mk_tag "a" and b = mk_tag "b" in
  let p = plant_id () in
  let links =
    [
      mk_link a.id p ~at:(utc 2026 11 12 11 0);
      mk_link b.id p ~at:(utc 2026 11 12 10 0);
    ]
  in
  let got =
    Intercept.recent_tags ~now:rt_now ~tags:[a; b] ~links ~except:[a.id]
  in
  Alcotest.(check (list string)) "a excluded, b unchanged" ["b"] (rt_names got)

let intercept_recent_tags_tie_by_name () =
  let a = mk_tag "zèbre" and b = mk_tag "arnica" in
  let p1 = plant_id () and p2 = plant_id () in
  let at = utc 2026 11 12 11 0 in
  let links = [mk_link a.id p1 ~at; mk_link b.id p2 ~at] in
  let got = Intercept.recent_tags ~now:rt_now ~tags:[a; b] ~links ~except:[] in
  Alcotest.(check (list string))
    "ordered by name" ["arnica"; "zèbre"] (rt_names got)

let intercept_recent_tags_except_then_six () =
  let p = plant_id () in
  let tags = List.init 8 (fun i -> mk_tag (Printf.sprintf "t%d" i)) in
  let links =
    List.mapi
      (fun i (t : Tag.t) -> mk_link t.id p ~at:(utc 2026 11 12 (11 - i) 0))
      tags
  in
  let t0 = List.hd tags in
  let got = Intercept.recent_tags ~now:rt_now ~tags ~links ~except:[t0.id] in
  Alcotest.(check int) "still 6" 6 (List.length got);
  Alcotest.(check (list string))
    "the 7th moves up"
    ["t1"; "t2"; "t3"; "t4"; "t5"; "t6"]
    (rt_names got)

let intercept_recent_tags_tie_by_id () =
  let a = mk_tag "même" and b = mk_tag "même" in
  let p1 = plant_id () and p2 = plant_id () in
  let at = utc 2026 11 12 11 0 in
  let first, second =
    match Ids.Tag_id.compare a.id b.id < 0 with
    | true -> (a, b)
    | false -> (b, a)
  in
  let links = [mk_link first.id p1 ~at; mk_link second.id p2 ~at] in
  let got =
    Intercept.recent_tags ~now:rt_now ~tags:[second; first] ~links ~except:[]
  in
  Alcotest.(check (list string))
    "ordered by id, whatever the input order"
    [Ids.Tag_id.to_string first.id; Ids.Tag_id.to_string second.id]
    (List.map (fun ((t : Tag.t), _) -> Ids.Tag_id.to_string t.id) got)

let intercept_recent_tags_session_boundary () =
  let p = plant_id () in
  let exactly = mk_tag "exactly"
  and older = mk_tag "older"
  and future = mk_tag "future" in
  let at_exact =
    utc 2026 11 12 0 0
    (* now - 12h exactly *)
  in
  let at_older =
    utc_s 2026 11 11 23 59 59
    (* one second older *)
  in
  let at_future =
    utc 2026 11 12 13 0
    (* after now *)
  in
  let links =
    [
      mk_link exactly.id p ~at:at_exact;
      mk_link older.id p ~at:at_older;
      mk_link future.id p ~at:at_future;
    ]
  in
  let got =
    Intercept.recent_tags ~now:rt_now ~tags:[exactly; older; future] ~links
      ~except:[]
  in
  Alcotest.(check (list (pair string bool)))
    "boundary inclusive (true), one second older (false), after now (true)"
    [("future", true); ("exactly", true); ("older", false)]
    (rt_pairs got)

let intercept_recent_tags_one_tag_several_plants_listed_once () =
  let a = mk_tag "a" in
  let p1 = plant_id () and p2 = plant_id () and p3 = plant_id () in
  let links =
    [
      mk_link a.id p1 ~at:(utc 2026 11 10 0 0);
      mk_link a.id p2 ~at:(utc 2026 11 12 11 0) (* newest *);
      mk_link a.id p3 ~at:(utc 2026 11 1 0 0);
    ]
  in
  let got = Intercept.recent_tags ~now:rt_now ~tags:[a] ~links ~except:[] in
  Alcotest.(check (list (pair string bool)))
    "listed once, flagged by its newest link"
    [("a", true)]
    (rt_pairs got)

(* ---------- observation ---------- *)

let intercept_observation () =
  let id = Ids.Observation_id.fresh () in
  let plant = plant_id () in
  let at = utc 2026 11 12 10 0 in
  let fix : Observation.position =
    {lat = 48.0331; lon = 7.0028; accuracy_m = Some 8.}
  in
  let o = Intercept.observation ~id ~at ~plant (Gps.Fix fix) in
  Alcotest.(check bool) "id" true (Ids.Observation_id.equal o.id id);
  Alcotest.(check (option string))
    "plant_id = Some plant"
    (Some (Plant_id.to_string plant))
    (Option.map Plant_id.to_string o.plant_id);
  Alcotest.(check bool) "at" true (Ptime.equal o.at at);
  Alcotest.(check bool) "created_at = at" true (Ptime.equal o.created_at at);
  Alcotest.(check bool) "updated_at = at" true (Ptime.equal o.updated_at at);
  (match o.position with
  | Some p ->
      Alcotest.(check (float 0.)) "Fix: lat" fix.lat p.lat;
      Alcotest.(check (float 0.)) "Fix: lon" fix.lon p.lon;
      Alcotest.(check (option (float 0.)))
        "Fix: accuracy_m" fix.accuracy_m p.accuracy_m
  | None -> Alcotest.fail "expected Some position for Fix");
  Alcotest.(check (option string)) "place_label" None o.place_label;
  Alcotest.(check bool) "place_derived" true (Option.is_none o.place_derived);
  Alcotest.(check (option string)) "note" None o.note;
  Alcotest.(check bool) "deleted_at" true (Option.is_none o.deleted_at);
  List.iter
    (fun (what, gps) ->
      let o = Intercept.observation ~id ~at ~plant gps in
      Alcotest.(check bool)
        (what ^ ": position = None")
        true
        (Option.is_none o.position))
    [("Searching", Gps.Searching); ("No_fix", Gps.No_fix)]

(* ---------- equal_status ---------- *)

let intercept_equal_status () =
  let p = {base_plant with Plant.display_name = "Ma digitale"} in
  let later = {p with Plant.updated_at = utc 2026 11 12 12 0} in
  let found existing =
    Intercept.Found {candidate = candidate_of digitalis_taxon; existing}
  in
  Alcotest.(check bool)
    "Found = Found" true
    (Intercept.equal_status (found (Some p)) (found (Some p)));
  Alcotest.(check bool)
    "existing updated later: not equal" false
    (Intercept.equal_status (found (Some p)) (found (Some later)));
  Alcotest.(check bool)
    "None vs Some: not equal" false
    (Intercept.equal_status (found None) (found (Some p)));
  Alcotest.(check bool)
    "Failed \"a\" vs Search \"a\": not equal" false
    (Intercept.equal_status (Intercept.Failed "a") (Intercept.Search "a"))

(* ---------- from what arrived to the sheet ---------- *)

let plantnet_share =
  "Digitalis purpurea L. \
   https://identify.plantnet.org/fr/k-world-flora/species/Digitalis%20purpurea%20L./data"

let intercept_chain_resolving () =
  List.iter
    (fun (what, text, header) ->
      let t, eff = Intercept.init ~online:true ~plants:[] text in
      Alcotest.(check intercept_status)
        (what ^ ": Resolving") Intercept.Resolving (Intercept.status t);
      check_intercept_effect
        (what ^ ": Resolve {seq = 0}")
        "Resolve {seq = 0}" eff;
      Alcotest.(check string)
        (what ^ ": header") header
        (Intercept.header (Intercept.link t)))
    [
      ( "Pl@ntNet share",
        Option.get (Intercept.of_share ~title:"" ~texts:[plantnet_share]),
        "lien Pl@ntNet reconnu" );
      ( "gbif.org link",
        Option.get (Intercept.of_url "https://www.gbif.org/species/5414995"),
        "lien GBIF reconnu" );
      ( "Pl@ntUse link",
        Option.get
          (Intercept.of_url
             "https://plantuse.plantnet.org/fr/Digitalis_purpurea"),
        "lien Pl@ntUse reconnu" );
    ]

let intercept_prefill_around_the_link () =
  let status text =
    Intercept.status (fst (Intercept.init ~online:true ~plants:[] text))
  in
  Alcotest.(check intercept_status)
    "a name with an observation link: the name"
    (Intercept.Search "Digitalis purpurea L.")
    (status
       "Digitalis purpurea L. – \
        https://identify.plantnet.org/fr/observations/1012345678");
  Alcotest.(check intercept_status)
    "an observation link alone: empty" (Intercept.Search "")
    (status "https://identify.plantnet.org/fr/observations/1012345678");
  Alcotest.(check intercept_status)
    "a Pl@ntUse page no pattern matches: empty, not the URL"
    (Intercept.Search "")
    (status "https://plantuse.plantnet.org/w/index.php?title=X");
  Alcotest.(check intercept_status)
    "free text around an unknown URL: the text" (Intercept.Search "digitale")
    (status "digitale https://example.org/x");
  let gbif =
    fst
      (Intercept.init ~online:true ~plants:[]
         "Digitale https://www.gbif.org/species/5414995")
  in
  let t, _ = Intercept.resolved ~seq:0 (Resolve.Candidates []) gbif in
  Alcotest.(check intercept_status)
    "Candidates for a gbif link: the words around it"
    (Intercept.Search "Digitale") (Intercept.status t);
  let t, _ =
    Intercept.resolved ~seq:0
      (Resolve.Unresolved {query = ""; why = Resolve.No_species})
      gbif
  in
  Alcotest.(check intercept_status)
    "an empty resolver query: the words around it" (Intercept.Search "Digitale")
    (Intercept.status t);
  Alcotest.(check string)
    "search_query while Resolving: the words around it" "Digitale"
    (Intercept.search_query gbif)

let intercept_cap () =
  Alcotest.(check int) "cap" 4096 Intercept.cap;
  let long = "a" ^ String.concat "" (List.init 3000 (fun _ -> "\xc3\xa9")) in
  match Intercept.of_share ~title:"" ~texts:[long] with
  | None -> Alcotest.fail "expected Some"
  | Some s ->
      Alcotest.(check bool) "at most cap bytes" true (String.length s <= 4096);
      Alcotest.(check bool) "cut at a character" true (String.is_valid_utf_8 s);
      Alcotest.(check int) "as long as a boundary allows" 4095 (String.length s);
      Alcotest.(check (option int))
        "of_url: capped too" (Some 4096)
        (Option.map String.length (Intercept.of_url (String.make 5000 'x')))

let intercept =
  [
    Alcotest.test_case "of_url, of_share" `Quick intercept_of_url_and_share;
    Alcotest.test_case "header: one assertion per Link.t constructor" `Quick
      intercept_header_per_constructor;
    Alcotest.test_case "query: one assertion per Link.t constructor" `Quick
      intercept_query_per_constructor;
    Alcotest.test_case "init: online, offline, Text, Plantnet_observation"
      `Quick intercept_init;
    Alcotest.test_case "resolved: Taxon keeps Resolving, effect Name" `Quick
      intercept_resolved_taxon_is_resolving_with_name_effect;
    Alcotest.test_case "named: no matching plant" `Quick
      intercept_named_no_match;
    Alcotest.test_case "named: matches a live plant by gbif_key" `Quick
      intercept_named_matches_live_plant;
    Alcotest.test_case "named: a soft-deleted plant is ignored" `Quick
      intercept_named_ignores_deleted_plant;
    Alcotest.test_case "named: a synonym taxon matches via its accepted_key"
      `Quick intercept_named_matches_via_synonym_accepted_key;
    Alcotest.test_case
      "resolved: No_species, Observation_link and Unavailable fallbacks" `Quick
      intercept_resolved_fallback_paths;
    Alcotest.test_case "resolved: Candidates [] falls back to Search" `Quick
      intercept_resolved_candidates_falls_back_to_search;
    Alcotest.test_case "resolved, named: a stale seq changes nothing" `Quick
      intercept_stale_seq_ignored;
    Alcotest.test_case "resolved: while Found, unchanged" `Quick
      intercept_resolved_while_found_unchanged;
    Alcotest.test_case "network: offline drops the in-flight request" `Quick
      intercept_network_offline_drops_in_flight;
    Alcotest.test_case "network: offline from Failed" `Quick
      intercept_network_offline_from_failed;
    Alcotest.test_case "network: online from Offline retries at once" `Quick
      intercept_network_online_from_offline;
    Alcotest.test_case
      "network: online while Found, Search, Resolving or Failed: unaffected"
      `Quick intercept_network_online_unaffected_states;
    Alcotest.test_case
      "network: offline while Found, Search or Offline: unaffected" `Quick
      intercept_network_offline_unaffected_states;
    Alcotest.test_case
      "named: while Search, Failed or Offline (seq 0), unchanged" `Quick
      intercept_named_outside_resolving_unchanged;
    Alcotest.test_case "retry: online, offline, and every other status" `Quick
      intercept_retry;
    Alcotest.test_case
      "search_query: Found (canonical or scientific), Search, Offline" `Quick
      intercept_search_query;
    Alcotest.test_case "name: first french, else canonical, else existing"
      `Quick intercept_name;
    Alcotest.test_case "Taxon.latin: canonical, else scientific" `Quick
      intercept_latin;
    Alcotest.test_case "meta: family · GBIF, or GBIF alone" `Quick
      intercept_meta;
    Alcotest.test_case "place_line: Searching, Fix, No_fix" `Quick
      intercept_place_line;
    Alcotest.test_case "recent_count and session_s" `Quick intercept_constants;
    Alcotest.test_case "recent_tags: live links, flagged by recency" `Quick
      intercept_recent_tags_basic;
    Alcotest.test_case "recent_tags: at most 6, newest first" `Quick
      intercept_recent_tags_top_six;
    Alcotest.test_case
      "recent_tags: a deleted newest link falls back to an older live one"
      `Quick intercept_recent_tags_newest_deleted_falls_back_to_live;
    Alcotest.test_case
      "recent_tags: a tag whose links are all deleted is not listed" `Quick
      intercept_recent_tags_only_deleted_links_not_listed;
    Alcotest.test_case "recent_tags: a deleted tag is never listed" `Quick
      intercept_recent_tags_deleted_tag_not_listed;
    Alcotest.test_case "recent_tags: except removes a tag" `Quick
      intercept_recent_tags_except;
    Alcotest.test_case "recent_tags: a tie on created_at orders by name" `Quick
      intercept_recent_tags_tie_by_name;
    Alcotest.test_case "recent_tags: except applies before the 6 are taken"
      `Quick intercept_recent_tags_except_then_six;
    Alcotest.test_case "recent_tags: a tie on created_at and name orders by id"
      `Quick intercept_recent_tags_tie_by_id;
    Alcotest.test_case "recent_tags: the session_s boundary" `Quick
      intercept_recent_tags_session_boundary;
    Alcotest.test_case
      "recent_tags: one tag on several plants is listed once, by its newest"
      `Quick intercept_recent_tags_one_tag_several_plants_listed_once;
    Alcotest.test_case "observation: Fix, Searching, No_fix" `Quick
      intercept_observation;
    Alcotest.test_case "equal_status: existing, constructors" `Quick
      intercept_equal_status;
    Alcotest.test_case "of_share / of_url → init: the three Done links" `Quick
      intercept_chain_resolving;
    Alcotest.test_case "init, resolved: 4i gets the words around the link"
      `Quick intercept_prefill_around_the_link;
    Alcotest.test_case "of_share, of_url: capped at a UTF-8 boundary" `Quick
      intercept_cap;
  ]
