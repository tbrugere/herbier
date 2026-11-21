module Communes = Herbier_geo.Communes
module Geocode = Herbier_geo.Geocode
module Place_name = Herbier_geo.Place_name
module Places = Herbier_domain.Places
module Observation = Herbier_domain.Observation
module Ids = Herbier_domain.Ids
module Fixture = Herbier_test_support.Fixture

(* ---------- fixture plumbing ---------- *)

let json_fixture name =
  match Geocode.json_of_string (Fixture.read name) with
  | Ok j -> j
  | Error e -> failwith (name ^ ": " ^ Geocode.error_to_string e)

(* ---------- points (same as test_geocode.ml) ---------- *)

let schlucht : Places.point = {lat = 48.0633; lon = 7.0081}
let lausanne : Places.point = {lat = 46.5197; lon = 6.6323}
let kew : Places.point = {lat = 51.4787; lon = -0.2956}
let atlantic : Places.point = {lat = 46.2; lon = -5.0}
let landes : Places.point = {lat = 44.25; lon = -0.85}
let all_points = [schlucht; lausanne; kew; atlantic; landes]

(* ---------- the 90 (Territoire de Belfort) offline pack, for the
   Ign_offline tests ---------- *)

let belfort : Places.point = {lat = 47.6380; lon = 6.8628}

let idx_90 =
  lazy
    (match
       Communes.pack_of_payload
         ~departement:(Option.get (Communes.Code.of_string "90"))
         (json_fixture "geoplateforme_wfs_communes_90.json")
     with
    | Ok p -> Communes.add Communes.empty p
    | Error e ->
        Alcotest.failf "pack_of_payload 90: %s" (Geocode.error_to_string e))

