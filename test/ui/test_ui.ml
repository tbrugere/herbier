(* List_patch: applying the edits gives the target list, and an unchanged item
   is never touched. Items are (id, value) pairs. *)

let same (a, _) (b, _) = Int.equal a b
let equal (a, x) (b, y) = Int.equal a b && String.equal x y

let apply old edits =
  List.fold_left
    (fun l -> function
      | List_patch.Remove i -> List.filteri (fun j _ -> j <> i) l
      | List_patch.Insert (i, v) ->
          let before = List.filteri (fun j _ -> j < i) l in
          let after = List.filteri (fun j _ -> j >= i) l in
          before @ (v :: after)
      | List_patch.Update (i, v) ->
          List.mapi (fun j x -> match j = i with true -> v | false -> x) l)
    old edits

let item = Alcotest.(pair int string)

let show = function
  | List_patch.Remove i -> Printf.sprintf "R%d" i
  | List_patch.Insert (i, (id, _)) -> Printf.sprintf "I%d:%d" i id
  | List_patch.Update (i, (id, _)) -> Printf.sprintf "U%d:%d" i id

let check name old next expected =
  Alcotest.test_case name `Quick (fun () ->
      let edits = List_patch.diff ~same ~equal old next in
      Alcotest.(check (list item)) "applied" next (apply old edits);
      match expected with
      | None -> ()
      | Some e -> Alcotest.(check (list string)) "edits" e (List.map show edits))

(* Every ordered subset of [1..4] (as old and as next), next with at most one
   value changed: the edits give next, and with both sides in id order no
   [Insert] or [Update] carries an item that is unchanged in old. *)
let exhaustive =
  Alcotest.test_case "exhaustive over [1..4]" `Quick (fun () ->
      let rec subsets = function
        | [] -> [[]]
        | x :: rest ->
            let s = subsets rest in
            s @ List.map (fun l -> x :: l) s
      in
      let rec perms = function
        | [] -> [[]]
        | l ->
            List.concat_map
              (fun x ->
                List.map
                  (fun p -> x :: p)
                  (perms (List.filter (fun y -> not (Int.equal y x)) l)))
              l
      in
      let lists = List.concat_map perms (subsets [1; 2; 3; 4]) in
      let items = List.map (fun i -> (i, string_of_int i)) in
      let variants l =
        items l
        :: List.mapi
             (fun k _ ->
               List.mapi
                 (fun j (i, v) ->
                   match j = k with true -> (i, v ^ "'") | false -> (i, v))
                 (items l))
             l
      in
      let sorted l = List.equal Int.equal l (List.sort Int.compare l) in
      List.iter
        (fun o ->
          let old = items o in
          List.iter
            (fun n ->
              List.iter
                (fun next ->
                  let edits = List_patch.diff ~same ~equal old next in
                  Alcotest.(check (list item)) "applied" next (apply old edits);
                  match sorted o && sorted n with
                  | false -> ()
                  | true ->
                      List.iter
                        (function
                          | List_patch.Insert (_, x) | List_patch.Update (_, x)
                            ->
                              Alcotest.(check bool)
                                "unchanged item untouched" false
                                (List.exists (equal x) old)
                          | List_patch.Remove _ -> ())
                        edits)
                (variants n))
            lists)
        lists)

(* Collection_filter *)

let utc y m d h mi =
  match Ptime.of_date_time ((y, m, d), ((h, mi, 0), 0)) with
  | Some t -> t
  | None -> failwith "bad date"

module Plant_id = Herbier_domain.Ids.Plant_id

let p1 = Plant_id.fresh ()
and p2 = Plant_id.fresh ()
and p3 = Plant_id.fresh ()

let obs plant_id : Herbier_domain.Observation.t =
  let t = Ptime.epoch in
  {
    id = Herbier_domain.Ids.Observation_id.fresh ();
    plant_id;
    at = t;
    position = None;
    place_label = None;
    place_derived = None;
    note = None;
    created_at = t;
    updated_at = t;
    deleted_at = None;
  }

let collection_filter =
  let open Collection_filter in
  let t1 = Herbier_domain.Ids.Tag_id.fresh ()
  and t2 = Herbier_domain.Ids.Tag_id.fresh () in
  let link tag_id plant_id : Herbier_domain.Tag.Plant_tag.t =
    {
      id = Herbier_domain.Ids.Plant_tag_id.of_key ~plant:plant_id ~tag:tag_id;
      plant_id;
      tag_id;
      created_at = Ptime.epoch;
      updated_at = Ptime.epoch;
      deleted_at = None;
    }
  in
  let ids =
    Alcotest.testable
      (Fmt.of_to_string Herbier_domain.Ids.Tag_id.to_string)
      Herbier_domain.Ids.Tag_id.equal
  in
  [
    Alcotest.test_case "tagged: the plants of each selected tag" `Quick
      (fun () ->
        let links = [link t1 p1; link t2 p2; link t1 p3] in
        Alcotest.(check (list (list bool)))
          "t2 then t1"
          [[false; true; false]; [true; false; true]]
          (List.map
             (fun ps ->
               List.map
                 (fun p -> List.exists (Plant_id.equal p) ps)
                 [p1; p2; p3])
             (tagged links [t2; t1]));
        Alcotest.(check int) "none selected" 0 (List.length (tagged links [])));
    Alcotest.test_case "toggle_tag" `Quick (fun () ->
        Alcotest.(check (list ids)) "add" [t2; t1] (toggle_tag t2 [t1]);
        Alcotest.(check (list ids)) "remove" [t1] (toggle_tag t2 [t2; t1]));
    Alcotest.test_case "counts" `Quick (fun () ->
        let c =
          counts [obs (Some p1); obs None; obs (Some p1); obs (Some p2)]
        in
        Alcotest.(check (list int))
          "p1 p2 p3" [2; 1; 0]
          (List.map (count c) [p1; p2; p3]));
    Alcotest.test_case "no observation" `Quick (fun () ->
        Alcotest.(check int) "zero" 0 (count (counts []) p1));
    Alcotest.test_case "tags: none selected keeps all" `Quick (fun () ->
        Alcotest.(check bool) "kept" true (has_all_tags ~tagged:[] p3));
    Alcotest.test_case "tags: one" `Quick (fun () ->
        let tagged = [[p1; p2]] in
        Alcotest.(check (list bool))
          "p1 p2 p3" [true; true; false]
          (List.map (has_all_tags ~tagged) [p1; p2; p3]));
    Alcotest.test_case "tags: all required" `Quick (fun () ->
        let tagged = [[p1; p2]; [p2; p3]] in
        Alcotest.(check (list bool))
          "p1 p2 p3" [false; true; false]
          (List.map (has_all_tags ~tagged) [p1; p2; p3]));
  ]

(* Journal_filter: the year of an observation is its UTC year here. *)

let journal_filter =
  let year_of (o : Herbier_domain.Observation.t) =
    Fr_date.year ~tz_offset_s:0 o.at
  in
  let at y o = {o with Herbier_domain.Observation.at = utc y 6 1 12 0} in
  let o1 = at 2025 (obs (Some p1))
  and o2 = at 2026 (obs (Some p2))
  and o3 = at 2026 (obs None) in
  let all = [o1; o2; o3] in
  let kept ?year ?(to_identify_only = false) ?(tagged = []) () =
    List.map (Journal_filter.keep ~year_of ~year ~to_identify_only ~tagged) all
  in
  let bools = Alcotest.(list bool) in
  [
    Alcotest.test_case "no filter keeps all" `Quick (fun () ->
        Alcotest.check bools "kept" [true; true; true] (kept ()));
    Alcotest.test_case "year" `Quick (fun () ->
        Alcotest.check bools "2026" [false; true; true] (kept ~year:2026 ()));
    Alcotest.test_case "à identifier" `Quick (fun () ->
        Alcotest.check bools "no plant" [false; false; true]
          (kept ~to_identify_only:true ()));
    Alcotest.test_case "tags: all required, no plant left out" `Quick (fun () ->
        Alcotest.check bools "p1 and p2 tagged" [true; true; false]
          (kept ~tagged:[[p1; p2]] ());
        Alcotest.check bools "only p2 has both" [false; true; false]
          (kept ~tagged:[[p1; p2]; [p2]] ()));
    Alcotest.test_case "filters combine" `Quick (fun () ->
        Alcotest.check bools "2026 and tagged" [false; true; false]
          (kept ~year:2026 ~tagged:[[p1; p2]] ()));
    Alcotest.test_case "year chips: newest first, a selected year stays" `Quick
      (fun () ->
        Alcotest.(check (list int))
          "present" [2026; 2025]
          (Journal_filter.year_chips ~year_of ~year:None all);
        Alcotest.(check (list int))
          "selected, none left" [2026; 2025; 2024]
          (Journal_filter.year_chips ~year_of ~year:(Some 2024) all);
        Alcotest.(check (list int))
          "empty" []
          (Journal_filter.year_chips ~year_of ~year:None []));
    Alcotest.test_case "à identifier chip stays while on" `Quick (fun () ->
        let chip = Alcotest.(option int) in
        Alcotest.check chip "count" (Some 1)
          (Journal_filter.to_identify_chip ~to_identify_only:false all);
        Alcotest.check chip "none: no chip" None
          (Journal_filter.to_identify_chip ~to_identify_only:false [o1; o2]);
        Alcotest.check chip "none, filter on" (Some 0)
          (Journal_filter.to_identify_chip ~to_identify_only:true [o1; o2]));
  ]

let fr_text =
  [
    Alcotest.test_case "plural" `Quick (fun () ->
        Alcotest.(check (list string))
          "0 1 2"
          ["0 plante"; "1 plante"; "2 plantes"]
          (List.map (fun n -> Fr_text.plural n "plante" "plantes") [0; 1; 2]));
  ]

(* Snap: where a released sheet settles, over the dev page's points. *)

let snaps = Snap.of_list [72.; 360.; 640.]

let settles name ~at ~speed ~rest_ms expected =
  Alcotest.test_case name `Quick (fun () ->
      Alcotest.(check int)
        "index" expected
        (Snap.release snaps ~at ~speed ~rest_ms))

let raises name l =
  Alcotest.test_case name `Quick (fun () ->
      match Snap.of_list l with
      | (_ : float array) -> Alcotest.fail "accepted"
      | exception Invalid_argument _ -> ())

let snap =
  [
    Alcotest.test_case "one point" `Quick (fun () ->
        Alcotest.(check int) "index" 0 (Snap.nearest [|100.|] 900.));
    Alcotest.test_case "tie takes the lower" `Quick (fun () ->
        Alcotest.(check int) "index" 0 (Snap.nearest snaps 216.));
    Alcotest.test_case "clamp" `Quick (fun () ->
        Alcotest.(check (float 0.)) "low" 72. (Snap.clamp snaps 10.);
        Alcotest.(check (float 0.)) "high" 640. (Snap.clamp snaps 700.);
        Alcotest.(check (float 0.)) "inside" 300. (Snap.clamp snaps 300.));
    settles "slow release between two points" ~at:250. ~speed:0. ~rest_ms:0. 1;
    settles "slow release near the bottom" ~at:200. ~speed:0. ~rest_ms:0. 0;
    settles "flick up one point" ~at:200. ~speed:1. ~rest_ms:10. 1;
    settles "flick down one point" ~at:300. ~speed:(-1.) ~rest_ms:10. 0;
    settles "fast flick passes a point" ~at:100. ~speed:3. ~rest_ms:10. 2;
    settles "flick past the top" ~at:600. ~speed:5. ~rest_ms:10. 2;
    settles "flick past the bottom" ~at:100. ~speed:(-5.) ~rest_ms:10. 0;
    settles "rested flick projects nothing" ~at:200. ~speed:3. ~rest_ms:200. 0;
    raises "no point" [];
    raises "descending" [360.; 72.];
    raises "repeated" [72.; 72.];
  ]

let a = (1, "a")
and b = (2, "b")
and c = (3, "c")
and d = (4, "d")

(* Fr_date *)

