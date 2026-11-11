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
          (header (2026, 2, 30)));
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
        Alcotest.check place "coords" (Some "48.0633, 7.0081")
          (Journal_day.place [obs (); obs ~pos:(48.0633, 7.0081) ()]);
        Alcotest.check place "mean of the positions" (Some "48.2000, 7.1000")
          (Journal_day.place
             [obs ~hour:15 ~pos:(48.1, 7.0) (); obs ~hour:9 ~pos:(48.3, 7.2) ()]);
        Alcotest.check place "a nan position is not placeable" None
          (Journal_day.place [obs ~pos:(Float.nan, 7.0) ()]);
        Alcotest.check place "none" None (Journal_day.place [obs ()]));
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

let () =
  Alcotest.run "ui"
    [
      ("plant_form", plant_form);
      ("tag_edits", tag_edits);
      ("fr_date", fr_date);
      ("journal_day", journal_day);
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