(* ---------- recorded requests, as test_geocode.ml's ---------- *)

let recorded_requests =
  [
    ("photon_reverse_schlucht.json", Geocode.photon_reverse schlucht);
    ("photon_reverse_lausanne.json", Geocode.photon_reverse lausanne);
    ("photon_reverse_kew.json", Geocode.photon_reverse kew);
    ("photon_reverse_atlantic.json", Geocode.photon_reverse atlantic);
    ( "geoplateforme_lieu_dit_schlucht.json",
      Geocode.geoplateforme_lieu_dit schlucht );
    ( "geoplateforme_commune_schlucht.json",
      Geocode.geoplateforme_commune schlucht );
    ("geoplateforme_lieu_dit_landes.json", Geocode.geoplateforme_lieu_dit landes);
    ("geoplateforme_commune_landes.json", Geocode.geoplateforme_commune landes);
    ( "geoplateforme_lieu_dit_lausanne.json",
      Geocode.geoplateforme_lieu_dit lausanne );
    ( "geoplateforme_commune_lausanne.json",
      Geocode.geoplateforme_commune lausanne );
    ( "geoplateforme_lieu_dit_atlantic.json",
      Geocode.geoplateforme_lieu_dit atlantic );
    ( "geoplateforme_commune_atlantic.json",
      Geocode.geoplateforme_commune atlantic );
    ( "geoplateforme_commune_figeac.json",
      Geocode.geoplateforme_commune {lat = 44.602; lon = 2.03} );
    ( "geoplateforme_lieu_dit_figeac.json",
      Geocode.geoplateforme_lieu_dit {lat = 44.602; lon = 2.03} );
    ( "geoplateforme_commune_pelegri.json",
      Geocode.geoplateforme_commune {lat = 44.6300; lon = 1.9835} );
    ( "geoplateforme_lieu_dit_pelegri.json",
      Geocode.geoplateforme_lieu_dit {lat = 44.6300; lon = 1.9835} );
  ]

let request_line (r : Geocode.request) =
  Geocode.provider_to_string r.provider ^ " " ^ r.url

let answer_from_fixtures (req : Geocode.request) =
  match
    List.find_opt
      (fun (_, (r : Geocode.request)) -> String.equal r.url req.url)
      recorded_requests
  with
  | Some (file, _) -> json_fixture file
  | None -> Alcotest.failf "no recorded fixture matches url %s" req.url

(* The result and every request a program issued, as test_geocode.ml's
   [run_program]: generic over the program's result type. *)
let run_program ~answer program =
  let rec step acc = function
    | Geocode.Done result -> (result, List.rev acc)
    | Geocode.Get (req, k) -> step (req :: acc) (k (answer req))
    | Geocode.Try (req, k) -> step (req :: acc) (k (Some (answer req)))
  in
  step [] program

(* ---------- observations ---------- *)

let id_string n = Printf.sprintf "00000000-0000-4000-8000-%012d" n

let obs_id n =
  match Ids.Observation_id.of_string (id_string n) with
  | Some id -> id
  | None -> Alcotest.failf "Observation_id.of_string %S gave None" (id_string n)

let base_time = 1_700_000_000.

let time s =
  match Ptime.of_float_s (base_time +. float_of_int s) with
  | Some t -> t
  | None -> Alcotest.failf "Ptime.of_float_s rejected offset %d" s

(* [obs ?label ?deleted ~id ~at pos]: an observation with id number [id],
   taken [at] seconds after [base_time], at [pos] ([None]: no position). *)
let obs ?label ?(deleted = false) ~id ~at (pos : Places.point option) :
    Observation.t =
  let at = time at in
  {
    Observation.id = obs_id id;
    plant_id = None;
    at;
    position =
      Option.map
        (fun (p : Places.point) ->
          {Observation.lat = p.lat; lon = p.lon; accuracy_m = None})
        pos;
    place_label = label;
    place_derived = None;
    place_detail = None;
    note = None;
    created_at = at;
    updated_at = at;
    deleted_at = (if deleted then Some at else None);
  }

let deg_of_m m = m /. Places.earth_radius_m *. 180. /. Float.pi

let north_of (p : Places.point) m : Places.point =
  {p with lat = p.lat +. deg_of_m m}

let base_point : Places.point = {lat = 45.0; lon = 5.0}

(* A labelled place far (thousands of km) from every fixture point: never
   anyone's "own" place. *)
let far_labelled = obs ~label:"Loin" ~id:900 ~at:0 (Some {lat = 0.; lon = 0.})

(* ---------- testables ---------- *)

let error =
  Alcotest.testable
    (fun f e -> Format.pp_print_string f (Geocode.error_to_string e))
    Geocode.equal_error

let sources =
  Alcotest.testable
    (fun f (s : Place_name.sources) ->
      Format.fprintf f "{ign_offline = %b; ign_online = %b; photon_online = %b}"
        s.ign_offline s.ign_online s.photon_online)
    Place_name.equal_sources

let outcome =
  Alcotest.testable
    (fun f o -> Format.pp_print_string f (Place_name.outcome_to_string o))
    Place_name.equal_outcome

let outcome_result = Alcotest.result outcome error

(* A shorthand for the common case: a name with no detail (an own label, an
   offline commune, or an online source that found none within
   [Geocode.detail_max_m]). *)
let named ?detail name : Place_name.outcome =
  Place_name.Named {Geocode.name; detail}

(* ---------- sources: none, set/enabled, can_search, order, label ---------- *)

let sources_none_defaults () =
  Alcotest.(check bool) "ign_offline" false Place_name.none.ign_offline;
  Alcotest.(check bool) "ign_online" false Place_name.none.ign_online;
  Alcotest.(check bool) "photon_online" false Place_name.none.photon_online;
  Alcotest.(check bool)
    "any_online none" false
    (Place_name.any_online Place_name.none);
  Alcotest.(check bool)
    "any_enabled none" false
    (Place_name.any_enabled Place_name.none);
  Alcotest.(check bool)
    "can_search none" false
    (Place_name.can_search Place_name.none)

let sources_set_enabled_round_trip () =
  List.iter
    (fun (src : Place_name.source) ->
      List.iter
        (fun b ->
          let s = Place_name.set Place_name.none src b in
          Alcotest.(check bool)
            (Printf.sprintf "enabled (set none %s %b) = %b"
               (Place_name.label src) b b)
            b (Place_name.enabled s src))
        [true; false])
    Place_name.order;
  Alcotest.(check sources)
    "setting Ign_online leaves the others at false"
    {ign_offline = false; ign_online = true; photon_online = false}
    (Place_name.set Place_name.none Place_name.Ign_online true);
  Alcotest.(check sources)
    "clearing Photon_online leaves ign_online at true"
    {ign_offline = false; ign_online = true; photon_online = false}
    (Place_name.set
       {ign_offline = false; ign_online = true; photon_online = true}
       Place_name.Photon_online false);
  Alcotest.(check sources)
    "setting Ign_offline leaves the others at false"
    {ign_offline = true; ign_online = false; photon_online = false}
    (Place_name.set Place_name.none Place_name.Ign_offline true)

let sources_combinations : Place_name.sources list =
  [
    Place_name.none;
    {ign_offline = false; ign_online = true; photon_online = false};
    {ign_offline = false; ign_online = false; photon_online = true};
    {ign_offline = false; ign_online = true; photon_online = true};
    {ign_offline = true; ign_online = false; photon_online = false};
    {ign_offline = true; ign_online = true; photon_online = true};
  ]

let sources_can_search_order_and_labels () =
  List.iter
    (fun (s : Place_name.sources) ->
      Alcotest.(check bool)
        "can_search s = s.photon_online" s.photon_online
        (Place_name.can_search s))
    sources_combinations;
  (match Place_name.order with
  | [Place_name.Ign_offline; Place_name.Ign_online; Place_name.Photon_online] ->
      ()
  | _ ->
      Alcotest.fail
        "order is not exactly [Ign_offline; Ign_online; Photon_online]");
  Alcotest.(check string)
    "label Ign_offline" "IGN hors-ligne"
    (Place_name.label Place_name.Ign_offline);
  Alcotest.(check string)
    "label Ign_online" "IGN en ligne"
    (Place_name.label Place_name.Ign_online);
  Alcotest.(check string)
    "label Photon_online" "Photon en ligne"
    (Place_name.label Place_name.Photon_online);
  Alcotest.(check string)
    "detail Ign_offline"
    "N’envoie aucune position ; nomme d’après les communes des départements \
     téléchargés (IGN, data.geopf.fr)."
    (Place_name.detail Place_name.Ign_offline);
  Alcotest.(check string)
    "detail Ign_online" "Envoie la position à l’IGN (data.geopf.fr), en France."
    (Place_name.detail Place_name.Ign_online);
  Alcotest.(check string)
    "detail Photon_online"
    "Envoie la position à komoot (photon.komoot.io), et la recherche « \
     Chercher un lieu »."
    (Place_name.detail Place_name.Photon_online)

(* The notice prints its items alone, after « Vous pouvez activer, dans
   Réglages › Noms de lieux : »: one colon each, nothing pointing at the page
   around it. *)
let notice_lines () =
  Alcotest.(check (list string))
    "notice lines"
    [
      "IGN hors-ligne : N’envoie aucune position ; nomme d’après les communes \
       des départements téléchargés (IGN, data.geopf.fr).";
      "IGN en ligne : Envoie la position à l’IGN (data.geopf.fr), en France.";
      "Photon en ligne : Envoie la position à komoot (photon.komoot.io), et la \
       recherche « Chercher un lieu ».";
    ]
    (List.map Place_name.notice_line Place_name.order);
  List.iter
    (fun src ->
      let line = Place_name.notice_line src in
      Alcotest.(check int)
        (line ^ ": one colon") 1
        (List.length (String.split_on_char ':' line) - 1);
      Alcotest.(check bool)
        (line ^ ": no « ci-dessous »")
        false
        (List.exists
           (String.equal "ci-dessous")
           (String.split_on_char ' ' line)))
    Place_name.order

let sources_allows_by_provider () =
  List.iter
    (fun (s : Place_name.sources) ->
      Alcotest.(check bool)
        "allows s Geoplateforme = s.ign_online" s.ign_online
        (Place_name.allows s Geocode.Geoplateforme);
      Alcotest.(check bool)
        "allows s Photon = s.photon_online" s.photon_online
        (Place_name.allows s Geocode.Photon))
    sources_combinations

let sources_any_online_ignores_offline_any_enabled_offline_only () =
  let offline_alone =
    {Place_name.ign_offline = true; ign_online = false; photon_online = false}
  in
  Alcotest.(check bool) "any_online" false (Place_name.any_online offline_alone);
  Alcotest.(check bool)
    "any_enabled" true
    (Place_name.any_enabled offline_alone);
  let full : Place_name.sources =
    {ign_offline = true; ign_online = true; photon_online = true}
  in
  Alcotest.(check sources)
    "offline_only keeps only ign_offline" offline_alone
    (Place_name.offline_only full);
  Alcotest.(check sources)
    "offline_only of none stays none" Place_name.none
    (Place_name.offline_only Place_name.none);
  List.iter
    (fun src ->
      Alcotest.(check bool)
        (Place_name.label src ^ ": is_online")
        (match src with
        | Place_name.Ign_offline -> false
        | Place_name.(Ign_online | Photon_online) -> true)
        (Place_name.is_online src))
    Place_name.order

let sources_tests =
  [
    ( "none has both sources off; any_online and can_search are false",
      `Quick,
      sources_none_defaults );
    ( "set/enabled round-trip for each source and value, the other kept",
      `Quick,
      sources_set_enabled_round_trip );
    ( "can_search is photon_online; order, label and detail strings",
      `Quick,
      sources_can_search_order_and_labels );
    ( "the first-opening notice's lines: one colon, no « ci-dessous »",
      `Quick,
      notice_lines );
    ( "allows: Géoplateforme with ign_online, Photon with photon_online",
      `Quick,
      sources_allows_by_provider );
    ( "any_online ignores ign_offline; any_enabled and offline_only",
      `Quick,
      sources_any_online_ignores_offline_any_enabled_offline_only );
  ]

(* ---------- own ---------- *)

let own_labelled_within_is_trimmed () =
  let near = north_of base_point 200. in
  Alcotest.(check bool)
    "about 200 m away, within 500 m" true
    (Places.distance_m base_point near < 500.);
  let plain = obs ~label:"Jardin" ~id:1 ~at:0 (Some near) in
  Alcotest.(check (option string))
    "own" (Some "Jardin")
    (Place_name.own [plain] base_point);
  let padded = obs ~label:"  Jardin de Marie  " ~id:2 ~at:0 (Some near) in
  Alcotest.(check (option string))
    "trimmed" (Some "Jardin de Marie")
    (Place_name.own [padded] base_point)

let own_too_far_is_none () =
  let far = north_of base_point 600. in
  Alcotest.(check bool)
    "600 m is not within 500 m" false
    (Places.within base_point far);
  let o = obs ~label:"Jardin" ~id:1 ~at:0 (Some far) in
  Alcotest.(check (option string)) "own" None (Place_name.own [o] base_point)

let own_boundary_matches_within () =
  let at_500 = north_of base_point 500. in
  let just_outside = north_of base_point 500.01 in
  Alcotest.(check bool)
    "exactly 500 m is within" true
    (Places.within base_point at_500);
  Alcotest.(check bool)
    "500.01 m is not within" false
    (Places.within base_point just_outside);
  let o1 = obs ~label:"Bord" ~id:1 ~at:0 (Some at_500) in
  Alcotest.(check (option string))
    "exactly 500 m: used" (Some "Bord")
    (Place_name.own [o1] base_point);
  let o2 = obs ~label:"Bord" ~id:2 ~at:0 (Some just_outside) in
  Alcotest.(check (option string))
    "500.01 m: not used" None
    (Place_name.own [o2] base_point)

let own_nearest_wins () =
  let near = north_of base_point 100. in
  let far = north_of base_point 400. in
  let o_near = obs ~label:"Proche" ~id:1 ~at:0 (Some near) in
  let o_far = obs ~label:"Lointain" ~id:2 ~at:1 (Some far) in
  Alcotest.(check (option string))
    "nearest wins regardless of list order" (Some "Proche")
    (Place_name.own [o_far; o_near] base_point)

let own_tie_breaks_by_at_then_id () =
  let tie = north_of base_point 200. in
  let earlier = obs ~label:"Premier" ~id:2 ~at:0 (Some tie) in
  let later = obs ~label:"Second" ~id:1 ~at:1 (Some tie) in
  Alcotest.(check (option string))
    "equal distance: the earliest at wins, whatever the id" (Some "Premier")
    (Place_name.own [later; earlier] base_point);
  let small_id = obs ~label:"B" ~id:1 ~at:0 (Some tie) in
  let big_id = obs ~label:"A" ~id:2 ~at:0 (Some tie) in
  Alcotest.(check (option string))
    "equal distance and at: the smaller id wins" (Some "B")
    (Place_name.own [big_id; small_id] base_point)

let own_ignores_unqualified_observations () =
  let near = north_of base_point 200. in
  let deleted = obs ~label:"Suppr" ~deleted:true ~id:1 ~at:0 (Some near) in
  let blank = obs ~label:"   " ~id:2 ~at:0 (Some near) in
  let no_label = obs ~id:3 ~at:0 (Some near) in
  let unpositioned = obs ~label:"Flottant" ~id:4 ~at:0 None in
  let nan_lat =
    obs ~label:"Nan" ~id:5 ~at:0 (Some {near with lat = Float.nan})
  in
  Alcotest.(check (option string))
    "deleted, blank, unlabelled, unpositioned and nan: none qualifies" None
    (Place_name.own
       [deleted; blank; no_label; unpositioned; nan_lat]
       base_point)

let own_point_nonfinite_is_none () =
  let near = north_of base_point 200. in
  let o = obs ~label:"Jardin" ~id:1 ~at:0 (Some near) in
  Alcotest.(check (option string))
    "p with a nan latitude is None" None
    (Place_name.own [o] {base_point with lat = Float.nan})

let own_self_distance_zero () =
  let o = obs ~label:"Ici" ~id:1 ~at:0 (Some base_point) in
  Alcotest.(check (option string))
    "the point's own labelled observation (distance 0) names itself"
    (Some "Ici")
    (Place_name.own [o] base_point)

let own_tests =
  [
    ( "a label within 500 m is used, trimmed",
      `Quick,
      own_labelled_within_is_trimmed );
    ("a label beyond 500 m is not used", `Quick, own_too_far_is_none);
    ( "the boundary matches Places.within exactly (500 m in, 500.01 m out)",
      `Quick,
      own_boundary_matches_within );
    ("the nearest labelled place wins", `Quick, own_nearest_wins);
    ( "an exact distance tie goes to the earliest at, then the smallest id",
      `Quick,
      own_tie_breaks_by_at_then_id );
    ( "deleted, blank-labelled, unlabelled, unpositioned and nan observations \
       are ignored",
      `Quick,
      own_ignores_unqualified_observations );
    ("a non-finite point gives None", `Quick, own_point_nonfinite_is_none);
    ( "the point's own labelled observation names itself (distance 0)",
      `Quick,
      own_self_distance_zero );
  ]

(* ---------- resolve ---------- *)

(* [~communes:Communes.empty] everywhere below: these cases exercise the
   online chain, unaffected by an empty offline index. The
   Ign_offline-specific behaviour has its own group further down, with the
   90 (Territoire de Belfort) index. *)
let no_communes = Communes.empty

let all_on : Place_name.sources =
  {ign_offline = false; ign_online = true; photon_online = true}

let ign_only : Place_name.sources =
  {ign_offline = false; ign_online = true; photon_online = false}

let photon_only : Place_name.sources =
  {ign_offline = false; ign_online = false; photon_online = true}

let resolve_all_off_is_unknown_with_no_request () =
  List.iter
    (fun point ->
      List.iter
        (fun online ->
          let result, reqs =
            run_program ~answer:answer_from_fixtures
              (Place_name.resolve ~sources:Place_name.none ~online ~labelled:[]
                 ~communes:no_communes point)
          in
          Alcotest.(check outcome_result)
            (Printf.sprintf "all off, online = %b" online)
            (Ok Place_name.Unknown) result;
          Alcotest.(check int) "zero requests" 0 (List.length reqs))
        [true; false])
    all_points

let resolve_own_place_online () =
  let jardin = obs ~label:"Jardin" ~id:1 ~at:0 (Some schlucht) in
  let result, reqs =
    run_program ~answer:answer_from_fixtures
      (Place_name.resolve ~sources:all_on ~online:true ~labelled:[jardin]
         ~communes:no_communes schlucht)
  in
  Alcotest.(check outcome_result)
    "own place wins over every online source"
    (Ok (named "Jardin"))
    result;
  Alcotest.(check int) "zero requests" 0 (List.length reqs)

let resolve_own_place_offline () =
  let jardin = obs ~label:"Jardin" ~id:1 ~at:0 (Some schlucht) in
  let result, reqs =
    run_program ~answer:answer_from_fixtures
      (Place_name.resolve ~sources:all_on ~online:false ~labelled:[jardin]
         ~communes:no_communes schlucht)
  in
  Alcotest.(check outcome_result)
    "own place names it, offline"
    (Ok (named "Jardin"))
    result;
  Alcotest.(check int) "zero requests" 0 (List.length reqs)

let resolve_neighbour_names_it_whatever_the_sources () =
  let jardin =
    obs ~label:"Jardin" ~id:1 ~at:0 (Some (north_of schlucht 200.))
  in
  List.iter
    (fun (name, sources) ->
      List.iter
        (fun online ->
          let result, reqs =
            run_program ~answer:answer_from_fixtures
              (Place_name.resolve ~sources ~online ~labelled:[jardin]
                 ~communes:no_communes schlucht)
          in
          Alcotest.(check outcome_result)
            (Printf.sprintf "%s, online = %b: named by the neighbour" name
               online)
            (Ok (named "Jardin"))
            result;
          Alcotest.(check int) "zero requests" 0 (List.length reqs))
        [true; false])
    [
      ("all off", Place_name.none);
      ("all on", all_on);
      ( "offline on too",
        {Place_name.ign_offline = true; ign_online = true; photon_online = true}
      );
    ]

let resolve_deferred_when_a_source_is_on_but_offline () =
  List.iter
    (fun (name, sources) ->
      let result, reqs =
        run_program ~answer:answer_from_fixtures
          (Place_name.resolve ~sources ~online:false ~labelled:[]
             ~communes:no_communes schlucht)
      in
      Alcotest.(check outcome_result)
        (name ^ ": deferred") (Ok Place_name.Deferred) result;
      Alcotest.(check int) (name ^ ": zero requests") 0 (List.length reqs))
    [("IGN alone", ign_only); ("Photon alone", photon_only)]

(* Commune first: IGN asks the commune, then, only when it found one,
   the lieu-dit (kept only as a detail within [Geocode.detail_max_m]). *)
let resolve_ign_only () =
  let check point expected_outcome reqs =
    let result, got_reqs =
      run_program ~answer:answer_from_fixtures
        (Place_name.resolve ~sources:ign_only ~online:true ~labelled:[]
           ~communes:no_communes point)
    in
    Alcotest.(check outcome_result) "result" (Ok expected_outcome) result;
    Alcotest.(check (list string))
      "requests"
      (List.map request_line reqs)
      (List.map request_line got_reqs)
  in
  check schlucht (named "Près du Valtin")
    (* the lieu-dit "le Rain des Aulx" is 464 m away, beyond detail_max_m *)
    [
      Geocode.geoplateforme_commune schlucht;
      Geocode.geoplateforme_lieu_dit schlucht;
    ];
  check landes
    (named "Près de Commensacq")
    [
      Geocode.geoplateforme_commune landes; Geocode.geoplateforme_lieu_dit landes;
    ];
  let result, reqs =
    run_program ~answer:answer_from_fixtures
      (Place_name.resolve ~sources:ign_only ~online:true ~labelled:[]
         ~communes:no_communes kew)
  in
  Alcotest.(check outcome_result)
    "kew: unknown, outside the box" (Ok Place_name.Unknown) result;
  Alcotest.(check int) "kew: zero requests" 0 (List.length reqs);
  let result, reqs =
    run_program ~answer:answer_from_fixtures
      (Place_name.resolve ~sources:ign_only ~online:true ~labelled:[]
         ~communes:no_communes lausanne)
  in
  Alcotest.(check outcome_result)
    "lausanne: unknown" (Ok Place_name.Unknown) result;
  Alcotest.(check (list string))
    "lausanne: the commune alone is empty, no lieu-dit request"
    (List.map request_line [Geocode.geoplateforme_commune lausanne])
    (List.map request_line reqs)

let resolve_photon_only () =
  let result, reqs =
    run_program ~answer:answer_from_fixtures
      (Place_name.resolve ~sources:photon_only ~online:true ~labelled:[]
         ~communes:no_communes kew)
  in
  Alcotest.(check outcome_result)
    "kew: city before district"
    (Ok (named "Près de Londres"))
    result;
  Alcotest.(check (list string))
    "kew: one photon request"
    (List.map request_line [Geocode.photon_reverse kew])
    (List.map request_line reqs);
  let result, reqs =
    run_program ~answer:answer_from_fixtures
      (Place_name.resolve ~sources:photon_only ~online:true ~labelled:[]
         ~communes:no_communes lausanne)
  in
  Alcotest.(check outcome_result)
    "lausanne"
    (Ok (named "Près de Lausanne"))
    result;
  Alcotest.(check (list string))
    "lausanne: one photon request, no geoplateforme"
    (List.map request_line [Geocode.photon_reverse lausanne])
    (List.map request_line reqs);
  let result, reqs =
    run_program ~answer:answer_from_fixtures
      (Place_name.resolve ~sources:photon_only ~online:true ~labelled:[]
         ~communes:no_communes atlantic)
  in
  Alcotest.(check outcome_result)
    "atlantic: unknown" (Ok Place_name.Unknown) result;
  Alcotest.(check int) "atlantic: one request" 1 (List.length reqs);
  let photon_name =
    match
      fst
        (run_program ~answer:answer_from_fixtures
           (Geocode.reverse_photon schlucht))
    with
    | Ok (Some n) -> n
    | Ok None | Error _ -> Alcotest.fail "Photon names Schlucht"
  in
  let result, reqs =
    run_program ~answer:answer_from_fixtures
      (Place_name.resolve ~sources:photon_only ~online:true ~labelled:[]
         ~communes:no_communes schlucht)
  in
  Alcotest.(check outcome_result)
    "schlucht, in France: Photon's name" (Ok (Place_name.Named photon_name))
    result;
  Alcotest.(check (list string))
    "schlucht: one photon request, no geoplateforme"
    (List.map request_line [Geocode.photon_reverse schlucht])
    (List.map request_line reqs)

let resolve_both_on_matches_m543 () =
  let check_case point expected_outcome expected_reqs =
    let result, reqs =
      run_program ~answer:answer_from_fixtures
        (Place_name.resolve ~sources:all_on ~online:true ~labelled:[]
           ~communes:no_communes point)
    in
    Alcotest.(check outcome_result) "result" (Ok expected_outcome) result;
    Alcotest.(check (list string))
      "requests"
      (List.map request_line expected_reqs)
      (List.map request_line reqs)
  in
  (* schlucht, landes: IGN finds a commune (its lieu-dit beyond
     detail_max_m), Photon is never tried (or_else short-circuits on
     Ok (Some _)). *)
  check_case schlucht (named "Près du Valtin")
    [
      Geocode.geoplateforme_commune schlucht;
      Geocode.geoplateforme_lieu_dit schlucht;
    ];
  check_case landes
    (named "Près de Commensacq")
    [
      Geocode.geoplateforme_commune landes; Geocode.geoplateforme_lieu_dit landes;
    ];
  (* lausanne: IGN's commune alone is empty (no lieu-dit request), so
     Photon is tried next and finds it. *)
  check_case lausanne
    (named "Près de Lausanne")
    [Geocode.geoplateforme_commune lausanne; Geocode.photon_reverse lausanne];
  (* kew: outside the IGN box, no IGN request at all; Photon finds the city
     (city before district). *)
  check_case kew (named "Près de Londres") [Geocode.photon_reverse kew];
  (* atlantic: both sources' commune step is empty. *)
  check_case atlantic Place_name.Unknown
    [Geocode.geoplateforme_commune atlantic; Geocode.photon_reverse atlantic]

let resolve_errors_stop_the_chain () =
  let result, reqs =
    run_program
      ~answer:(fun _ -> `Assoc [("features", `Int 3)])
      (Place_name.resolve ~sources:all_on ~online:true ~labelled:[]
         ~communes:no_communes schlucht)
  in
  Alcotest.(check outcome_result)
    "bad payload at the first request"
    (Error (Geocode.Unexpected {path = "/features"; expected = "array"}))
    result;
  Alcotest.(check int) "one request" 1 (List.length reqs);
  (* A bad lieu-dit payload after a good commune: the detail is optional, so
     the commune names the point, with no detail and no Photon request. *)
  let lieu_dit = Geocode.geoplateforme_lieu_dit landes in
  let result, reqs =
    run_program
      ~answer:(fun (req : Geocode.request) ->
        match Geocode.equal_request req lieu_dit with
        | true -> `Assoc [("features", `Int 3)]
        | false -> answer_from_fixtures req)
      (Place_name.resolve ~sources:all_on ~online:true ~labelled:[]
         ~communes:no_communes landes)
  in
  Alcotest.(check outcome_result)
    "bad payload at the lieu-dit step, after a good commune"
    (Ok (named "Près de Commensacq"))
    result;
  Alcotest.(check (list string))
    "two requests, no Photon"
    (List.map request_line [Geocode.geoplateforme_commune landes; lieu_dit])
    (List.map request_line reqs)