let fr_date =
  let str = Alcotest.string in
  [
    Alcotest.test_case "day header" `Quick (fun () ->
        let header = Fr_date.day_header ~this_year:2026 in
        Alcotest.check str "fri" "Ven. 12 juin" (header (2026, 6, 12));
        Alcotest.check str "accent" "Sam. 15 août" (header (2026, 8, 15));
        Alcotest.check str "another year" "Lun. 1 mars 2027"
          (header (2027, 3, 1));
        Alcotest.check str "no such date: no weekday" "30 février"
          (header (2026, 2, 30));
        Alcotest.check str "long, this year too" "Ven. 12 juin 2026"
          (Fr_date.long_day (2026, 6, 12));
        Alcotest.check str "day and time, local" "Sam. 13 juin 2026 · 00:30"
          (Fr_date.day_time ~tz_offset_s:7200 (utc 2026 6 12 22 30)));
    Alcotest.test_case "year at the New Year" `Quick (fun () ->
        let t = utc 2026 12 31 23 30 in
        Alcotest.(check int) "utc" 2026 (Fr_date.year ~tz_offset_s:0 t);
        Alcotest.(check int) "paris" 2027 (Fr_date.year ~tz_offset_s:3600 t));
    Alcotest.test_case "local date, negative offset" `Quick (fun () ->
        Alcotest.(check (triple int int int))
          "new york" (2026, 6, 11)
          (Fr_date.local_date ~tz_offset_s:(-14400) (utc 2026 6 12 2 0)));
    Alcotest.test_case "day month and full date" `Quick (fun () ->
        Alcotest.(check string)
          "1 mars" "1 mars"
          (Fr_date.day_month (2027, 3, 1));
        Alcotest.(check string)
          "full" "12 juin 2026"
          (Fr_date.full_date (2026, 6, 12)));
    Alcotest.test_case "local date crosses midnight" `Quick (fun () ->
        let t = utc 2026 6 11 22 30 in
        Alcotest.(check (triple int int int))
          "utc" (2026, 6, 11)
          (Fr_date.local_date ~tz_offset_s:0 t);
        Alcotest.(check (triple int int int))
          "paris summer" (2026, 6, 12)
          (Fr_date.local_date ~tz_offset_s:7200 t));
    Alcotest.test_case "time" `Quick (fun () ->
        Alcotest.check str "padded" "09:05"
          (Fr_date.time ~tz_offset_s:3600 (utc 2026 1 3 8 5)));
  ]

(* Fr_date.ago: whole days between the instant and [now] (floor). *)

let ago_now = utc 2026 11 12 0 0

let ago =
  let case what expected instant =
    Alcotest.test_case what `Quick (fun () ->
        Alcotest.(check string) what expected (Fr_date.ago ~now:ago_now instant))
  in
  [
    case "0 s: aujourd'hui" "aujourd'hui" ago_now;
    case "23 h: aujourd'hui" "aujourd'hui" (utc 2026 11 11 1 0);
    case "1 day" "il y a 1 j" (utc 2026 11 11 0 0);
    case "13 days: still in days" "il y a 13 j" (utc 2026 10 30 0 0);
    case "14 days: weeks start" "il y a 2 sem." (utc 2026 10 29 0 0);
    case "59 days: still weeks" "il y a 8 sem." (utc 2026 9 14 0 0);
    case "60 days: months start" "il y a 2 mois" (utc 2026 9 13 0 0);
    case "364 days: still months" "il y a 12 mois" (utc 2025 11 13 0 0);
    case "365 days: years start, singular" "il y a 1 an" (utc 2025 11 12 0 0);
    case "800 days: plural ans" "il y a 2 ans" (utc 2024 9 3 0 0);
    case "an instant after now" "aujourd'hui" (utc 2026 11 12 1 0);
    case "days after now" "aujourd'hui" (utc 2026 11 15 0 0);
  ]

(* Plant_link: the plant record after linking to a GBIF taxon. *)

module Plant = Herbier_domain.Plant
module Gbif = Herbier_refs.Sources.Gbif
module Source = Herbier_domain.Reference.Source
module Organ = Herbier_domain.Reference.Organ
module Projection = Herbier_refs.Projection

let base_plant : Plant.t =
  {
    id = Plant_id.fresh ();
    display_name = "Ma plante";
    aliases = ["la mauve du talus"];
    scientific_name = None;
    authorship = None;
    gbif_key = None;
    notes = "vue au bord du chemin";
    notes_updated_at = Some (utc 2026 2 1 0 0);
    cover_photo_id = Some (Herbier_domain.Ids.Photo_id.fresh ());
    created_at = utc 2026 1 1 0 0;
    updated_at = utc 2026 1 1 0 0;
    deleted_at = None;
  }

let digitalis_taxon : Gbif.Taxon.t =
  {
    key = 5414995;
    scientific_name = "Digitalis purpurea L.";
    canonical_name = Some "Digitalis purpurea";
    authorship = Some "L.";
    rank = Some "SPECIES";
    status = Some Gbif.Status.Accepted;
    accepted_key = None;
    family = Some "Plantaginaceae";
    vernacular_name = Some "Foxglove";
  }

let link_at = utc 2026 11 12 10 0

let plant_link =
  [
    Alcotest.test_case "apply: a free-name plant linked to a taxon" `Quick
      (fun () ->
        let p = Plant_link.apply ~at:link_at base_plant digitalis_taxon in
        Alcotest.(check (option int)) "gbif_key" (Some 5414995) p.gbif_key;
        Alcotest.(check (option string))
          "scientific_name (canonical)" (Some "Digitalis purpurea")
          p.scientific_name;
        Alcotest.(check (option string)) "authorship" (Some "L.") p.authorship;
        Alcotest.(check bool)
          "updated_at = at" true
          (Ptime.equal p.updated_at link_at);
        Alcotest.(check string)
          "display_name unchanged" base_plant.display_name p.display_name;
        Alcotest.(check (list string))
          "aliases unchanged" base_plant.aliases p.aliases;
        Alcotest.(check string) "notes unchanged" base_plant.notes p.notes;
        Alcotest.(check bool)
          "notes_updated_at unchanged" true
          (Option.equal Ptime.equal base_plant.notes_updated_at
             p.notes_updated_at);
        Alcotest.(check (option string))
          "cover_photo_id unchanged"
          (Option.map Herbier_domain.Ids.Photo_id.to_string
             base_plant.cover_photo_id)
          (Option.map Herbier_domain.Ids.Photo_id.to_string p.cover_photo_id);
        Alcotest.(check bool)
          "created_at unchanged" true
          (Ptime.equal p.created_at base_plant.created_at));
    Alcotest.test_case "apply: no canonical_name falls back to scientific_name"
      `Quick (fun () ->
        let taxon = {digitalis_taxon with Gbif.Taxon.canonical_name = None} in
        let p = Plant_link.apply ~at:link_at base_plant taxon in
        Alcotest.(check (option string))
          "scientific_name" (Some taxon.scientific_name) p.scientific_name);
    Alcotest.test_case "apply: no authorship replaces an old one with None"
      `Quick (fun () ->
        let taxon = {digitalis_taxon with Gbif.Taxon.authorship = None} in
        let old_plant = {base_plant with Plant.authorship = Some "Old"} in
        let p = Plant_link.apply ~at:link_at old_plant taxon in
        Alcotest.(check (option string)) "authorship" None p.authorship);
    Alcotest.test_case "retires_references" `Quick (fun () ->
        Alcotest.(check bool)
          "no gbif_key: false" false
          (Plant_link.retires_references base_plant digitalis_taxon);
        Alcotest.(check bool)
          "same key: false" false
          (Plant_link.retires_references
             {base_plant with Plant.gbif_key = Some 5414995}
             digitalis_taxon);
        Alcotest.(check bool)
          "other key: true" true
          (Plant_link.retires_references
             {base_plant with Plant.gbif_key = Some 1}
             digitalis_taxon));
    (* apply ?name (free name -> alias), display_name, create. *)
    Alcotest.test_case
      "apply ~name: a free-name plant is renamed, its old name becomes an \
       alias (Done criterion)"
      `Quick (fun () ->
        let free : Plant.t =
          {
            base_plant with
            display_name = "Fleur violette";
            aliases = ["violette"];
          }
        in
        let p =
          Plant_link.apply ~at:link_at ~name:"Digitale pourpre" free
            digitalis_taxon
        in
        Alcotest.(check string) "display_name" "Digitale pourpre" p.display_name;
        Alcotest.(check (list string))
          "aliases: old name prepended, order kept"
          ["Fleur violette"; "violette"]
          p.aliases;
        Alcotest.(check (option int)) "gbif_key" (Some 5414995) p.gbif_key;
        Alcotest.(check (option string))
          "scientific_name" (Some "Digitalis purpurea") p.scientific_name);
    Alcotest.test_case
      "apply ~name equal (trimmed, case-insensitive) to the old name: no alias \
       added, the trimmed spelling is kept"
      `Quick (fun () ->
        let free : Plant.t =
          {
            base_plant with
            display_name = "Fleur Violette";
            aliases = ["violette"];
          }
        in
        let p =
          Plant_link.apply ~at:link_at ~name:" fleur violette " free
            digitalis_taxon
        in
        Alcotest.(check string) "display_name" "fleur violette" p.display_name;
        Alcotest.(check (list string))
          "aliases unchanged" ["violette"] p.aliases);
    Alcotest.test_case
      "apply ~name: the old name already an alias is not duplicated; an alias \
       equal to the new name is removed"
      `Quick (fun () ->
        let free : Plant.t =
          {
            base_plant with
            display_name = "Fleur violette";
            aliases = ["fleur violette"; "violette"];
          }
        in
        let p =
          Plant_link.apply ~at:link_at ~name:"Digitale pourpre" free
            digitalis_taxon
        in
        Alcotest.(check (list string))
          "old name not added twice (already an alias)"
          ["fleur violette"; "violette"]
          p.aliases;
        let free2 : Plant.t =
          {
            base_plant with
            display_name = "Fleur violette";
            aliases = ["digitale pourpre"; "violette"];
          }
        in
        let p2 =
          Plant_link.apply ~at:link_at ~name:"Digitale pourpre" free2
            digitalis_taxon
        in
        Alcotest.(check (list string))
          "an alias equal to the new name is removed, old name prepended"
          ["Fleur violette"; "violette"]
          p2.aliases);
    Alcotest.test_case "apply ~name:\"  \" (blank): name and aliases unchanged"
      `Quick (fun () ->
        let free : Plant.t =
          {
            base_plant with
            display_name = "Fleur violette";
            aliases = ["violette"];
          }
        in
        let p = Plant_link.apply ~at:link_at ~name:"  " free digitalis_taxon in
        Alcotest.(check string) "display_name" "Fleur violette" p.display_name;
        Alcotest.(check (list string)) "aliases" ["violette"] p.aliases);
    Alcotest.test_case
      "apply ~name on an already-linked plant (relink): display name and \
       aliases are untouched"
      `Quick (fun () ->
        let linked : Plant.t =
          {
            base_plant with
            display_name = "Digitalis purpurea";
            aliases = ["violette"];
            scientific_name = Some "Digitalis purpurea L.";
            gbif_key = Some 999;
          }
        in
        let p =
          Plant_link.apply ~at:link_at ~name:"Nouveau nom" linked
            digitalis_taxon
        in
        Alcotest.(check string)
          "display_name unchanged" "Digitalis purpurea" p.display_name;
        Alcotest.(check (list string))
          "aliases unchanged" ["violette"] p.aliases;
        Alcotest.(check (option int))
          "gbif_key updated" (Some 5414995) p.gbif_key);
    Alcotest.test_case
      "display_name: first french, else canonical_name, else scientific_name"
      `Quick (fun () ->
        let cand french taxon : Herbier_refs.Resolve.Candidate.t =
          {taxon; french}
        in
        Alcotest.(check string)
          "first french" "Digitale pourpre"
          (Plant_link.display_name
             (cand ["Digitale pourpre"; "Gantelée"] digitalis_taxon));
        Alcotest.(check string)
          "no french: canonical_name" "Digitalis purpurea"
          (Plant_link.display_name (cand [] digitalis_taxon));
        let no_canonical =
          {digitalis_taxon with Gbif.Taxon.canonical_name = None}
        in
        Alcotest.(check string)
          "no canonical: scientific_name" "Digitalis purpurea L."
          (Plant_link.display_name (cand [] no_canonical)));
    Alcotest.test_case
      "create: a new linked plant, no alias, created_at = updated_at = at"
      `Quick (fun () ->
        let id = Plant_id.fresh () in
        let p =
          Plant_link.create ~id ~at:link_at ~name:"Digitale pourpre"
            digitalis_taxon
        in
        Alcotest.(check bool) "id" true (Plant_id.equal id p.id);
        Alcotest.(check string) "display_name" "Digitale pourpre" p.display_name;
        Alcotest.(check (list string)) "no alias" [] p.aliases;
        Alcotest.(check (option int)) "gbif_key" (Some 5414995) p.gbif_key;
        Alcotest.(check (option string))
          "scientific_name" (Some "Digitalis purpurea") p.scientific_name;
        Alcotest.(check (option string)) "authorship" (Some "L.") p.authorship;
        Alcotest.(check bool)
          "created_at = at" true
          (Ptime.equal p.created_at link_at);
        Alcotest.(check bool)
          "updated_at = at" true
          (Ptime.equal p.updated_at link_at);
        Alcotest.(check bool)
          "deleted_at = None" true
          (Option.is_none p.deleted_at));
  ]

(* Ref_search: 4i's reference search state machine, without timers or
   network. *)

module Resolve = Herbier_refs.Resolve

let cand key : Resolve.Candidate.t =
  {taxon = {digitalis_taxon with key}; french = []}

let status_str = function
  | Ref_search.Blank -> "Blank"
  | Ref_search.Pending -> "Pending"
  | Ref_search.Found cs ->
      Printf.sprintf "Found [%s]"
        (String.concat ", "
           (List.map
              (fun (c : Resolve.Candidate.t) -> string_of_int c.taxon.key)
              cs))
  | Ref_search.Offline -> "Offline"
  | Ref_search.Failed m -> "Failed " ^ m

