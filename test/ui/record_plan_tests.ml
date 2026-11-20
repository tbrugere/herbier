(* of_choice cases not covered by to_identify_tests' save_* fixtures. *)

module Record_plan = Herbier_ui_model.Record_plan
module Identify = Herbier_ui_model.Identify
module Choice = Identify.Choice
module Gbif = Herbier_refs.Sources.Gbif
module Plantnet = Herbier_identify.Plantnet
module Fixture = Herbier_test_support.Fixture
module Support_text = Herbier_test_support.Text
module Is = Herbier_ui_model.Identify_settings

let utc = Fixtures.utc
let plant_id = Fixtures.plant_id

(* ---------- a pending choice (gbif id present, not yet resolved) ---------- *)

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

(* P4: "Hibiscus spp." (genus-level), gbif null, "Hibiscus commun" first. *)
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
        | To_identify -> Format.pp_print_string f "To_identify")
      ( = )
  in
  let choice =
    Alcotest.testable
      (fun f -> function
        | Record_plan.Target t ->
            Format.fprintf f "Target %a" (Alcotest.pp target) t
        | Linked {name; taxon} ->
            Format.fprintf f "Linked {name = %s; taxon = %d}" name taxon.key)
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
    Alcotest.test_case
      "of_choice: pending (no resolution yet), no owner, a gbif id present -> \
       Linked with Pl@ntNet's own taxon"
      `Quick (fun () ->
        let p1 = Lazy.force p1 in
        let named_plant = plant "Digitale pourpre" [] in
        Alcotest.check choice "Linked {name = Rose de Chine; taxon = p1_taxon}"
          (Record_plan.Linked {name = "Rose de Chine"; taxon = p1_taxon})
          (Record_plan.of_choice ~plants:[named_plant] (Choice.v p1)));
    Alcotest.test_case
      "of_choice: no gbif id, pending, a plant of that name (ASCII case) -> \
       Existing it, as the typed name"
      `Quick (fun () ->
        let p4 = Lazy.force p4 in
        let hibiscus = plant "hibiscus Commun" [] in
        Alcotest.check choice "Existing hibiscus Commun"
          (Record_plan.Target (Existing hibiscus))
          (Record_plan.of_choice
             ~plants:[plant "Digitale pourpre" []; hibiscus]
             (Choice.v p4)));
    Alcotest.test_case
      "of_choice: resolved Unknown, a plant with the proposal's gbif key -> \
       Existing it"
      `Quick (fun () ->
        let p1 = Lazy.force p1 in
        let owner = {(plant "Ma plante" []) with gbif_key = Some 3152559} in
        Alcotest.check choice "Existing Ma plante"
          (Record_plan.Target (Existing owner))
          (Record_plan.of_choice ~plants:[owner]
             (Choice.resolved (Choice.v p1) Choice.Unknown)));
    Alcotest.test_case
      "controls' labels: save_label, shutter_label, flip_label, pending_label"
      `Quick (fun () ->
        Alcotest.(check string)
          "save_label" "Enregistrer" Record_plan.save_label;
        Alcotest.(check string)
          "shutter_label" "Prendre la photo" Record_plan.shutter_label;
        Alcotest.(check string)
          "flip_label" "Changer de caméra" Record_plan.flip_label;
        Alcotest.(check string)
          "pending_label" "Photo en cours" Record_plan.pending_label;
        Alcotest.(check string)
          "cancel_pending_label" "Annuler la photo en cours"
          Record_plan.cancel_pending_label);
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
        check_clean "save_label" Record_plan.save_label;
        check_clean "shutter_label" Record_plan.shutter_label;
        check_clean "flip_label" Record_plan.flip_label;
        check_clean "pending_label" Record_plan.pending_label);
    Alcotest.test_case
      "identify_after_save: on_photo and Ready and To_identify only" `Quick
      (fun () ->
        let key =
          match Is.Key.of_input "abcdefgh" with
          | Some k -> k
          | None -> Alcotest.fail "Key.of_input \"abcdefgh\" should be a key"
        in
        let ready = Is.Ready key in
        Alcotest.(check bool)
          "on_photo, Ready, To_identify -> true" true
          (Record_plan.identify_after_save ~on_photo:true ready To_identify);
        Alcotest.(check bool)
          "no_photo, Ready, To_identify -> false" false
          (Record_plan.identify_after_save ~on_photo:false ready To_identify);
        List.iter
          (fun (name, gate) ->
            Alcotest.(check bool)
              (Printf.sprintf "on_photo, %s, To_identify -> false" name)
              false
              (Record_plan.identify_after_save ~on_photo:true gate To_identify))
          [
            ("Offline", Is.Offline);
            ("No_key", Is.No_key);
            ("Waiting", Is.Waiting);
          ];
        let named_plant = plant "Digitale pourpre" [] in
        Alcotest.(check bool)
          "on_photo, Ready, Existing p -> false (a name was picked)" false
          (Record_plan.identify_after_save ~on_photo:true ready
             (Existing named_plant));
        Alcotest.(check bool)
          "on_photo, Ready, Free \"x\" -> false (a name was typed)" false
          (Record_plan.identify_after_save ~on_photo:true ready (Free "x")));
  ]