let resolve_nonfinite_point_is_unknown () =
  let result, reqs =
    run_program ~answer:answer_from_fixtures
      (Place_name.resolve ~sources:all_on ~online:true ~labelled:[]
         ~communes:no_communes
         {Places.lat = Float.nan; lon = 7.})
  in
  Alcotest.(check outcome_result) "nan latitude" (Ok Place_name.Unknown) result;
  Alcotest.(check int) "zero requests" 0 (List.length reqs)

(* Every request is answered with an empty feature list, which both
   decoders give as [Ok None] (see test_geocode.ml's "no feature gives None"
   cases): the sweep checks the requests, not the name. *)
let no_feature (_ : Geocode.request) : Yojson.Safe.t =
  `Assoc [("features", `List [])]

let resolve_privacy_invariant () =
  let all_sources_combinations =
    [
      Place_name.none;
      ign_only;
      photon_only;
      all_on;
      {Place_name.ign_offline = true; ign_online = false; photon_online = false};
      {Place_name.ign_offline = true; ign_online = true; photon_online = true};
    ]
  in
  List.iter
    (fun (sources : Place_name.sources) ->
      List.iter
        (fun online ->
          List.iter
            (fun point ->
              List.iter
                (fun labelled ->
                  List.iter
                    (fun communes ->
                      let _, reqs =
                        run_program ~answer:no_feature
                          (Place_name.resolve ~sources ~online ~labelled
                             ~communes point)
                      in
                      (match online with
                      | false ->
                          Alcotest.(check int)
                            "offline: no request is ever issued" 0
                            (List.length reqs)
                      | true -> ());
                      (* Schlucht is in France and no own place names it: every
                     enabled online source is asked, since none finds a
                     feature and neither index (empty, or the 90 pack) holds
                     it. *)
                      (match
                         (online, labelled, Places.equal_point point schlucht)
                       with
                      | true, [], true ->
                          let ign (r : Geocode.request) =
                            match r.provider with
                            | Geocode.Geoplateforme -> true
                            | Geocode.Photon -> false
                          in
                          Alcotest.(check bool)
                            "schlucht: Géoplateforme asked iff ign_online"
                            sources.ign_online (List.exists ign reqs);
                          Alcotest.(check bool)
                            "schlucht: Photon asked iff photon_online"
                            sources.photon_online
                            (List.exists (fun r -> not (ign r)) reqs)
                      | _ -> ());
                      List.iter
                        (fun (r : Geocode.request) ->
                          match r.provider with
                          | Geocode.Geoplateforme ->
                              Alcotest.(check bool)
                                "a Geoplateforme request implies ign_online"
                                true sources.ign_online
                          | Geocode.Photon ->
                              Alcotest.(check bool)
                                "a Photon request implies photon_online" true
                                sources.photon_online)
                        reqs)
                    [no_communes; Lazy.force idx_90])
                [[]; [far_labelled]])
            (belfort :: all_points))
        [true; false])
    all_sources_combinations