let status =
  Alcotest.testable
    (fun f s -> Format.pp_print_string f (status_str s))
    Ref_search.equal_status

let effect_str = function
  | Ref_search.No_effect -> "No_effect"
  | Ref_search.Wait {seq; ms} ->
      Printf.sprintf "Wait {seq = %d; ms = %d}" seq ms
  | Ref_search.Fetch {seq; q} -> Printf.sprintf "Fetch {seq = %d; q = %S}" seq q

let check_effect what expected eff =
  Alcotest.(check string) what expected (effect_str eff)

let ref_search_init () =
  (match Ref_search.init ~online:true "digitale" with
  | t, Ref_search.Fetch {seq = 0; q = "digitale"} ->
      Alcotest.(check status) "status" Ref_search.Pending (Ref_search.status t)
  | _, e ->
      Alcotest.failf "expected Fetch {seq=0; q=\"digitale\"}, got %s"
        (effect_str e));
  (match Ref_search.init ~online:false "x" with
  | t, Ref_search.No_effect ->
      Alcotest.(check status) "offline" Ref_search.Offline (Ref_search.status t)
  | _, e -> Alcotest.failf "expected No_effect, got %s" (effect_str e));
  match Ref_search.init ~online:true " " with
  | t, Ref_search.No_effect ->
      Alcotest.(check status) "blank" Ref_search.Blank (Ref_search.status t)
  | _, e -> Alcotest.failf "expected No_effect, got %s" (effect_str e)

let ref_search_debounce_sequence () =
  let t0 = fst (Ref_search.init ~online:true "") in
  let t1, e1 = Ref_search.typed ~online:true "di" t0 in
  let t2, e2 = Ref_search.typed ~online:true "dig" t1 in
  let t3, e3 = Ref_search.typed ~online:true "digi" t2 in
  Alcotest.(check int) "debounce_ms" 300 Ref_search.debounce_ms;
  check_effect "di" "Wait {seq = 1; ms = 300}" e1;
  check_effect "dig" "Wait {seq = 2; ms = 300}" e2;
  check_effect "digi" "Wait {seq = 3; ms = 300}" e3;
  check_effect "elapsed, stale seq 1" "No_effect"
    (snd (Ref_search.elapsed ~online:true ~seq:1 t3));
  check_effect "elapsed, stale seq 2" "No_effect"
    (snd (Ref_search.elapsed ~online:true ~seq:2 t3));
  let t4, e4 = Ref_search.elapsed ~online:true ~seq:3 t3 in
  check_effect "elapsed, current seq" "Fetch {seq = 3; q = \"digi\"}" e4;
  Alcotest.(check status)
    "still Pending" Ref_search.Pending (Ref_search.status t4)

let ref_search_stale_answer_ignored () =
  let t0 = fst (Ref_search.init ~online:true "") in
  let t1, _ = Ref_search.typed ~online:true "di" t0 in
  let t2, _ = Ref_search.typed ~online:true "dig" t1 in
  let t3, _ = Ref_search.typed ~online:true "digi" t2 in
  let stale = Ref_search.answered ~seq:1 (Ok [cand 1]) t3 in
  Alcotest.(check status)
    "an older seq changes nothing" Ref_search.Pending (Ref_search.status stale);
  Alcotest.(check int) "seq unchanged" 3 (Ref_search.seq stale);
  let current = Ref_search.answered ~seq:3 (Ok [cand 1; cand 2]) t3 in
  Alcotest.(check status)
    "the current seq's answer"
    (Ref_search.Found [cand 1; cand 2])
    (Ref_search.status current)

let ref_search_typed_same_text_or_blank () =
  let t0 = fst (Ref_search.init ~online:true "") in
  let t1, _ = Ref_search.typed ~online:true "digi" t0 in
  let same, e = Ref_search.typed ~online:true " digi " t1 in
  check_effect "same text (padded)" "No_effect" e;
  Alcotest.(check status)
    "unchanged" (Ref_search.status t1) (Ref_search.status same);
  Alcotest.(check int) "seq unchanged" (Ref_search.seq t1) (Ref_search.seq same);
  let blank, e2 = Ref_search.typed ~online:true "  " t1 in
  check_effect "blank" "No_effect" e2;
  Alcotest.(check status) "Blank" Ref_search.Blank (Ref_search.status blank);
  Alcotest.(check int)
    "blank bumps seq"
    (Ref_search.seq t1 + 1)
    (Ref_search.seq blank)

let ref_search_answered_unavailable_and_no_species () =
  let t0 = fst (Ref_search.init ~online:true "digi") in
  Alcotest.(check status)
    "Failed" (Ref_search.Failed "m")
    (Ref_search.status
       (Ref_search.answered ~seq:0 (Error (Resolve.Unavailable "m")) t0));
  Alcotest.(check status)
    "No_species is Found []" (Ref_search.Found [])
    (Ref_search.status
       (Ref_search.answered ~seq:0 (Error Resolve.No_species) t0));
  Alcotest.(check status)
    "Observation_link is Found []" (Ref_search.Found [])
    (Ref_search.status
       (Ref_search.answered ~seq:0 (Error Resolve.Observation_link) t0))

let ref_search_network_changes () =
  let t0 = fst (Ref_search.init ~online:true "digi") in
  let offline, e = Ref_search.network ~online:false t0 in
  check_effect "going offline while Pending" "No_effect" e;
  Alcotest.(check status)
    "Offline" Ref_search.Offline
    (Ref_search.status offline);
  Alcotest.(check int)
    "seq bumped (drops the in-flight request)" 1 (Ref_search.seq offline);
  let ignored = Ref_search.answered ~seq:0 (Ok [cand 1]) offline in
  Alcotest.(check status)
    "the in-flight answer is ignored" Ref_search.Offline
    (Ref_search.status ignored);
  let online, e2 = Ref_search.network ~online:true offline in
  check_effect "coming online with a query, at once"
    "Fetch {seq = 2; q = \"digi\"}" e2;
  Alcotest.(check status)
    "Pending" Ref_search.Pending (Ref_search.status online);
  let found = Ref_search.answered ~seq:2 (Ok [cand 1]) online in
  let unaffected, e3 = Ref_search.network ~online:false found in
  check_effect "Found stays shown offline" "No_effect" e3;
  Alcotest.(check status)
    "unchanged"
    (Ref_search.Found [cand 1])
    (Ref_search.status unaffected)

let ref_search_online_while_pending_or_found () =
  let pending = fst (Ref_search.init ~online:true "digi") in
  let t1, e1 = Ref_search.network ~online:true pending in
  check_effect "online while Pending" "No_effect" e1;
  Alcotest.(check status)
    "still Pending" Ref_search.Pending (Ref_search.status t1);
  Alcotest.(check int)
    "seq unchanged while Pending" (Ref_search.seq pending) (Ref_search.seq t1);
  let found = Ref_search.answered ~seq:0 (Ok [cand 1]) pending in
  let t2, e2 = Ref_search.network ~online:true found in
  check_effect "online while Found" "No_effect" e2;
  Alcotest.(check status)
    "still Found"
    (Ref_search.Found [cand 1])
    (Ref_search.status t2);
  Alcotest.(check int)
    "seq unchanged while Found" (Ref_search.seq found) (Ref_search.seq t2)

let ref_search_network_from_failed () =
  let t0 = fst (Ref_search.init ~online:true "digi") in
  let failed =
    Ref_search.answered ~seq:0 (Error (Resolve.Unavailable "m")) t0
  in
  let offline, e = Ref_search.network ~online:false failed in
  check_effect "going offline while Failed" "No_effect" e;
  Alcotest.(check status)
    "Offline" Ref_search.Offline
    (Ref_search.status offline);
  Alcotest.(check int) "seq bumped" 1 (Ref_search.seq offline);
  let online, e2 = Ref_search.network ~online:true failed in
  check_effect "coming online while Failed, at once"
    "Fetch {seq = 1; q = \"digi\"}" e2;
  Alcotest.(check status)
    "Pending" Ref_search.Pending (Ref_search.status online)

let ref_search_blank_ignores_network_and_retry () =
  let t0 = fst (Ref_search.init ~online:true "") in
  let t1, e1 = Ref_search.network ~online:true t0 in
  check_effect "online with a blank query" "No_effect" e1;
  Alcotest.(check status) "Blank" Ref_search.Blank (Ref_search.status t1);
  let t2, e2 = Ref_search.retry ~online:true t0 in
  check_effect "retry with a blank query" "No_effect" e2;
  Alcotest.(check status) "Blank" Ref_search.Blank (Ref_search.status t2);
  Alcotest.(check int) "seq unchanged" 0 (Ref_search.seq t2)

let ref_search_typed_and_elapsed_offline () =
  let t0 = fst (Ref_search.init ~online:true "") in
  let t1, e1 = Ref_search.typed ~online:false "abc" t0 in
  check_effect "typed offline" "No_effect" e1;
  Alcotest.(check status) "Offline" Ref_search.Offline (Ref_search.status t1);
  let t2, e2 = Ref_search.elapsed ~online:false ~seq:(Ref_search.seq t1) t1 in
  check_effect "elapsed offline, current seq" "No_effect" e2;
  Alcotest.(check status) "Offline" Ref_search.Offline (Ref_search.status t2)

let ref_search_retry () =
  let t0 = fst (Ref_search.init ~online:true "digi") in
  let failed =
    Ref_search.answered ~seq:0 (Error (Resolve.Unavailable "m")) t0
  in
  let t1, e1 = Ref_search.retry ~online:true failed in
  check_effect "retry online: Fetch at once" "Fetch {seq = 1; q = \"digi\"}" e1;
  Alcotest.(check status) "Pending" Ref_search.Pending (Ref_search.status t1);
  let t2, e2 = Ref_search.retry ~online:false failed in
  check_effect "retry offline" "No_effect" e2;
  Alcotest.(check status) "Offline" Ref_search.Offline (Ref_search.status t2)

