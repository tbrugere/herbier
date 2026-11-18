module Record_plan = Herbier_ui_model.Record_plan
module Identify = Herbier_ui_model.Identify
module Choice = Identify.Choice
module Is = Herbier_ui_model.Identify_settings
module Plantnet = Herbier_identify.Plantnet
module Organ = Herbier_identify.Organ
module Gbif = Herbier_refs.Sources.Gbif
module Decode = Herbier_refs.Decode
module Fixture = Herbier_test_support.Fixture
module Support_text = Herbier_test_support.Text

let utc = Fixtures.utc
let plant_id = Fixtures.plant_id

(* ---------- identification (6a, 6e) helpers ---------- *)

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

(* Choice.plantnet_taxon of P1, as a literal: the expected value (not derived
   from {!Choice.plantnet_taxon}, which Identify_choice_tests checks
   directly). *)
let p1_taxon : Gbif.Taxon.t =
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

let json_of_fixture file =
  match Decode.json_of_string (Fixture.read file) with
  | Ok j -> j
  | Error e -> Alcotest.failf "%s: %s" file (Decode.error_to_string e)

(* The real GBIF species the 5334357 synonym (P1 with that gbif key)
   resolves to, decoded from the recorded payload rather than transcribed by
   hand. *)
let accepted_taxon =
  lazy
    (match
       Gbif.species_of_json (json_of_fixture "gbif_species_2889173.json")
     with
    | Ok t -> t
    | Error e ->
        Alcotest.failf "gbif_species_2889173.json: %s"
          (Decode.error_to_string e))

let ready_key () =
  match Is.Key.of_input "abcdefgh" with
  | Some k -> k
  | None -> Alcotest.fail "Key.of_input \"abcdefgh\" should be a key"

let stub_identified : Herbier_identify.identified =
  {
    answer = {proposals = []; detected = []; flora = None; remaining = None};
    uncertain = false;
  }

let proposal_with_score score : Plantnet.proposal =
  {
    score;
    name = "Sample";
    author = "";
    scientific_name = "Sample";
    family = None;
    common_names = [];
    gbif = None;
    images = [];
  }

let pp_choice_change fmt = function
  | Record_plan.Keep_choice -> Format.pp_print_string fmt "Keep_choice"
  | Record_plan.Clear_choice -> Format.pp_print_string fmt "Clear_choice"
  | Record_plan.Set_choice (p : Plantnet.proposal) ->
      Format.fprintf fmt "Set_choice %s" p.name

let pp_after fmt (a : Record_plan.after) =
  Format.fprintf fmt "{choice = %a; clear_text = %b; retake = %b}"
    pp_choice_change a.choice a.clear_text a.retake

let after_t = Alcotest.testable pp_after Record_plan.equal_after