(* ---------- Ign_offline: the 90 (Territoire de Belfort) pack ---------- *)

let offline_only_src : Place_name.sources =
  {ign_offline = true; ign_online = false; photon_online = false}

let offline_with_photon : Place_name.sources =
  {ign_offline = true; ign_online = false; photon_online = true}

let offline_and_both_online : Place_name.sources =
  {ign_offline = true; ign_online = true; photon_online = true}

let resolve_offline_in_the_pack_names_it_with_no_request () =
  let result, reqs =
    run_program ~answer:answer_from_fixtures
      (Place_name.resolve ~sources:offline_only_src ~online:false ~labelled:[]
         ~communes:(Lazy.force idx_90) belfort)
  in
  Alcotest.(check outcome_result)
    "belfort"
    (Ok (named "Près de Belfort"))
    result;
  Alcotest.(check int) "no request" 0 (List.length reqs)

let resolve_offline_outside_the_pack_is_unknown_whatever_online () =
  List.iter
    (fun online ->
      let result, reqs =
        run_program ~answer:answer_from_fixtures
          (Place_name.resolve ~sources:offline_only_src ~online ~labelled:[]
             ~communes:(Lazy.force idx_90) landes)
      in
      Alcotest.(check outcome_result)
        (Printf.sprintf "landes, online = %b" online)
        (Ok Place_name.Unknown) result;
      Alcotest.(check int) "no request" 0 (List.length reqs))
    [true; false]