let ref_search =
  [
    Alcotest.test_case "network online while Pending or Found: nothing" `Quick
      ref_search_online_while_pending_or_found;
    Alcotest.test_case "init: prefilled online, offline, blank" `Quick
      ref_search_init;
    Alcotest.test_case
      "typed: debounce sequence, elapsed drops the stale timers" `Quick
      ref_search_debounce_sequence;
    Alcotest.test_case
      "answered: a stale seq is ignored, the current one is not" `Quick
      ref_search_stale_answer_ignored;
    Alcotest.test_case "typed: a padded repeat is a no-op, blank clears" `Quick
      ref_search_typed_same_text_or_blank;
    Alcotest.test_case "answered: Unavailable is Failed, No_species is Found []"
      `Quick ref_search_answered_unavailable_and_no_species;
    Alcotest.test_case
      "network: offline drops the request, online retries at once, Found is \
       unaffected"
      `Quick ref_search_network_changes;
    Alcotest.test_case
      "network: Failed goes Offline (seq bumped) or fetches again at once"
      `Quick ref_search_network_from_failed;
    Alcotest.test_case "network and retry leave a blank query alone" `Quick
      ref_search_blank_ignores_network_and_retry;
    Alcotest.test_case "typed and elapsed stay Offline without a network change"
      `Quick ref_search_typed_and_elapsed_offline;
    Alcotest.test_case "retry: online fetches again, offline stays Offline"
      `Quick ref_search_retry;
  ]

(* Ref_pick: what tapping a reference row does, per entry mode. *)

let plant_with ?(gbif_key = None) ?(deleted_at = None) () : Plant.t =
  {base_plant with id = Plant_id.fresh (); gbif_key; deleted_at}

let action_str = function
  | Ref_pick.Inert -> "Inert"
  | Ref_pick.Open (p : Plant.t) -> "Open " ^ Plant_id.to_string p.id
  | Ref_pick.Attach_to (p : Plant.t) -> "Attach_to " ^ Plant_id.to_string p.id
  | Ref_pick.Create -> "Create"
  | Ref_pick.Link_this -> "Link_this"

let action =
  Alcotest.testable
    (fun f a -> Format.pp_print_string f (action_str a))
    Ref_pick.equal_action

let ref_pick_matching_plant_per_mode () =
  let a = plant_with ~gbif_key:(Some 5414995) () in
  let b = plant_with () in
  Alcotest.(check action)
    "Browse: Open" (Ref_pick.Open a)
    (Ref_pick.action Ref_pick.Browse ~current:None ~plants:[a; b]
       digitalis_taxon);
  Alcotest.(check action)
    "Attach: Attach_to" (Ref_pick.Attach_to a)
    (Ref_pick.action Ref_pick.Attach ~current:None ~plants:[a; b]
       digitalis_taxon);
  Alcotest.(check action)
    "Relink: Link_this" Ref_pick.Link_this
    (Ref_pick.action Ref_pick.Relink ~current:(Some b.id) ~plants:[a; b]
       digitalis_taxon)

let ref_pick_current_is_inert () =
  let a = plant_with ~gbif_key:(Some 5414995) () in
  List.iter
    (fun mode ->
      Alcotest.(check action)
        "Inert" Ref_pick.Inert
        (Ref_pick.action mode ~current:(Some a.id) ~plants:[a] digitalis_taxon))
    [Ref_pick.Browse; Ref_pick.Attach; Ref_pick.Relink]

let ref_pick_no_match () =
  let b = plant_with () in
  Alcotest.(check action)
    "Browse: Create" Ref_pick.Create
    (Ref_pick.action Ref_pick.Browse ~current:None ~plants:[b] digitalis_taxon);
  Alcotest.(check action)
    "Attach: Create" Ref_pick.Create
    (Ref_pick.action Ref_pick.Attach ~current:None ~plants:[b] digitalis_taxon);
  Alcotest.(check action)
    "Relink: Link_this" Ref_pick.Link_this
    (Ref_pick.action Ref_pick.Relink ~current:None ~plants:[b] digitalis_taxon)

let ref_pick_synonym_accepted_key_matches () =
  let a = plant_with ~gbif_key:(Some 5414995) () in
  let synonym =
    {digitalis_taxon with Gbif.Taxon.key = 7971454; accepted_key = Some 5414995}
  in
  Alcotest.(check action)
    "Browse: Open via accepted_key" (Ref_pick.Open a)
    (Ref_pick.action Ref_pick.Browse ~current:None ~plants:[a] synonym)

let ref_pick_deleted_ignored_first_match_wins () =
  let deleted =
    plant_with ~gbif_key:(Some 5414995) ~deleted_at:(Some (utc 2026 1 1 0 0)) ()
  in
  let live = plant_with ~gbif_key:(Some 5414995) () in
  Alcotest.(check action)
    "soft-deleted ignored" (Ref_pick.Open live)
    (Ref_pick.action Ref_pick.Browse ~current:None ~plants:[deleted; live]
       digitalis_taxon);
  let other = plant_with ~gbif_key:(Some 5414995) () in
  Alcotest.(check action)
    "two matches: the first in list order" (Ref_pick.Open live)
    (Ref_pick.action Ref_pick.Browse ~current:None ~plants:[live; other]
       digitalis_taxon)

let ref_pick_other_owner () =
  let a = plant_with ~gbif_key:(Some 5414995) () in
  let b = plant_with ~gbif_key:(Some 5414995) () in
  match
    Ref_pick.other_owner ~current:(Some a.id) ~plants:[a; b] digitalis_taxon
  with
  | Some (p : Plant.t) ->
      Alcotest.(check bool)
        "the other matching plant" true (Plant_id.equal p.id b.id)
  | None -> Alcotest.fail "expected Some"

let ref_pick_other_owner_none () =
  let a = plant_with ~gbif_key:(Some 5414995) () in
  let b = plant_with () in
  Alcotest.(check bool)
    "only the current plant has the species" true
    (Option.is_none
       (Ref_pick.other_owner ~current:(Some a.id) ~plants:[a; b] digitalis_taxon))

let ref_pick =
  [
    Alcotest.test_case
      "action: the matching plant per mode (Open / Attach_to / Link_this)"
      `Quick ref_pick_matching_plant_per_mode;
    Alcotest.test_case "action: current is Inert in every mode" `Quick
      ref_pick_current_is_inert;
    Alcotest.test_case
      "action: no match is Create (Browse / Attach) or Link_this (Relink)"
      `Quick ref_pick_no_match;
    Alcotest.test_case
      "action: a synonym's accepted_key matches the plant's gbif_key" `Quick
      ref_pick_synonym_accepted_key_matches;
    Alcotest.test_case
      "action: a soft-deleted plant is ignored, the first match wins" `Quick
      ref_pick_deleted_ignored_first_match_wins;
    Alcotest.test_case
      "other_owner: the first matching plant that is not current" `Quick
      ref_pick_other_owner;
    Alcotest.test_case "other_owner: None when only the current plant matches"
      `Quick ref_pick_other_owner_none;
  ]

