module Tag_edits = Herbier_ui_model.Tag_edits

let tag_id = Fixtures.tag_id
let plant_id = Fixtures.plant_id

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