let resolve_offline_and_photon_outside_the_pack () =
  let result, reqs =
    run_program ~answer:answer_from_fixtures
      (Place_name.resolve ~sources:offline_with_photon ~online:false
         ~labelled:[] ~communes:(Lazy.force idx_90) kew)
  in
  Alcotest.(check outcome_result)
    "offline, deferred" (Ok Place_name.Deferred) result;
  Alcotest.(check int) "no request offline" 0 (List.length reqs);
  let result, reqs =
    run_program ~answer:answer_from_fixtures
      (Place_name.resolve ~sources:offline_with_photon ~online:true ~labelled:[]
         ~communes:(Lazy.force idx_90) kew)
  in
  Alcotest.(check outcome_result)
    "online: city before district"
    (Ok (named "Près de Londres"))
    result;
  Alcotest.(check (list string))
    "one photon request"
    (List.map request_line [Geocode.photon_reverse kew])
    (List.map request_line reqs)

let resolve_offline_wins_over_online_in_the_pack () =
  let result, reqs =
    run_program ~answer:answer_from_fixtures
      (Place_name.resolve ~sources:offline_and_both_online ~online:true
         ~labelled:[] ~communes:(Lazy.force idx_90) belfort)
  in
  Alcotest.(check outcome_result) "result" (Ok (named "Près de Belfort")) result;
  Alcotest.(check int) "no request: offline first" 0 (List.length reqs)