(* Ref_paste: a pasted link -> the plant's id at one source (5a). *)

module Link = Herbier_domain.Link
module Plant_ref = Herbier_domain.Reference.Plant_ref

let ref_paste_str = function
  | Ref_paste.Species k -> Printf.sprintf "Species %d" k
  | Ref_paste.Plant_ref {source; external_id; url} ->
      Printf.sprintf "Plant_ref {%s; %S; %S}" (Source.to_string source)
        external_id url
  | Ref_paste.Not_a_reference -> "Not_a_reference"
  | Ref_paste.Unrecognised -> "Unrecognised"

let paste =
  Alcotest.testable
    (fun f t -> Format.pp_print_string f (ref_paste_str t))
    Ref_paste.equal

let plant_ref ?(plant_id = Plant_id.fresh ()) ~source ~external_id ~url () :
    Plant_ref.t =
  {
    id = Plant_ref.id_of_key ~plant:plant_id ~source;
    plant_id;
    source;
    external_id;
    url;
    created_at = utc 2026 1 1 0 0;
    updated_at = utc 2026 1 1 0 0;
    deleted_at = None;
  }

let ref_paste =
  [
    Alcotest.test_case "a GBIF species link is Species" `Quick (fun () ->
        Alcotest.check paste "species" (Ref_paste.Species 5414995)
          (Ref_paste.of_text "https://www.gbif.org/species/5414995"));
    Alcotest.test_case "a Pl@ntNet species link is a Plant_ref" `Quick
      (fun () ->
        Alcotest.check paste "plantnet"
          (Ref_paste.Plant_ref
             {
               source = Source.Plantnet;
               external_id = "Digitalis purpurea L.";
               url =
                 "https://identify.plantnet.org/k-world-flora/species/Digitalis%20purpurea%20L./data";
             })
          (Ref_paste.of_text
             "https://identify.plantnet.org/fr/k-world-flora/species/Digitalis%20purpurea%20L./data"));
    Alcotest.test_case "a Wikipedia link is a Plant_ref, interwiki external_id"
      `Quick (fun () ->
        Alcotest.check paste "wikipedia"
          (Ref_paste.Plant_ref
             {
               source = Source.Wikipedia;
               external_id = "fr:Digitale pourpre";
               url = "https://fr.wikipedia.org/wiki/Digitale_pourpre";
             })
          (Ref_paste.of_text "https://fr.wikipedia.org/wiki/Digitale_pourpre"));
    Alcotest.test_case "an INPN link is a Plant_ref (Taxref)" `Quick (fun () ->
        Alcotest.check paste "inpn"
          (Ref_paste.Plant_ref
             {
               source = Source.Taxref;
               external_id = "94959";
               url = "https://inpn.mnhn.fr/espece/cd_nom/94959";
             })
          (Ref_paste.of_text "https://inpn.mnhn.fr/espece/cd_nom/94959"));
    Alcotest.test_case "a Tela link drops the -<tab> suffix from the url" `Quick
      (fun () ->
        Alcotest.check paste "tela"
          (Ref_paste.Plant_ref
             {
               source = Source.Tela;
               external_id = "22437";
               url = "https://www.tela-botanica.org/bdtfx-nn-22437";
             })
          (Ref_paste.of_text
             "https://www.tela-botanica.org/bdtfx-nn-22437-synthese"));
    Alcotest.test_case "a POWO link is a Plant_ref, the IPNI lsid kept as is"
      `Quick (fun () ->
        Alcotest.check paste "powo"
          (Ref_paste.Plant_ref
             {
               source = Source.Powo;
               external_id = "urn:lsid:ipni.org:names:802077-1";
               url =
                 "https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:802077-1";
             })
          (Ref_paste.of_text
             "https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:802077-1"));
    Alcotest.test_case "an iNat link is a Plant_ref" `Quick (fun () ->
        Alcotest.check paste "inat"
          (Ref_paste.Plant_ref
             {
               source = Source.Inat;
               external_id = "53983";
               url = "https://www.inaturalist.org/taxa/53983";
             })
          (Ref_paste.of_text
             "https://www.inaturalist.org/taxa/53983-Digitalis-purpurea"));
    Alcotest.test_case "a POWO id other than an IPNI lsid is percent-encoded"
      `Quick (fun () ->
        Alcotest.check paste "powo other"
          (Ref_paste.Plant_ref
             {
               source = Source.Powo;
               external_id = "abc:1";
               url = "https://powo.science.kew.org/taxon/abc%3A1";
             })
          (Ref_paste.of_text "https://powo.science.kew.org/taxon/abc:1"));
    Alcotest.test_case
      "an accented or parenthesised Wikipedia title is decoded in the id" `Quick
      (fun () ->
        List.iter
          (fun (text, external_id) ->
            match Ref_paste.of_text text with
            | Ref_paste.Plant_ref {external_id = got; _} ->
                Alcotest.(check string) text external_id got
            | Ref_paste.(Species _ | Not_a_reference | Unrecognised) ->
                Alcotest.failf "%s: expected a Plant_ref" text)
          [
            ( "https://fr.wikipedia.org/wiki/Digitale_%C3%A0_grandes_fleurs",
              "fr:Digitale à grandes fleurs" );
            ("https://fr.wikipedia.org/wiki/Ail_(plante)", "fr:Ail (plante)");
          ]);
    Alcotest.test_case "a Pl@ntUse link is Not_a_reference" `Quick (fun () ->
        Alcotest.check paste "plantuse" Ref_paste.Not_a_reference
          (Ref_paste.of_text
             "https://plantuse.plantnet.org/fr/Digitalis_purpurea"));
    Alcotest.test_case "a Pl@ntNet observation link is Not_a_reference" `Quick
      (fun () ->
        Alcotest.check paste "plantnet observation" Ref_paste.Not_a_reference
          (Ref_paste.of_text
             "https://identify.plantnet.org/fr/observations/1012345678"));
    Alcotest.test_case "plain text is Unrecognised" `Quick (fun () ->
        Alcotest.check paste "text" Ref_paste.Unrecognised
          (Ref_paste.of_text "digitale pourpre"));
    Alcotest.test_case
      "round trip: Link.classify of the stored url matches the text's \
       classification"
      `Quick (fun () ->
        List.iter
          (fun text ->
            match Ref_paste.of_text text with
            | Ref_paste.Plant_ref {url; _} ->
                Alcotest.(check bool)
                  (text ^ ": classify url = classify text")
                  true
                  (Link.equal (Link.classify url) (Link.classify text))
            | _ -> Alcotest.failf "%s: expected a Plant_ref" text)
          [
            "https://identify.plantnet.org/fr/k-world-flora/species/Digitalis%20purpurea%20L./data";
            "https://fr.wikipedia.org/wiki/Digitale_pourpre";
            "https://fr.wikipedia.org/wiki/Digitale_%C3%A0_grandes_fleurs";
            "https://fr.wikipedia.org/wiki/Ail_(plante)";
            "https://powo.science.kew.org/taxon/abc:1";
            "https://inpn.mnhn.fr/espece/cd_nom/94959";
            "https://www.tela-botanica.org/bdtfx-nn-22437-synthese";
            "https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:802077-1";
            "https://www.inaturalist.org/taxa/53983-Digitalis-purpurea";
          ]);
    Alcotest.test_case
      "a url with a query string and fragment gives the same Plant_ref as the \
       bare url"
      `Quick (fun () ->
        Alcotest.check paste "with query and fragment"
          (Ref_paste.of_text "https://inpn.mnhn.fr/espece/cd_nom/94959")
          (Ref_paste.of_text
             "https://inpn.mnhn.fr/espece/cd_nom/94959?tab=taxo#onglet"));
    Alcotest.test_case "text around the url is still classified" `Quick
      (fun () ->
        Alcotest.check paste "surrounded by text"
          (Ref_paste.of_text "https://inpn.mnhn.fr/espece/cd_nom/94959")
          (Ref_paste.of_text "voir https://inpn.mnhn.fr/espece/cd_nom/94959"));
    Alcotest.test_case "removable: every source but Gbif" `Quick (fun () ->
        Alcotest.(check bool)
          "Gbif: not removable" false
          (Ref_paste.removable
             (plant_ref ~source:Source.Gbif ~external_id:"5414995"
                ~url:(Gbif.species_url 5414995) ()));
        List.iter
          (fun source ->
            Alcotest.(check bool)
              (Source.to_string source ^ ": removable")
              true
              (Ref_paste.removable
                 (plant_ref ~source ~external_id:"x"
                    ~url:"https://example.invalid/x" ())))
          (List.filter
             (fun s -> not (Source.to_string s = Source.to_string Source.Gbif))
             Source.all));
    Alcotest.test_case "label: source name, a middle dot, external_id" `Quick
      (fun () ->
        Alcotest.(check string)
          "label" "GBIF · 5414995"
          (Ref_paste.label
             (plant_ref ~source:Source.Gbif ~external_id:"5414995"
                ~url:(Gbif.species_url 5414995) ()));
        Alcotest.(check string)
          "Wikipédia label" "Wikipédia · fr:Digitale pourpre"
          (Ref_paste.label
             (plant_ref ~source:Source.Wikipedia
                ~external_id:"fr:Digitale pourpre"
                ~url:"https://fr.wikipedia.org/wiki/Digitale_pourpre" ())));
  ]

(* Ref_text: texts of 4f's reference block. *)

let ref_text =
  [
    Alcotest.test_case "source_name for every source" `Quick (fun () ->
        let case expected source =
          Alcotest.(check string)
            (Source.to_string source) expected
            (Ref_text.source_name source)
        in
        case "GBIF" Source.Gbif;
        case "Wikidata" Source.Wikidata;
        case "Wikipédia" Source.Wikipedia;
        case "POWO" Source.Powo;
        case "IPNI" Source.Ipni;
        case "INPN" Source.Taxref;
        case "Tela Botanica" Source.Tela;
        case "EPPO" Source.Eppo;
        case "iNaturalist" Source.Inat;
        case "Pl@ntNet" Source.Plantnet);
    Alcotest.test_case
      "names_source_line: family and sources, no family, neither, family alone"
      `Quick (fun () ->
        Alcotest.(check string)
          "family and sources" "Plantaginaceae · GBIF, Wikidata"
          (Ref_text.names_source_line ~family:(Some "Plantaginaceae")
             [Source.Gbif; Source.Wikidata]);
        Alcotest.(check string)
          "no family" "GBIF, Wikidata"
          (Ref_text.names_source_line ~family:None
             [Source.Gbif; Source.Wikidata]);
        Alcotest.(check string)
          "neither" ""
          (Ref_text.names_source_line ~family:None []);
        Alcotest.(check string)
          "family alone, no separator" "Plantaginaceae"
          (Ref_text.names_source_line ~family:(Some "Plantaginaceae") []));
    Alcotest.test_case "names_line joins with \", \"" `Quick (fun () ->
        Alcotest.(check string)
          "names_line" "Digitale pourpre, grande digitale"
          (Ref_text.names_line
             {
               Projection.lang = Projection.Lang.Fr;
               names = ["Digitale pourpre"; "grande digitale"];
             }));
    Alcotest.test_case "sources_line: joined, empty for []" `Quick (fun () ->
        Alcotest.(check string)
          "two sources" "GBIF, Wikidata"
          (Ref_text.sources_line [Source.Gbif; Source.Wikidata]);
        Alcotest.(check string)
          "one source" "GBIF"
          (Ref_text.sources_line [Source.Gbif]);
        Alcotest.(check string) "empty" "" (Ref_text.sources_line []));
    Alcotest.test_case "origin_line: 0, 1, 6, 7 and 80 names (\"et n autres\")"
      `Quick (fun () ->
        let names n = List.init n (fun i -> Printf.sprintf "C%02d" (i + 1)) in
        Alcotest.(check (option string))
          "0 names" None (Ref_text.origin_line []);
        Alcotest.(check (option string))
          "1 name" (Some "C01")
          (Ref_text.origin_line (names 1));
        Alcotest.(check (option string))
          "6 names, all joined" (Some "C01, C02, C03, C04, C05, C06")
          (Ref_text.origin_line (names 6));
        Alcotest.(check (option string))
          "7 names: first 5 then et 2 autres"
          (Some "C01, C02, C03, C04, C05 et 2 autres")
          (Ref_text.origin_line (names 7));
        Alcotest.(check (option string))
          "80 names: first 5 then et 75 autres"
          (Some "C01, C02, C03, C04, C05 et 75 autres")
          (Ref_text.origin_line (names 80)));
    Alcotest.test_case
      "red_list: every listed IUCN category, no-data categories, an unknown \
       string passed through"
      `Quick (fun () ->
        let case expected cat =
          Alcotest.(check (option string))
            (Printf.sprintf "red_list %S" cat)
            expected (Ref_text.red_list cat)
        in
        case (Some "LC · préoccupation mineure") "LEAST_CONCERN";
        case (Some "NT · quasi menacée") "NEAR_THREATENED";
        case (Some "VU · vulnérable") "VULNERABLE";
        case (Some "EN · en danger") "ENDANGERED";
        case (Some "CR · en danger critique") "CRITICALLY_ENDANGERED";
        case (Some "EW · éteinte à l'état sauvage") "EXTINCT_IN_THE_WILD";
        case (Some "EX · éteinte") "EXTINCT";
        case (Some "DD · données insuffisantes") "DATA_DEFICIENT";
        case None "NOT_EVALUATED";
        case None "NOT_APPLICABLE";
        case (Some "FOO") "FOO");
    Alcotest.test_case "month_letter: 1, 12, and out of range" `Quick (fun () ->
        Alcotest.(check string) "january" "J" (Ref_text.month_letter 1);
        Alcotest.(check string) "december" "D" (Ref_text.month_letter 12);
        Alcotest.(check string) "zero" "" (Ref_text.month_letter 0);
        Alcotest.(check string) "thirteen" "" (Ref_text.month_letter 13));
    Alcotest.test_case
      "months_text: runs, wrap across the year, dedup, invalid values dropped, \
       all twelve, empty"
      `Quick (fun () ->
        let case what expected months =
          Alcotest.(check string) what expected (Ref_text.months_text months)
        in
        case "a single run" "juin – août" [6; 7; 8];
        case "wraps December to January" "décembre – février" [12; 1; 2];
        case "two runs" "mars – avril, septembre" [3; 4; 9];
        case "one month" "mai" [5];
        case "all twelve" "toute l'année" (List.init 12 (fun i -> i + 1));
        case "empty" "" [];
        case "duplicates and an out-of-range value dropped" "juin – août"
          [8; 6; 7; 7];
        case "an invalid value dropped, one month left" "juin" [13; 6];
        case "a wrapping run after a plain month, ordered by first month"
          "mai, novembre – janvier" [11; 12; 1; 5];
        case "the smallest wrap" "décembre – janvier" [1; 12];
        case "eleven months are a wrapping run, not the whole year"
          "juillet – mai"
          [1; 2; 3; 4; 5; 7; 8; 9; 10; 11; 12]);
    Alcotest.test_case "organ_label for every organ" `Quick (fun () ->
        let case expected organ =
          Alcotest.(check string)
            (Organ.to_string organ) expected
            (Ref_text.organ_label organ)
        in
        case "fleur" Organ.Flower;
        case "feuille" Organ.Leaf;
        case "fruit" Organ.Fruit;
        case "port" Organ.Habit);
    Alcotest.test_case "credits: dedup by (attribution, licence), order, empty"
      `Quick (fun () ->
        let image ~attribution ~licence : Herbier_domain.Reference.Image.t =
          {
            plant_id = Herbier_domain.Ids.Plant_id.fresh ();
            source = Source.Plantnet;
            organ = Organ.Flower;
            remote_url = "https://bs.plantnet.org/image/o/x";
            licence;
            attribution;
            thumb_path = None;
          }
        in
        Alcotest.(check string) "empty" "" (Ref_text.credits []);
        Alcotest.(check string)
          "order kept, a duplicate (attribution, licence) dropped"
          "Photos : A (cc-by-sa), B (cc-by)"
          (Ref_text.credits
             [
               image ~attribution:"A" ~licence:"cc-by-sa";
               image ~attribution:"B" ~licence:"cc-by";
               image ~attribution:"A" ~licence:"cc-by-sa";
             ]);
        Alcotest.(check string)
          "same attribution, another licence: both kept"
          "Photos : A (cc-by-sa), A (cc-by)"
          (Ref_text.credits
             [
               image ~attribution:"A" ~licence:"cc-by-sa";
               image ~attribution:"A" ~licence:"cc-by";
             ]));
    Alcotest.test_case "link_label is source_name with an arrow" `Quick
      (fun () ->
        Alcotest.(check string)
          "GBIF" "GBIF ↗"
          (Ref_text.link_label Source.Gbif);
        Alcotest.(check string)
          "Pl@ntNet" "Pl@ntNet ↗"
          (Ref_text.link_label Source.Plantnet));
  ]

(* Journal_day *)

let obs ?(hour = 12) ?label ?derived ?pos () : Herbier_domain.Observation.t =
  let t = utc 2026 6 12 hour 0 in
  {
    id = Herbier_domain.Ids.Observation_id.fresh ();
    plant_id = None;
    at = t;
    position =
      Option.map
        (fun (lat, lon) ->
          {Herbier_domain.Observation.lat; lon; accuracy_m = None})
        pos;
    place_label = label;
    place_derived = derived;
    note = None;
    created_at = t;
    updated_at = t;
    deleted_at = None;
  }

let journal_day =
  let place = Alcotest.(option string) in
  [
    Alcotest.test_case "group consecutive" `Quick (fun () ->
        let days =
          Journal_day.group ~date:fst
            [((1, 1, 2), "a"); ((1, 1, 2), "b"); ((1, 1, 1), "c")]
        in
        Alcotest.(check (list (list string)))
          "items"
          [["a"; "b"]; ["c"]]
          (List.map (fun (d : _ Journal_day.t) -> List.map snd d.items) days));
    Alcotest.test_case "a date that comes back is a new day" `Quick (fun () ->
        let days =
          Journal_day.group ~date:fst
            [((1, 1, 2), "a"); ((1, 1, 1), "b"); ((1, 1, 2), "c")]
        in
        Alcotest.(check (list (list string)))
          "items" [["a"]; ["b"]; ["c"]]
          (List.map (fun (d : _ Journal_day.t) -> List.map snd d.items) days));
    Alcotest.test_case "one item, empty" `Quick (fun () ->
        Alcotest.(check int)
          "one day" 1
          (List.length (Journal_day.group ~date:Fun.id [(1, 1, 1)]));
        Alcotest.(check int)
          "no day" 0
          (List.length (Journal_day.group ~date:Fun.id [])));
    Alcotest.test_case "majority label" `Quick (fun () ->
        Alcotest.check place "label" (Some "Col")
          (Journal_day.place
             [
               obs ~label:"Lac" ();
               obs ~label:"Col" ();
               obs ~label:"Col" ();
               obs ~derived:"Près" ();
             ]));
    Alcotest.test_case "tie to the earliest, blank and padded labels" `Quick
      (fun () ->
        (* The store gives a day newest first. *)
        Alcotest.check place "earliest" (Some "Col")
          (Journal_day.place
             [obs ~hour:15 ~label:"Lac" (); obs ~hour:9 ~label:"Col" ()]);
        Alcotest.check place "trimmed, blank ignored" (Some "Lac")
          (Journal_day.place
             [obs ~label:"  " (); obs ~label:" Lac " (); obs ~derived:"Près" ()]));
    Alcotest.test_case "derived, then coordinates" `Quick (fun () ->
        Alcotest.check place "derived" (Some "Près de Colmar")
          (Journal_day.place
             [obs ~pos:(48.1, 7.2) (); obs ~derived:"Près de Colmar" ()]);
        Alcotest.check place "no name, positioned: Lieu inconnu"
          (Some "Lieu inconnu")
          (Journal_day.place [obs (); obs ~pos:(48.0633, 7.0081) ()]);
        Alcotest.check place
          "no name, two different positions: still Lieu inconnu"
          (Some "Lieu inconnu")
          (Journal_day.place
             [obs ~hour:15 ~pos:(48.1, 7.0) (); obs ~hour:9 ~pos:(48.3, 7.2) ()]);
        Alcotest.check place "a nan position is not placeable" None
          (Journal_day.place [obs ~pos:(Float.nan, 7.0) ()]);
        Alcotest.check place "none" None (Journal_day.place [obs ()]));
  ]

(* Map_filter, Map_sheet *)

module Ids = Herbier_domain.Ids
module Places = Herbier_domain.Places
module Photo = Herbier_domain.Photo

(* Shadows the Journal_day [obs] with one that can also carry a [plant_id],
   for Map_filter's identified/unidentified cases. *)
let obs ?(hour = 12) ?(minute = 0) ?plant ?label ?derived ?pos () :
    Herbier_domain.Observation.t =
  let t = utc 2026 6 12 hour minute in
  {
    id = Ids.Observation_id.fresh ();
    plant_id = plant;
    at = t;
    position =
      Option.map
        (fun (lat, lon) ->
          {Herbier_domain.Observation.lat; lon; accuracy_m = None})
        pos;
    place_label = label;
    place_derived = derived;
    note = None;
    created_at = t;
    updated_at = t;
    deleted_at = None;
  }

let cluster_of members : Places.cluster =
  {centroid = {lat = 0.; lon = 0.}; members}

let map_filter_place_name () =
  let str = Alcotest.(option string) in
  Alcotest.check str "Named gives its label" (Some "Jardin")
    (Map_filter.place_name (cluster_of [obs ~label:"Jardin" ()]));
  Alcotest.check str "Derived (no Named) gives the derived label"
    (Some "Près de Y")
    (Map_filter.place_name (cluster_of [obs ~derived:"Près de Y" ()]));
  Alcotest.check str "Coordinates gives None" None
    (Map_filter.place_name (cluster_of [obs ~pos:(48.1, 7.2) ()]));
  Alcotest.check str "no label, no position gives None" None
    (Map_filter.place_name (cluster_of [obs ()]))

let map_filter_false_whatever_the_query () =
  let p = Plant_id.fresh () in
  let o = obs ~plant:p () in
  let c = cluster_of [o] in
  let filter (_ : Herbier_domain.Observation.t) = false in
  List.iter
    (fun (name, query) ->
      Alcotest.(check bool) name false (Map_filter.keep ~filter query c o))
    [
      ("Everything, filter false", Map_filter.Everything);
      ( "Matching accepting everything, filter false",
        Map_filter.Matching
          {plants = [p]; place = (fun (_ : Places.cluster) -> true)} );
    ]

let map_filter_everything_is_filter () =
  let o1 = obs ~plant:(Plant_id.fresh ()) () and o2 = obs () in
  let c = cluster_of [o1; o2] in
  List.iter
    (fun (name, filter) ->
      Alcotest.(check bool)
        (name ^ ": o1") (filter o1)
        (Map_filter.keep ~filter Map_filter.Everything c o1);
      Alcotest.(check bool)
        (name ^ ": o2") (filter o2)
        (Map_filter.keep ~filter Map_filter.Everything c o2))
    [
      ("always true", fun (_ : Herbier_domain.Observation.t) -> true);
      ("always false", fun (_ : Herbier_domain.Observation.t) -> false);
    ]

let map_filter_matching_by_plant () =
  let p = Plant_id.fresh () and q = Plant_id.fresh () in
  let of_p = obs ~plant:p ()
  and of_q = obs ~plant:q ()
  and unidentified = obs () in
  let c = cluster_of [of_p; of_q; unidentified] in
  let query =
    Map_filter.Matching
      {plants = [p]; place = (fun (_ : Places.cluster) -> false)}
  in
  let filter (_ : Herbier_domain.Observation.t) = true in
  Alcotest.(check bool)
    "an observation of the matching plant passes" true
    (Map_filter.keep ~filter query c of_p);
  Alcotest.(check bool)
    "an observation of another plant does not" false
    (Map_filter.keep ~filter query c of_q);
  Alcotest.(check bool)
    "an unidentified observation does not pass through plants" false
    (Map_filter.keep ~filter query c unidentified)

let map_filter_matching_by_place_only () =
  let identified = obs ~plant:(Plant_id.fresh ()) () in
  let unidentified = obs () in
  let c = cluster_of [identified; unidentified] in
  let query =
    Map_filter.Matching
      {plants = []; place = (fun (_ : Places.cluster) -> true)}
  in
  Alcotest.(check bool)
    "an identified observation passes through place" true
    (Map_filter.keep ~filter:(fun _ -> true) query c identified);
  Alcotest.(check bool)
    "an unidentified observation passes through place too" true
    (Map_filter.keep ~filter:(fun _ -> true) query c unidentified);
  Alcotest.(check bool)
    "filter still gates it" false
    (Map_filter.keep ~filter:(fun _ -> false) query c identified)

let map_filter_place_matched_once_per_cluster () =
  let members = List.init 5 (fun _ -> obs ()) in
  let c = cluster_of members in
  let calls = ref 0 in
  let query =
    Map_filter.Matching
      {
        plants = [];
        place =
          (fun (_ : Places.cluster) ->
            incr calls;
            true);
      }
  in
  let keep = Map_filter.keep ~filter:(fun _ -> true) query c in
  Alcotest.(check (list bool))
    "every member passes through place"
    [true; true; true; true; true]
    (List.map keep members);
  Alcotest.(check int) "place is called once for the cluster" 1 !calls

let map_filter =
  [
    Alcotest.test_case "place_name" `Quick map_filter_place_name;
    Alcotest.test_case "keep with filter always false" `Quick
      map_filter_false_whatever_the_query;
    Alcotest.test_case "keep Everything is exactly filter" `Quick
      map_filter_everything_is_filter;
    Alcotest.test_case "keep Matching by plants" `Quick
      map_filter_matching_by_plant;
    Alcotest.test_case "keep Matching by place only (plants = [])" `Quick
      map_filter_matching_by_place_only;
    Alcotest.test_case "keep matches the place once per cluster" `Quick
      map_filter_place_matched_once_per_cluster;
  ]

let map_sheet_snaps () =
  let float_list = Alcotest.(list (float 1e-9)) in
  List.iter
    (fun (name, available, top, expected) ->
      Alcotest.check float_list name expected (Map_sheet.snaps ~available ~top))
    [
      ("available 800, top 104", 800., 104., [64.; 360.; 660.]);
      ("available 500, top 104", 500., 104., [64.; 250.; 360.]);
      (* A taller top (safe-area inset) lowers only the highest point. *)
      ("available 800, top 152", 800., 152., [64.; 360.; 612.]);
      ("top nan is 0", 800., Float.nan, [64.; 360.; 764.]);
      ("high = mid + 1, mid not raised", 200., 104., [64.; 100.; 101.]);
      ("available 100: mid raised to 65", 100., 104., [64.; 65.; 66.]);
      ("available 0", 0., 104., [64.; 65.; 66.]);
      ("available negative", -50., 104., [64.; 65.; 66.]);
      ("available nan", Float.nan, 104., [64.; 65.; 66.]);
    ]

let map_sheet_summary () =
  let str = Alcotest.string in
  let p1 = Plant_id.fresh ()
  and p2 = Plant_id.fresh ()
  and p3 = Plant_id.fresh ()
  and p4 = Plant_id.fresh () in
  Alcotest.check str "6 observations, 4 distinct plants"
    "rayon 500 m · 6 observations · 4 plantes"
    (Map_sheet.summary
       [
         obs ~plant:p1 ();
         obs ~plant:p1 ();
         obs ~plant:p2 ();
         obs ~plant:p3 ();
         obs ~plant:p4 ();
         obs ~plant:p4 ();
       ]);
  Alcotest.check str "1 observation, 1 plant"
    "rayon 500 m · 1 observation · 1 plante"
    (Map_sheet.summary [obs ~plant:p1 ()]);
  Alcotest.check str "2 unidentified observations"
    "rayon 500 m · 2 observations"
    (Map_sheet.summary [obs (); obs ()]);
  Alcotest.check str "two observations of the same plant: 1 plante"
    "rayon 500 m · 2 observations · 1 plante"
    (Map_sheet.summary [obs ~plant:p1 (); obs ~plant:p1 ()])

let map_sheet_collapsed () =
  let str = Alcotest.string in
  Alcotest.check str "3 places, 13 observations" "3 lieux · 13 observations"
    (Map_sheet.collapsed ~places:3 ~observations:13);
  Alcotest.check str "1 place, 1 observation" "1 lieu · 1 observation"
    (Map_sheet.collapsed ~places:1 ~observations:1);
  Alcotest.check str "no places" "Aucune observation sur la carte"
    (Map_sheet.collapsed ~places:0 ~observations:0)

let map_sheet_title () =
  let str = Alcotest.string in
  Alcotest.check str "majority place_label" "Col"
    (Map_sheet.title
       (cluster_of
          [obs ~label:"Col" (); obs ~label:"Col" (); obs ~label:"Lac" ()]));
  Alcotest.check str "derived only" "Près de Y"
    (Map_sheet.title (cluster_of [obs ~derived:"Près de Y" ()]));
  let positioned = cluster_of [obs ~pos:(48.1, 7.2) ()] in
  Alcotest.check str "neither label nor derived, but positioned: Lieu inconnu"
    "Lieu inconnu"
    (Map_sheet.title positioned);
  Alcotest.check str "no label and no position falls back to \"Lieu\"" "Lieu"
    (Map_sheet.title (cluster_of [obs ()]))

let map_sheet_rename_value () =
  let str = Alcotest.string in
  Alcotest.check str "Named gives the label" "Jardin"
    (Map_sheet.rename_value (cluster_of [obs ~label:"Jardin" ()]));
  Alcotest.check str "Derived only gives the empty string" ""
    (Map_sheet.rename_value (cluster_of [obs ~derived:"Près de Y" ()]))

let photo_id n =
  match
    Ids.Photo_id.of_string (Printf.sprintf "00000000-0000-4000-8000-%012d" n)
  with
  | Some id -> id
  | None -> Alcotest.failf "Photo_id.of_string of test id %d gave None" n

let photo ~id ~observation_id ~taken_at : Photo.t =
  {
    id = photo_id id;
    observation_id;
    taken_at;
    width = 100;
    height = 100;
    sha256 = String.make 64 '0';
    preview_path = "previews/x.jpg";
    preview_bucket_key = None;
    original_target = Photo.Original_target.App_only;
    drive_file_id = None;
    upload_state = Photo.Upload_state.Uploaded;
    created_at = taken_at;
    updated_at = taken_at;
    deleted_at = None;
  }

let map_sheet_photos_by_observation () =
  let o1 = obs () and o2 = obs () in
  let t1 = utc 2026 6 12 9 0 and t2 = utc 2026 6 12 10 0 in
  (* p_a, p_b: same taken_at for o1, so the tie must break by id. *)
  let p_a = photo ~id:2 ~observation_id:o1.id ~taken_at:t2 in
  let p_b = photo ~id:1 ~observation_id:o1.id ~taken_at:t2 in
  let p_early = photo ~id:3 ~observation_id:o1.id ~taken_at:t1 in
  let p_o2 = photo ~id:4 ~observation_id:o2.id ~taken_at:t1 in
  let photo_strs =
    List.map (fun (p : Photo.t) -> Ids.Photo_id.to_string p.id)
  in
  (* Given in [Photos.live] order: taken_at descending. *)
  let index = Map_sheet.photos_by_observation [p_a; p_b; p_early; p_o2] in
  Alcotest.(check (list string))
    "o1's photos ascending by taken_at, tie broken by id"
    (photo_strs [p_early; p_b; p_a])
    (photo_strs (index o1.id));
  Alcotest.(check (list string))
    "o2's single photo" (photo_strs [p_o2])
    (photo_strs (index o2.id));
  Alcotest.(check (list string))
    "an observation with no photo gives []" []
    (photo_strs (index (Ids.Observation_id.fresh ())))

let map_sheet_row_meta () =
  let str = Alcotest.string in
  Alcotest.check str "this year, 2 photos" "12 juin · 2 photos"
    (Map_sheet.row_meta ~this_year:2026 ~date:(2026, 6, 12) ~photos:2);
  Alcotest.check str "this year, 1 photo" "12 juin · 1 photo"
    (Map_sheet.row_meta ~this_year:2026 ~date:(2026, 6, 12) ~photos:1);
  Alcotest.check str "this year, 0 photos" "12 juin"
    (Map_sheet.row_meta ~this_year:2026 ~date:(2026, 6, 12) ~photos:0);
  Alcotest.check str "another year, 1 photo" "3 décembre 2025 · 1 photo"
    (Map_sheet.row_meta ~this_year:2026 ~date:(2025, 12, 3) ~photos:1)

let map_sheet_notices () =
  let str = Alcotest.string in
  List.iter
    (fun (n, expected) ->
      Alcotest.check str expected expected (Map_sheet.notice_text n))
    [
      (Map_sheet.Loading, "Chargement…");
      (Read_failed, "Lecture impossible");
      (Search_failed, "Recherche impossible");
      (Position_unavailable, "Position indisponible");
      (Location_denied, "Localisation non autorisée");
      (Location_off, "Localisation désactivée");
    ];
  Alcotest.check str "missing tokens" "Jetons absents : --map-point, --paper"
    (Map_sheet.broken_text (Missing_tokens ["--map-point"; "--paper"]));
  Alcotest.check str "map unavailable" "Carte indisponible"
    (Map_sheet.broken_text Map_unavailable);
  List.iter
    (fun (code, expected) ->
      Alcotest.check str
        (Option.value code ~default:"no code")
        (Map_sheet.notice_text expected)
        (Map_sheet.notice_text (Map_sheet.position_failure code)))
    [
      (Some "OS-PLUG-GLOC-0003", Map_sheet.Location_denied);
      (Some "OS-PLUG-GLOC-0007", Location_off);
      (Some "OS-PLUG-GLOC-0017", Location_off);
      (Some "OS-PLUG-GLOC-0010", Position_unavailable);
      (Some "UNAVAILABLE", Position_unavailable);
      (None, Position_unavailable);
    ]

let map_sheet =
  [
    Alcotest.test_case "snaps: exact heights" `Quick map_sheet_snaps;
    Alcotest.test_case "notice, broken and position texts" `Quick
      map_sheet_notices;
    Alcotest.test_case "summary" `Quick map_sheet_summary;
    Alcotest.test_case "collapsed" `Quick map_sheet_collapsed;
    Alcotest.test_case "title" `Quick map_sheet_title;
    Alcotest.test_case "rename_value" `Quick map_sheet_rename_value;
    Alcotest.test_case "photos_by_observation" `Quick
      map_sheet_photos_by_observation;
    Alcotest.test_case "row_meta" `Quick map_sheet_row_meta;
  ]

(* Tag_edits *)

let tag_id = Herbier_domain.Ids.Tag_id.fresh
let plant_id = Herbier_domain.Ids.Plant_id.fresh

let tag_edits =
  let p1 = plant_id ()
  and p2 = plant_id ()
  and p3 = plant_id ()
  and p4 = plant_id ()
  and p5 = plant_id () in
  let ta = tag_id () and tb = tag_id () and tc = tag_id () in
  let model () =
    Tag_edits.init
      [(ta, "bois", [p1]); (tb, "forêt", [p1; p2]); (tc, "lisière", [p3])]
  in
  let names m =
    List.map (fun (e : Tag_edits.entry) -> e.name) (Tag_edits.visible m)
  in
  let tag_name id =
    List.assoc_opt id [(ta, "a"); (tb, "b"); (tc, "c")]
    |> Option.value ~default:"?"
  and plant_name id =
    List.assoc_opt id [(p1, "p1"); (p2, "p2"); (p3, "p3")]
    |> Option.value ~default:"?"
  in
  let show = function
    | Tag_edits.Rename (id, n) -> tag_name id ^ "=" ^ n
    | Tag_edits.Delete id -> "del " ^ tag_name id
    | Tag_edits.Link {plant; tag} ->
        Printf.sprintf "link %s %s" (plant_name plant) (tag_name tag)
    | Tag_edits.Unlink {plant; tag} ->
        Printf.sprintf "unlink %s %s" (plant_name plant) (tag_name tag)
  in
  let ops m = List.map show (Tag_edits.plan m) in
  let strs = Alcotest.(list string) in
  [
    Alcotest.test_case "nothing staged, nothing planned" `Quick (fun () ->
        Alcotest.check strs "ops" [] (ops (model ())));
    Alcotest.test_case "rename, blank ignored" `Quick (fun () ->
        let m =
          Tag_edits.rename ta "  " (Tag_edits.rename ta "bosquet" (model ()))
        in
        Alcotest.check strs "names" ["bosquet"; "forêt"; "lisière"] (names m);
        Alcotest.check strs "ops" ["a=bosquet"] (ops m));
    Alcotest.test_case "delete" `Quick (fun () ->
        let m = Tag_edits.delete [tc] (model ()) in
        Alcotest.check strs "names" ["bois"; "forêt"] (names m);
        Alcotest.check strs "ops" ["del c"] (ops m));
    Alcotest.test_case "merge keeps the most used" `Quick (fun () ->
        let m = model () in
        Alcotest.(check (option string))
          "winner" (Some "forêt")
          (Option.map
             (fun (e : Tag_edits.entry) -> e.name)
             (Tag_edits.winner [ta; tb] m));
        let m = Tag_edits.merge [ta; tb] m in
        Alcotest.check strs "names" ["forêt"; "lisière"] (names m);
        Alcotest.(check int)
          "plants" 2
          (List.length (Tag_edits.plants m (List.nth (Tag_edits.visible m) 0)));
        Alcotest.check strs "ops" ["link p1 b"; "unlink p1 a"; "del a"] (ops m));
    Alcotest.test_case "merge follows an earlier merge" `Quick (fun () ->
        (* a into b, then b and c: b keeps 2 plants (a's p1 is already on
           it), c has 1. *)
        let m =
          Tag_edits.merge [tb; tc] (Tag_edits.merge [ta; tb] (model ()))
        in
        Alcotest.check strs "names" ["forêt"] (names m);
        Alcotest.check strs "ops"
          [
            "link p1 b";
            "unlink p1 a";
            "del a";
            "link p3 b";
            "unlink p3 c";
            "del c";
          ]
          (ops m));
    Alcotest.test_case "a later winner takes the earlier merge along" `Quick
      (fun () ->
        let m =
          Tag_edits.init
            [
              (ta, "bois", [p1]);
              (tb, "forêt", [p1; p2]);
              (tc, "lisière", [p3; p4; p5]);
            ]
        in
        let m = Tag_edits.merge [tb; tc] (Tag_edits.merge [ta; tb] m) in
        Alcotest.check strs "names" ["lisière"] (names m);
        Alcotest.check strs "ops"
          [
            "link p1 c";
            "unlink p1 a";
            "del a";
            "link p1 c";
            "link p2 c";
            "unlink p1 b";
            "unlink p2 b";
            "del b";
          ]
          (ops m));
    Alcotest.test_case "deleting a winner deletes what it absorbed" `Quick
      (fun () ->
        let m = Tag_edits.delete [tb] (Tag_edits.merge [ta; tb] (model ())) in
        Alcotest.check strs "names" ["lisière"] (names m);
        Alcotest.check strs "ops" ["del a"; "del b"] (ops m);
        Alcotest.(check (list string))
          "filter" []
          (List.map tag_name (Tag_edits.followed m [ta])));
    Alcotest.test_case "followed: merged to the winner, deleted dropped" `Quick
      (fun () ->
        let m = Tag_edits.delete [tc] (Tag_edits.merge [ta; tb] (model ())) in
        Alcotest.(check (list string))
          "filter" ["b"]
          (List.map tag_name (Tag_edits.followed m [ta; tb; tc])));
    Alcotest.test_case "winner: a tie goes to the first in model order" `Quick
      (fun () ->
        Alcotest.(check (option string))
          "winner" (Some "bois")
          (Option.map
             (fun (e : Tag_edits.entry) -> e.name)
             (Tag_edits.winner [tc; ta] (model ()))));
    Alcotest.test_case "one selected: no merge" `Quick (fun () ->
        Alcotest.check strs "ops" [] (ops (Tag_edits.merge [ta] (model ()))));
  ]

(* Plant_form *)

let plant_form =
  let t0 = utc 2026 6 1 0 0 in
  let tag name : Herbier_domain.Tag.t =
    {id = tag_id (); name; created_at = t0; updated_at = t0; deleted_at = None}
  in
  let forest = tag "Forêt"
  and toxic = tag "Toxique"
  and garden = tag "Jardin" in
  let plant : Herbier_domain.Plant.t =
    {
      id = plant_id ();
      display_name = "Digitale";
      aliases = ["gant de Notre-Dame"];
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
  let all = [forest; toxic; garden] in
  let f0 = Plant_form.of_plant plant [forest] in
  let names f = List.map Plant_form.tag_name f.Plant_form.tags in
  let strs = Alcotest.(list string) in
  let ids = List.map Herbier_domain.Ids.Tag_id.to_string in
  [
    Alcotest.test_case "unchanged form, no change" `Quick (fun () ->
        let c = Plant_form.diff ~before:plant ~before_tags:[forest] f0 in
        Alcotest.(check bool) "plant" true (Option.is_none c.plant);
        Alcotest.check strs "create_tags" [] c.create_tags;
        Alcotest.check strs "link" [] (ids c.link);
        Alcotest.check strs "unlink" [] (ids c.unlink));
    Alcotest.test_case "a padded but equal name is no change" `Quick (fun () ->
        let c =
          Plant_form.diff ~before:plant ~before_tags:[forest]
            {f0 with name = " Digitale "}
        in
        Alcotest.(check bool) "plant" true (Option.is_none c.plant));
    Alcotest.test_case "tags: existing by name, created, duplicate, blank"
      `Quick (fun () ->
        let f =
          f0
          |> Plant_form.add_tag ~all " toxique "
          |> Plant_form.add_tag ~all "Lisière"
          |> Plant_form.add_tag ~all "forêt"
          |> Plant_form.add_tag ~all "  "
        in
        Alcotest.check strs "tags" ["Forêt"; "Toxique"; "Lisière"] (names f);
        let c =
          Plant_form.diff ~before:plant ~before_tags:[forest]
            (Plant_form.remove_tag (Plant_form.Existing forest) f)
        in
        Alcotest.check strs "created" ["Lisière"] c.create_tags;
        Alcotest.check strs "link toxic" (ids [toxic.id]) (ids c.link);
        Alcotest.check strs "unlink forest" (ids [forest.id]) (ids c.unlink));
    Alcotest.test_case "a created tag: deduplicated, then removed" `Quick
      (fun () ->
        let f =
          f0
          |> Plant_form.add_tag ~all "Lisière"
          |> Plant_form.add_tag ~all "lisière"
        in
        Alcotest.check strs "tags" ["Forêt"; "Lisière"] (names f);
        let c =
          Plant_form.diff ~before:plant ~before_tags:[forest]
            (Plant_form.remove_tag (Plant_form.Created "Lisière") f)
        in
        Alcotest.check strs "created" [] c.create_tags);
    Alcotest.test_case "name and aliases" `Quick (fun () ->
        let f =
          {
            (Plant_form.add_alias "Gant de notre-dame" f0) with
            name = "  Digitale pourpre ";
          }
        in
        let f = Plant_form.add_alias "doigtier" f in
        Alcotest.check strs "aliases"
          ["gant de Notre-Dame"; "doigtier"]
          f.aliases;
        let c = Plant_form.diff ~before:plant ~before_tags:[forest] f in
        Alcotest.(check (option string))
          "name" (Some "Digitale pourpre")
          (Option.map
             (fun (p : Herbier_domain.Plant.t) -> p.display_name)
             c.plant);
        Alcotest.(check bool)
          "blank invalid" false
          (Plant_form.valid {f with name = " "}));
    Alcotest.test_case "cover: chosen, kept, cleared" `Quick (fun () ->
        let pid = Herbier_domain.Ids.Photo_id.fresh () in
        let cover (p : Herbier_domain.Plant.t option) =
          Option.map
            (fun (p : Herbier_domain.Plant.t) ->
              Option.map Herbier_domain.Ids.Photo_id.to_string p.cover_photo_id)
            p
        in
        let c =
          Plant_form.diff ~before:plant ~before_tags:[forest]
            {f0 with cover = Some pid}
        in
        Alcotest.(check (option (option string)))
          "chosen"
          (Some (Some (Herbier_domain.Ids.Photo_id.to_string pid)))
          (cover c.plant);
        Alcotest.(check (option string))
          "name kept" (Some "Digitale")
          (Option.map
             (fun (p : Herbier_domain.Plant.t) -> p.display_name)
             c.plant);
        let with_cover = {plant with cover_photo_id = Some pid} in
        let f = Plant_form.of_plant with_cover [forest] in
        Alcotest.(check (option string))
          "of_plant"
          (Some (Herbier_domain.Ids.Photo_id.to_string pid))
          (Option.map Herbier_domain.Ids.Photo_id.to_string f.cover);
        Alcotest.(check bool)
          "kept: no change" true
          (Option.is_none
             (Plant_form.diff ~before:with_cover ~before_tags:[forest] f).plant);
        Alcotest.(check (option (option string)))
          "cleared" (Some None)
          (cover
             (Plant_form.diff ~before:with_cover ~before_tags:[forest]
                {f with cover = None})
               .plant));
    Alcotest.test_case "aliases only" `Quick (fun () ->
        let c =
          Plant_form.diff ~before:plant ~before_tags:[forest]
            (Plant_form.add_alias "doigtier" f0)
        in
        Alcotest.(check (option strs))
          "aliases"
          (Some ["gant de Notre-Dame"; "doigtier"])
          (Option.map (fun (p : Herbier_domain.Plant.t) -> p.aliases) c.plant));
    Alcotest.test_case "remove_alias" `Quick (fun () ->
        let c =
          Plant_form.diff ~before:plant ~before_tags:[forest]
            (Plant_form.remove_alias "gant de Notre-Dame" f0)
        in
        Alcotest.(check (option strs))
          "aliases" (Some [])
          (Option.map (fun (p : Herbier_domain.Plant.t) -> p.aliases) c.plant));
    Alcotest.test_case "a new plant: from a blank record" `Quick (fun () ->
        let blank = {plant with display_name = ""; aliases = []} in
        let f =
          {(Plant_form.of_plant blank []) with name = "Digitale"}
          |> Plant_form.add_tag ~all "Toxique"
          |> Plant_form.add_tag ~all "Lisière"
        in
        let c = Plant_form.diff ~before:blank ~before_tags:[] f in
        Alcotest.(check (option string))
          "name" (Some "Digitale")
          (Option.map
             (fun (p : Herbier_domain.Plant.t) -> p.display_name)
             c.plant);
        Alcotest.check strs "created" ["Lisière"] c.create_tags;
        Alcotest.check strs "link" (ids [toxic.id]) (ids c.link);
        Alcotest.check strs "unlink" [] (ids c.unlink));
  ]

(* Local_time, To_identify *)

let local_time =
  (* Paris in 2026: +1 h until 29 Mar 01:00 UTC, +2 h until 25 Oct 01:00 UTC,
     then +1 h. *)
  let spring = utc 2026 3 29 1 0 and autumn = utc 2026 10 25 1 0 in
  let offset t =
    match
      (Ptime.is_earlier t ~than:spring, Ptime.is_earlier t ~than:autumn)
    with
    | true, _ -> 3600
    | false, true -> 7200
    | false, false -> 3600
  in
  (* New York in 2026: -5 h until 8 Mar 07:00 UTC, then -4 h. *)
  let new_york t =
    match Ptime.is_earlier t ~than:(utc 2026 3 8 7 0) with
    | true -> -18000
    | false -> -14400
  in
  let t = Alcotest.testable Ptime.pp Ptime.equal in
  let input ?(offset = offset) s = Local_time.of_input ~offset s in
  [
    Alcotest.test_case "to input" `Quick (fun () ->
        Alcotest.(check string)
          "summer" "2026-06-12T14:32"
          (Local_time.to_input ~tz_offset_s:7200 (utc 2026 6 12 12 32));
        let late =
          Option.get (Ptime.of_date_time ((2026, 6, 12), ((23, 30, 45), 0)))
        in
        Alcotest.(check string)
          "seconds dropped, next day" "2026-06-13T01:30"
          (Local_time.to_input ~tz_offset_s:7200 late));
    Alcotest.test_case "of input, each side of the change" `Quick (fun () ->
        Alcotest.(check (option t))
          "summer"
          (Some (utc 2026 6 12 12 32))
          (input "2026-06-12T14:32");
        Alcotest.(check (option t))
          "winter"
          (Some (utc 2026 11 2 8 5))
          (input "2026-11-02T09:05:00");
        Alcotest.(check (option t))
          "the hour before the autumn change"
          (Some (utc 2026 10 24 23 30))
          (input "2026-10-25T01:30"));
    Alcotest.test_case "of input, around a change" `Quick (fun () ->
        Alcotest.(check (option t))
          "repeated hour: the first one"
          (Some (utc 2026 10 25 0 30))
          (input "2026-10-25T02:30");
        Alcotest.(check (option t))
          "skipped hour, Paris: the offset before"
          (Some (utc 2026 3 29 1 30))
          (input "2026-03-29T02:30");
        Alcotest.(check (option t))
          "skipped hour, New York: the offset before"
          (Some (utc 2026 3 8 7 30))
          (input ~offset:new_york "2026-03-08T02:30");
        Alcotest.(check (option t))
          "New York, after the change"
          (Some (utc 2026 3 8 7 30))
          (input ~offset:new_york "2026-03-08T03:30");
        Alcotest.(check (option t))
          "New York, before the change"
          (Some (utc 2026 3 8 6 30))
          (input ~offset:new_york "2026-03-08T01:30"));
    Alcotest.test_case "of input, rejected" `Quick (fun () ->
        List.iter
          (fun s -> Alcotest.(check (option t)) s None (input s))
          [
            "2026-11-02 09:05";
            "2026-13-02T09:05";
            "2026-+6-12T14:32";
            "2026-06-1_T14:32";
            "0x7e-06-12T14:32";
            "2026-06-12T24:00";
            "2026-06-12T14:60";
            "2026-06-12T14:32:";
          ]);
  ]

let to_identify =
  let o1 = obs () and o2 = obs () and o3 = obs () and o4 = obs () in
  let name o =
    match
      List.find_index
        (fun (x : Herbier_domain.Observation.t) ->
          Herbier_domain.Ids.Observation_id.equal x.id
            o.Herbier_domain.Observation.id)
        [o1; o2; o3; o4]
    with
    | Some i -> i + 1
    | None -> 0
  in
  let pos x l =
    Option.map
      (fun (p : To_identify.position) ->
        (p.index, p.total, Option.map name p.next))
      (To_identify.position x l)
  in
  let p = Alcotest.(option (triple int int (option int))) in
  [
    Alcotest.test_case "position, next wraps" `Quick (fun () ->
        Alcotest.check p "first" (Some (1, 3, Some 2)) (pos o1 [o1; o2; o3]);
        Alcotest.check p "middle" (Some (2, 3, Some 3)) (pos o2 [o1; o2; o3]);
        Alcotest.check p "last wraps"
          (Some (3, 3, Some 1))
          (pos o3 [o1; o2; o3]);
        Alcotest.check p "two, last wraps"
          (Some (2, 2, Some 1))
          (pos o2 [o1; o2]);
        Alcotest.check p "alone" (Some (1, 1, None)) (pos o1 [o1]);
        Alcotest.check p "empty" None (pos o1 []);
        Alcotest.check p "gone" None (pos o4 [o1; o2; o3]));
  ]

(* Record_plan *)

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
  ]

(* Cover *)

let cover =
  let t0 = utc 2026 6 1 0 0 in
  let obs plant : Herbier_domain.Observation.t =
    {
      id = Herbier_domain.Ids.Observation_id.fresh ();
      plant_id = plant;
      at = t0;
      position = None;
      place_label = None;
      place_derived = None;
      note = None;
      created_at = t0;
      updated_at = t0;
      deleted_at = None;
    }
  in
  let photo (o : Herbier_domain.Observation.t) : Herbier_domain.Photo.t =
    let id = Herbier_domain.Ids.Photo_id.fresh () in
    {
      id;
      observation_id = o.id;
      taken_at = t0;
      width = 1;
      height = 1;
      sha256 = "";
      preview_path = "";
      preview_bucket_key = None;
      original_target = App_only;
      drive_file_id = None;
      upload_state = Pending;
      created_at = t0;
      updated_at = t0;
      deleted_at = None;
    }
  in
  let a = plant_id () and b = plant_id () in
  let oa = obs (Some a) and ob = obs (Some b) and on = obs None in
  let p1 = photo oa and p2 = photo ob and p3 = photo oa and p4 = photo on in
  let ids l =
    List.map
      (fun (p : Herbier_domain.Photo.t) ->
        Herbier_domain.Ids.Photo_id.to_string p.id)
      l
  in
  let strs = Alcotest.(list string) in
  [
    Alcotest.test_case "by plant keeps order, skips unlinked" `Quick (fun () ->
        let f = Cover.by_plant [oa; ob; on] [p1; p2; p3; p4] in
        Alcotest.check strs "a" (ids [p1; p3]) (ids (f a));
        Alcotest.check strs "b" (ids [p2]) (ids (f b)));
    Alcotest.test_case "by plant skips a photo of an unknown observation" `Quick
      (fun () ->
        (* [ox] is linked to [a] but not passed: its photo belongs to no
           plant. *)
        let ox = obs (Some a) in
        let p5 = photo ox in
        let f = Cover.by_plant [oa; ob; on] [p1; p5; p3] in
        Alcotest.check strs "a" (ids [p1; p3]) (ids (f a)));
    Alcotest.test_case "cover first, else newest" `Quick (fun () ->
        Alcotest.check strs "chosen"
          (ids [p3; p1])
          (ids (Cover.ordered (Some p3.id) [p1; p3]));
        Alcotest.check strs "gone"
          (ids [p1; p3])
          (ids (Cover.ordered (Some p2.id) [p1; p3]));
        Alcotest.check strs "none chosen"
          (ids [p1; p3])
          (ids (Cover.ordered None [p1; p3])));
    Alcotest.test_case "choose" `Quick (fun () ->
        let one l = ids (Option.to_list l) in
        Alcotest.check strs "none chosen: newest" (ids [p1])
          (one (Cover.choose None [p1; p3]));
        Alcotest.check strs "chosen" (ids [p3])
          (one (Cover.choose (Some p3.id) [p1; p3]));
        Alcotest.check strs "gone: newest" (ids [p1])
          (one (Cover.choose (Some p2.id) [p1; p3]));
        Alcotest.check strs "no photo" [] (one (Cover.choose None [])));
  ]

(* Zoom *)

let zoom =
  let w = 400. and h = 800. in
  let z =
    Alcotest.testable
      (fun f (t : Zoom.t) -> Format.fprintf f "{%g %g %g}" t.scale t.x t.y)
      (fun (a : Zoom.t) b ->
        Float.abs (a.scale -. b.scale) < 1e-9
        && Float.abs (a.x -. b.x) < 1e-9
        && Float.abs (a.y -. b.y) < 1e-9)
  in
  [
    Alcotest.test_case "about keeps the point still" `Quick (fun () ->
        Alcotest.check z "x2 at (100,200)"
          {scale = 2.; x = -100.; y = -200.}
          (Zoom.about ~w ~h Zoom.identity ~cx:100. ~cy:200. ~ratio:2.);
        let t = {Zoom.scale = 2.; x = -100.; y = -200.} in
        let t' = Zoom.about ~w ~h t ~cx:300. ~cy:100. ~ratio:1.5 in
        Alcotest.check z "x1.5 from x2 at (300,100)"
          {scale = 3.; x = -300.; y = -350.}
          t';
        (* the content point under (300, 100) stays under it *)
        Alcotest.(check (float 1e-9))
          "fixed"
          ((300. -. t.x) /. t.scale)
          ((300. -. t'.x) /. t'.scale));
    Alcotest.test_case "clamped scale and covering offsets" `Quick (fun () ->
        Alcotest.check z "below 1" Zoom.identity
          (Zoom.about ~w ~h Zoom.identity ~cx:0. ~cy:0. ~ratio:0.5);
        Alcotest.check z "above 4"
          {scale = 4.; x = -300.; y = -600.}
          (Zoom.about ~w ~h Zoom.identity ~cx:100. ~cy:200. ~ratio:10.);
        Alcotest.check z "capped from x3"
          {scale = 4.; x = 100. -. (400. *. 4. /. 3.); y = -500.}
          (Zoom.about ~w ~h
             {scale = 3.; x = -300.; y = -350.}
             ~cx:100. ~cy:100. ~ratio:2.);
        let t = {Zoom.scale = 2.; x = -100.; y = -200.} in
        Alcotest.check z "pinched out from x2" Zoom.identity
          (Zoom.about ~w ~h t ~cx:300. ~cy:100. ~ratio:0.25);
        Alcotest.check z "pan past the left and bottom edges"
          {scale = 2.; x = -400.; y = 0.}
          (Zoom.pan ~w ~h t ~dx:(-1000.) ~dy:500.);
        Alcotest.check z "pan past the right and top edges"
          {scale = 2.; x = 0.; y = -800.}
          (Zoom.pan ~w ~h t ~dx:1000. ~dy:(-1000.)));
    Alcotest.test_case "zoomed above 1 %, settled below" `Quick (fun () ->
        let t = {Zoom.scale = 2.; x = -100.; y = -200.} in
        let barely = {Zoom.scale = 1.005; x = -2.; y = -1.} in
        Alcotest.(check bool) "zoomed" true (Zoom.zoomed t);
        Alcotest.(check bool) "not zoomed" false (Zoom.zoomed Zoom.identity);
        Alcotest.(check bool) "x1.005" false (Zoom.zoomed barely);
        Alcotest.check z "settle x1.005" Zoom.identity (Zoom.settle barely);
        Alcotest.check z "settle x2" t (Zoom.settle t));
  ]

let () =
  Alcotest.run "ui"
    [
      ("zoom", zoom);
      ("cover", cover);
      ("record_plan", record_plan);
      ("local_time", local_time);
      ("to_identify", to_identify);
      ("plant_form", plant_form);
      ("tag_edits", tag_edits);
      ("fr_date", fr_date @ ago);
      ("plant_link", plant_link);
      ("ref_search", ref_search);
      ("ref_pick", ref_pick);
      ("ref_paste", ref_paste);
      ("ref_text", ref_text);
      ("journal_day", journal_day);
      ("map_filter", map_filter);
      ("map_sheet", map_sheet);
      ( "list_patch",
        [
          check "identical" [a; b; c] [a; b; c] (Some []);
          check "empty to list" [] [a; b] (Some ["I0:1"; "I1:2"]);
          check "list to empty" [a; b] [] (Some ["R1"; "R0"]);
          check "filter keeps order" [a; b; c; d] [b; d] (Some ["R2"; "R0"]);
          check "unfilter" [b; d] [a; b; c; d] (Some ["I0:1"; "I2:3"]);
          check "swap one for another" [a; b; c] [a; d]
            (Some ["R2"; "R1"; "I1:4"]);
          check "update in place" [a; b; c] [a; (2, "b'"); c] (Some ["U1:2"]);
          check "update and insert" [a; c]
            [(1, "a'"); b; c]
            (Some ["U0:1"; "I1:2"]);
          check "out of order: rebuild" [a; b; c] [c; a; b]
            (Some ["R2"; "R1"; "R0"; "I0:3"; "I1:1"; "I2:2"]);
          check "out of order with removal" [a; b; c; d] [c; b]
            (Some ["R3"; "R2"; "R1"; "R0"; "I0:3"; "I1:2"]);
          check "update after remove" [a; b; c]
            [(1, "a'"); c]
            (Some ["R1"; "U0:1"]);
          check "single element" [a] [a] (Some []);
          check "single element updated" [a] [(1, "a'")] (Some ["U0:1"]);
          check "append" [a] [a; b] (Some ["I1:2"]);
          exhaustive;
        ] );
      ("collection_filter", collection_filter);
      ("journal_filter", journal_filter);
      ("fr_text", fr_text);
      ("snap", snap);
    ]