let record_plan =
  let t0 = utc 2026 6 1 0 0 in
  let plant name aliases : Herbier_domain.Plant.t =
    {
      id = plant_id ();
      display_name = name;
      aliases;
      scientific_name = None;
      authorship = None;
      gbif_key = None;
      notes = "";
      notes_updated_at = None;
      cover_photo_id = None;
      created_at = t0;
      updated_at = t0;
      deleted_at = None;
    }
  in
  let digitale = plant "Digitale pourpre" ["gant de Notre-Dame"]
  and arnica = plant "Arnica" [] in
  let plants = [digitale; arnica] in
  let target =
    Alcotest.testable
      (fun f -> function
        | Record_plan.Existing p ->
            Format.fprintf f "Existing %s" p.display_name
        | Free n -> Format.fprintf f "Free %s" n
        | Linked {name; taxon} ->
            Format.fprintf f "Linked {name = %s; taxon = %d}" name taxon.key
        | To_identify -> Format.pp_print_string f "To_identify")
      ( = )
  in
  let pos lat lon : Herbier_domain.Observation.position =
    {lat; lon; accuracy_m = None}
  in
  let obs plant position : Herbier_domain.Observation.t =
    {
      id = Herbier_domain.Ids.Observation_id.fresh ();
      plant_id = plant;
      at = t0;
      position;
      place_label = None;
      place_derived = None;
      note = None;
      created_at = t0;
      updated_at = t0;
      deleted_at = None;
    }
  in
  [
    Alcotest.test_case "target" `Quick (fun () ->
        let t ?chosen s = Record_plan.target ~plants ~chosen s in
        Alcotest.check target "blank" Record_plan.To_identify (t "  ");
        Alcotest.check target "name, case" (Record_plan.Existing digitale)
          (t " digitale POURPRE ");
        Alcotest.check target "alias" (Record_plan.Existing digitale)
          (t "Gant de notre-dame");
        Alcotest.check target "free" (Record_plan.Free "Lis martagon")
          (t " Lis martagon ");
        let arnica' = plant "Arnica" [] in
        Alcotest.check target "chosen wins over a same-name plant"
          (Record_plan.Existing arnica')
          (t ~chosen:arnica' "arnica");
        Alcotest.check target "case folding is ASCII only"
          (Record_plan.Free "érable")
          (Record_plan.target ~plants:[plant "Érable" []] ~chosen:None "érable");
        Alcotest.check target "chosen then edited"
          (Record_plan.Free "Arnica des")
          (t ~chosen:arnica "Arnica des"));
    Alcotest.test_case "seen here: within 500 m, nearest first, once" `Quick
      (fun () ->
        let here = pos 48.0 7.0 in
        let far = plant "Lis martagon" [] and edge = plant "Gentiane" [] in
        (* 0.001° lat ≈ 111 m *)
        let observations =
          [
            obs (Some arnica.id) (Some (pos 48.004 7.0));
            obs (Some digitale.id) (Some (pos 48.001 7.0));
            obs (Some arnica.id) (Some (pos 48.002 7.0));
            obs (Some digitale.id) (Some (pos 48.1 7.0));
            (* ≈ 511 m: outside *)
            obs (Some far.id) (Some (pos 48.0046 7.0));
            (* ≈ 489 m: inside *)
            obs (Some edge.id) (Some (pos 48.0044 7.0));
            obs None (Some (pos 48.0 7.0));
            obs (Some (plant_id ())) (Some (pos 48.0 7.0));
          ]
        in
        Alcotest.(check (list string))
          "names"
          ["Digitale pourpre"; "Arnica"; "Gentiane"]
          (List.map
             (fun (p : Herbier_domain.Plant.t) -> p.display_name)
             (Record_plan.seen_here ~here observations (plants @ [far; edge]))));
    Alcotest.test_case "when and where" `Quick (fun () ->
        let now = utc 2026 11 6 10 0 and fix = Some (pos 1. 2.) in
        let taken = utc 2026 7 1 9 0 and just_now = utc 2026 11 6 9 55 in
        let ww l = Record_plan.when_where ~now ~fix l in
        let position =
          Alcotest.testable
            (fun f (p : Herbier_domain.Observation.position) ->
              Format.fprintf f "%g, %g" p.lat p.lon)
            ( = )
        in
        let when_where =
          Alcotest.(pair (testable Ptime.pp Ptime.equal) (option position))
        in
        Alcotest.check when_where "none" (now, fix) (ww []);
        Alcotest.check when_where "no exif" (now, fix) (ww [(None, None)]);
        Alcotest.check when_where "old exif date, no position: none"
          (taken, None)
          (ww [(Some taken, None)]);
        Alcotest.check when_where "recent exif date, no position: the fix"
          (just_now, fix)
          (ww [(Some just_now, None)]);
        Alcotest.check when_where "exif position only"
          (now, Some (pos 3. 4.))
          (ww [(None, Some (pos 3. 4.))]);
        Alcotest.check when_where "exif both"
          (taken, Some (pos 3. 4.))
          (ww [(Some taken, Some (pos 3. 4.)); (None, None)]);
        Alcotest.check when_where "first photo only" (now, fix)
          (ww [(None, None); (Some taken, Some (pos 3. 4.))]));
    Alcotest.test_case "target with a choice (6e): it wins over the text" `Quick
      (fun () ->
        let p1 = Lazy.force p1 and p4 = Lazy.force p4 in
        let named_plant = plant "Digitale pourpre" [] in
        List.iter
          (fun (text, chosen) ->
            Alcotest.check target
              (Printf.sprintf "a choice wins over the text %S and chosen" text)
              (Record_plan.Linked {name = "Rose de Chine"; taxon = p1_taxon})
              (Record_plan.target ~plants:[named_plant] ~chosen
                 ~choice:(Choice.v p1) text))
          [("", None); ("Digitale pourpre", None); ("", Some named_plant)];
        let owner = {(plant "Ma plante" []) with gbif_key = Some 3152559} in
        Alcotest.check target
          "owned (by gbif key): Existing that plant, no duplicate"
          (Record_plan.Existing owner)
          (Record_plan.target ~plants:[owner] ~chosen:None ~choice:(Choice.v p1)
             "");
        Alcotest.check target
          "resolved Unknown, no owner -> Free (Pl@ntNet's name, a free name)"
          (Record_plan.Free "Rose de Chine")
          (Record_plan.target ~plants:[named_plant] ~chosen:None
             ~choice:(Choice.resolved (Choice.v p1) Choice.Unknown)
             "");
        Alcotest.check target "P4 (no gbif id) -> Free, its first French name"
          (Record_plan.Free "Hibiscus commun")
          (Record_plan.target ~plants:[named_plant] ~chosen:None
             ~choice:(Choice.v p4) "");
        let hibiscus = plant "hibiscus Commun" [] in
        Alcotest.check target
          "P4 again, a plant of that name: Existing, as the typed name"
          (Record_plan.Existing hibiscus)
          (Record_plan.target ~plants:[named_plant; hibiscus] ~chosen:None
             ~choice:(Choice.v p4) "");
        Alcotest.(check (option string))
          "choice_owner: the same plant, for 6e's card" (Some "hibiscus Commun")
          (Option.map
             (fun (p : Herbier_domain.Plant.t) -> p.display_name)
             (Record_plan.choice_owner ~plants:[named_plant; hibiscus]
                (Choice.v p4)));
        Alcotest.(check (option string))
          "choice_owner: a linked new plant is no owner" None
          (Option.map
             (fun (p : Herbier_domain.Plant.t) -> p.display_name)
             (Record_plan.choice_owner ~plants:[named_plant] (Choice.v p1)));
        Alcotest.check target
          "GBIF unavailable, no owner -> Linked with Pl@ntNet's taxon (R12)"
          (Record_plan.Linked {name = "Rose de Chine"; taxon = p1_taxon})
          (Record_plan.target ~plants:[named_plant] ~chosen:None
             ~choice:(Choice.resolved (Choice.v p1) (Choice.Unavailable "x"))
             "");
        Alcotest.check target
          "resolved Unknown, a plant with the proposal's key -> Existing"
          (Record_plan.Existing owner)
          (Record_plan.target ~plants:[owner] ~chosen:None
             ~choice:(Choice.resolved (Choice.v p1) Choice.Unknown)
             "");
        let synonym = {p1 with gbif = Some 5334357} in
        let accepted = Lazy.force accepted_taxon in
        Alcotest.check target
          "a resolved synonym -> Linked with the accepted taxon"
          (Record_plan.Linked {name = "Rose de Chine"; taxon = accepted})
          (Record_plan.target ~plants:[named_plant] ~chosen:None
             ~choice:
               (Choice.resolved (Choice.v synonym) (Choice.Resolved accepted))
             ""));
    Alcotest.test_case "identify_enabled, identify_line, identify_aria (6a)"
      `Quick (fun () ->
        let k = ready_key () in
        Alcotest.(check bool)
          "Ready, a photo -> enabled" true
          (Record_plan.identify_enabled (Is.Ready k) ~photos:1);
        Alcotest.(check bool)
          "Ready, no photo -> disabled" false
          (Record_plan.identify_enabled (Is.Ready k) ~photos:0);
        Alcotest.(check bool)
          "Waiting -> disabled" false
          (Record_plan.identify_enabled Is.Waiting ~photos:1);
        Alcotest.(check bool)
          "No_key -> disabled" false
          (Record_plan.identify_enabled Is.No_key ~photos:1);
        Alcotest.(check bool)
          "Offline -> disabled" false
          (Record_plan.identify_enabled Is.Offline ~photos:1);
        Alcotest.(check (option string))
          "No_key -> Identify_settings.no_key_line" (Some Is.no_key_line)
          (Record_plan.identify_line Is.No_key);
        Alcotest.(check (option string))
          "Offline -> offline_line" (Some Record_plan.offline_line)
          (Record_plan.identify_line Is.Offline);
        Alcotest.(check (option string))
          "Ready -> None" None
          (Record_plan.identify_line (Is.Ready k));
        Alcotest.(check (option string))
          "Waiting -> None" None
          (Record_plan.identify_line Is.Waiting);
        Alcotest.(check string)
          "Ready: identify_label" Record_plan.identify_label
          (Record_plan.identify_aria (Is.Ready k));
        Alcotest.(check string)
          "Offline: the unavailable aria"
          "Identifier avec Pl@ntNet, indisponible hors-ligne"
          (Record_plan.identify_aria Is.Offline);
        Alcotest.(check string)
          "No_key: the missing-key aria"
          "Identifier avec Pl@ntNet, clé API manquante"
          (Record_plan.identify_aria Is.No_key);
        Alcotest.(check string)
          "Waiting: identify_label" Record_plan.identify_label
          (Record_plan.identify_aria Is.Waiting));
    Alcotest.test_case
      "auto_open: armed, on_photo, Ready, the row's first photo, at least one \
       added"
      `Quick (fun () ->
        let k = ready_key () in
        let ao ?(armed = true) ?(on_photo = true) ?(gate = Is.Ready k)
            ?(before = 0) ?(added = 1) () =
          Record_plan.auto_open ~armed ~on_photo gate ~before ~added
        in
        Alcotest.(check bool) "every condition holds" true (ao ());
        Alcotest.(check bool) "not armed" false (ao ~armed:false ());
        Alcotest.(check bool) "on_photo off" false (ao ~on_photo:false ());
        Alcotest.(check bool) "No_key" false (ao ~gate:Is.No_key ());
        Alcotest.(check bool) "Offline" false (ao ~gate:Is.Offline ());
        Alcotest.(check bool) "Waiting" false (ao ~gate:Is.Waiting ());
        Alcotest.(check bool)
          "not the row's first photo" false (ao ~before:1 ());
        Alcotest.(check bool) "none added" false (ao ~added:0 ()));
    Alcotest.test_case
      "reuses: physical equality on photos, structural on organs/flora; a \
       forced answer also answers the ordinary ask"
      `Quick (fun () ->
        let a = ref () and b = ref () in
        let ask photos organs flora no_reject =
          {Record_plan.photos; organs; flora; no_reject}
        in
        let organs = [Organ.Auto; Organ.Given Organ.Flower] in
        let kept = ask [a; b] organs "all" false in
        let reuses = Record_plan.reuses ( == ) ~kept in
        Alcotest.(check bool)
          "same photos, organs, flora, no_reject" true
          (reuses (ask [a; b] organs "all" false));
        Alcotest.(check bool)
          "a different photo" false
          (reuses (ask [a; ref ()] organs "all" false));
        Alcotest.(check bool)
          "an extra photo, the same organs" false
          (reuses (ask [a; b; ref ()] organs "all" false));
        Alcotest.(check bool)
          "an extra organ, the same photos" false
          (reuses (ask [a; b] (organs @ [Organ.Auto]) "all" false));
        Alcotest.(check bool)
          "one organ differs (Auto vs Given Flower)" false
          (reuses
             (ask [a; b]
                [Organ.Given Organ.Flower; Organ.Given Organ.Flower]
                "all" false));
        Alcotest.(check bool)
          "another flora" false
          (reuses (ask [a; b] organs "k-europe" false));
        Alcotest.(check bool)
          "an ordinary answer for a forced ask: asked again" false
          (reuses (ask [a; b] organs "all" true));
        Alcotest.(check bool)
          "a forced answer for the ordinary ask of a reopen: reused" true
          (Record_plan.reuses ( == )
             ~kept:(ask [a; b] organs "all" true)
             (ask [a; b] organs "all" false));
        Alcotest.(check bool)
          "a forced answer for the same forced ask" true
          (Record_plan.reuses ( == )
             ~kept:(ask [a; b] organs "all" true)
             (ask [a; b] organs "all" true));
        Alcotest.(check bool)
          "no photo, no organ, both sides" true
          (Record_plan.reuses ( == ) ~kept:(ask [] [] "all" false)
             (ask [] [] "all" false)));
    Alcotest.test_case
      "keep_answer: a 200 and a 404 only (Key_not_exposed asked again)" `Quick
      (fun () ->
        let check msg expected result =
          Alcotest.(check bool) msg expected (Record_plan.keep_answer result)
        in
        check "Ok _ -> true" true (Ok stub_identified);
        check "Error (Plantnet No_plant) -> true" true
          (Error (Identify.Failure.Plantnet Plantnet.No_plant));
        check "Plantnet Key_not_exposed -> false" false
          (Error (Identify.Failure.Plantnet Plantnet.Key_not_exposed));
        check "Plantnet (Unreachable Timeout) -> false" false
          (Error
             (Identify.Failure.Plantnet (Plantnet.Unreachable Plantnet.Timeout)));
        check "Plantnet (Refused_request 413) -> false" false
          (Error (Identify.Failure.Plantnet (Plantnet.Refused_request 413)));
        check "Plantnet (Malformed \"x\") -> false" false
          (Error (Identify.Failure.Plantnet (Plantnet.Malformed "x")));
        check "Plantnet Quota_used_up -> false" false
          (Error (Identify.Failure.Plantnet Plantnet.Quota_used_up));
        check "Plantnet Key_refused -> false" false
          (Error (Identify.Failure.Plantnet Plantnet.Key_refused));
        check "Plantnet No_key -> false" false
          (Error (Identify.Failure.Plantnet Plantnet.No_key));
        check "Plantnet No_photo -> false" false
          (Error (Identify.Failure.Plantnet Plantnet.No_photo));
        check "Not_sent_offline -> false" false
          (Error Identify.Failure.Not_sent_offline);
        check "Preview_unreadable -> false" false
          (Error Identify.Failure.Preview_unreadable));
    Alcotest.test_case "choice_score, already_line, taking_label texts (6e)"
      `Quick (fun () ->
        Alcotest.(check string)
          "0.82 -> 82 %" "Pl@ntNet 82 %"
          (Record_plan.choice_score (proposal_with_score 0.82));
        Alcotest.(check string)
          "0.44239 -> 44 %" "Pl@ntNet 44 %"
          (Record_plan.choice_score (proposal_with_score 0.44239));
        let owner = plant "Arnica" [] in
        Alcotest.(check string)
          "already_line, exact text"
          (Printf.sprintf
             "Déjà dans ma collection : l'observation s'ajoutera à %s."
             owner.display_name)
          (Record_plan.already_line owner);
        Alcotest.(check string)
          "taking_label (Given Leaf)" "Pl@ntNet · + feuille"
          (Record_plan.taking_label (Organ.Given Organ.Leaf));
        Alcotest.(check string)
          "taking_label Auto" "Pl@ntNet · + photo"
          (Record_plan.taking_label Organ.Auto));
    Alcotest.test_case "after_layer: the five outcomes" `Quick (fun () ->
        let p1 = Lazy.force p1 in
        Alcotest.(check after_t)
          "Left: keep everything"
          {
            Record_plan.choice = Record_plan.Keep_choice;
            clear_text = false;
            retake = false;
          }
          (Record_plan.after_layer Identify.Layer.Left);
        Alcotest.(check after_t)
          "Chosen p: Set_choice p, clear_text"
          {
            Record_plan.choice = Record_plan.Set_choice p1;
            clear_text = true;
            retake = false;
          }
          (Record_plan.after_layer (Identify.Layer.Chosen p1));
        Alcotest.(check after_t)
          "None_matches: Clear_choice, text kept"
          {
            Record_plan.choice = Record_plan.Clear_choice;
            clear_text = false;
            retake = false;
          }
          (Record_plan.after_layer Identify.Layer.None_matches);
        Alcotest.(check after_t)
          "Keep_unnamed: Clear_choice, clear_text"
          {
            Record_plan.choice = Record_plan.Clear_choice;
            clear_text = true;
            retake = false;
          }
          (Record_plan.after_layer Identify.Layer.Keep_unnamed);
        Alcotest.(check after_t)
          "Retake: Clear_choice, photos removed, re-armed"
          {
            Record_plan.choice = Record_plan.Clear_choice;
            clear_text = false;
            retake = true;
          }
          (Record_plan.after_layer Identify.Layer.Retake));
    Alcotest.test_case
      "no text of Record_plan names CORS, an origin, localhost or exposing"
      `Quick (fun () ->
        let forbidden = ["cors"; "origin"; "localhost"; "expos"] in
        let check_clean label text =
          let lower = String.lowercase_ascii text in
          List.iter
            (fun bad ->
              Alcotest.(check bool)
                (Printf.sprintf "%s does not name %s" label bad)
                false
                (Support_text.contains ~sub:bad lower))
            forbidden
        in
        check_clean "offline_line" Record_plan.offline_line;
        let k = ready_key () in
        List.iter
          (fun (name, gate) ->
            (match Record_plan.identify_line gate with
            | Some line ->
                check_clean (Printf.sprintf "identify_line %s" name) line
            | None -> ());
            check_clean
              (Printf.sprintf "identify_aria %s" name)
              (Record_plan.identify_aria gate))
          [
            ("Ready", Is.Ready k);
            ("Waiting", Is.Waiting);
            ("No_key", Is.No_key);
            ("Offline", Is.Offline);
          ];
        check_clean "already_line"
          (Record_plan.already_line (plant "Arnica" []));
        check_clean "taking_label (Given Leaf)"
          (Record_plan.taking_label (Organ.Given Organ.Leaf));
        check_clean "taking_label Auto" (Record_plan.taking_label Organ.Auto);
        check_clean "taking_cancel" Record_plan.taking_cancel;
        check_clean "clear_choice_label" Record_plan.clear_choice_label);
  ]