let resolve_offline_off_ignores_the_pack () =
  let result, reqs =
    run_program ~answer:answer_from_fixtures
      (Place_name.resolve ~sources:Place_name.none ~online:true ~labelled:[]
         ~communes:(Lazy.force idx_90) belfort)
  in
  Alcotest.(check outcome_result) "result" (Ok Place_name.Unknown) result;
  Alcotest.(check int) "no request" 0 (List.length reqs)

let resolve_own_place_wins_over_the_pack () =
  let jardin = obs ~label:"Jardin" ~id:1 ~at:0 (Some (north_of belfort 200.)) in
  let result, reqs =
    run_program ~answer:answer_from_fixtures
      (Place_name.resolve ~sources:offline_and_both_online ~online:true
         ~labelled:[jardin] ~communes:(Lazy.force idx_90) belfort)
  in
  Alcotest.(check outcome_result) "result" (Ok (named "Jardin")) result;
  Alcotest.(check int) "no request" 0 (List.length reqs)

let offline_tests =
  [
    ( "Belfort, in the pack, offline alone: named with no request",
      `Quick,
      resolve_offline_in_the_pack_names_it_with_no_request );
    ( "Landes, outside the pack, nothing else on: Unknown with no request, \
       online or not",
      `Quick,
      resolve_offline_outside_the_pack_is_unknown_whatever_online );
    ( "Kew, outside the pack, Photon also on: deferred offline, one Photon \
       request online",
      `Quick,
      resolve_offline_and_photon_outside_the_pack );
    ( "Belfort, in the pack, every source on: the offline answer wins, zero \
       requests",
      `Quick,
      resolve_offline_wins_over_online_in_the_pack );
    ( "Ign_offline off: the pack is ignored even when it holds the point",
      `Quick,
      resolve_offline_off_ignores_the_pack );
    ( "a labelled place within 500 m wins over the offline pack",
      `Quick,
      resolve_own_place_wins_over_the_pack );
  ]

(* End to end through [Place_name.resolve]: a lieu-dit inside a commune is
   not the name itself, only an optional detail under it, kept only when
   close enough. *)
let figeac : Places.point = {lat = 44.602; lon = 2.03}
let pelegri : Places.point = {lat = 44.6300; lon = 1.9835}

let resolve_figeac_gives_the_commune_with_no_detail () =
  let result, reqs =
    run_program ~answer:answer_from_fixtures
      (Place_name.resolve ~sources:ign_only ~online:true ~labelled:[]
         ~communes:no_communes figeac)
  in
  Alcotest.(check outcome_result)
    "Près de Figeac, no detail (its nearest lieu-dit is 319 m away)"
    (Ok (named "Près de Figeac"))
    result;
  Alcotest.(check (list string))
    "commune then lieu-dit"
    (List.map request_line
       [
         Geocode.geoplateforme_commune figeac;
         Geocode.geoplateforme_lieu_dit figeac;
       ])
    (List.map request_line reqs)

let resolve_pelegri_gives_the_commune_with_the_hamlet_as_detail () =
  let result, reqs =
    run_program ~answer:answer_from_fixtures
      (Place_name.resolve ~sources:ign_only ~online:true ~labelled:[]
         ~communes:no_communes pelegri)
  in
  Alcotest.(check outcome_result)
    "Près de Lissac-et-Mouret, detail Pélégri (66 m)"
    (Ok (named ~detail:"Pélégri" "Près de Lissac-et-Mouret"))
    result;
  Alcotest.(check (list string))
    "commune then lieu-dit"
    (List.map request_line
       [
         Geocode.geoplateforme_commune pelegri;
         Geocode.geoplateforme_lieu_dit pelegri;
       ])
    (List.map request_line reqs)

let outcome_to_string_renders_name_and_detail () =
  Alcotest.(check string)
    "named with a detail" "named Près de Lissac-et-Mouret / Pélégri"
    (Place_name.outcome_to_string
       (named ~detail:"Pélégri" "Près de Lissac-et-Mouret"));
  Alcotest.(check string)
    "named without a detail" "named Près de Figeac"
    (Place_name.outcome_to_string (named "Près de Figeac"));
  Alcotest.(check string)
    "unknown" "unknown"
    (Place_name.outcome_to_string Place_name.Unknown);
  Alcotest.(check string)
    "deferred" "deferred"
    (Place_name.outcome_to_string Place_name.Deferred)

let resolve_tests =
  [
    ( "outcome_to_string: « named <name> / <detail> », unknown, deferred",
      `Quick,
      outcome_to_string_renders_name_and_detail );
    ( "every source off is Unknown, no request, at every point and online value",
      `Quick,
      resolve_all_off_is_unknown_with_no_request );
    ( "Figeac: the commune, its lieu-dit too far for a detail",
      `Quick,
      resolve_figeac_gives_the_commune_with_no_detail );
    ( "Pélégri: the commune, with the nearby hamlet as its detail",
      `Quick,
      resolve_pelegri_gives_the_commune_with_the_hamlet_as_detail );
    ( "an own place wins over every online source",
      `Quick,
      resolve_own_place_online );
    ("an own place names it even offline", `Quick, resolve_own_place_offline);
    ( "a labelled neighbour within 500 m names it, every source off or on, \
       online or not, with no request",
      `Quick,
      resolve_neighbour_names_it_whatever_the_sources );
    ( "a source on but offline, no own place, is Deferred with no request",
      `Quick,
      resolve_deferred_when_a_source_is_on_but_offline );
    ("IGN only: no Photon request in any case", `Quick, resolve_ign_only);
    ( "Photon only: no Géoplateforme request in any case",
      `Quick,
      resolve_photon_only );
    ( "both on: the IGN-then-Photon chain's five cases",
      `Quick,
      resolve_both_on_matches_m543 );
    ( "a commune decode error stops the chain at once; a lieu-dit one keeps \
       the commune",
      `Quick,
      resolve_errors_stop_the_chain );
    ( "a non-finite point is Unknown, no request",
      `Quick,
      resolve_nonfinite_point_is_unknown );
    ( "privacy invariant: a request's provider implies its source is on, and \
       offline issues none, for every sources x online x point x labelled \
       combination",
      `Quick,
      resolve_privacy_invariant );
  ]

let () =
  Alcotest.run "place_name"
    [
      ("sources", sources_tests);
      ("own", own_tests);
      ("resolve", resolve_tests);
      ("Ign_offline", offline_tests);
    ]
