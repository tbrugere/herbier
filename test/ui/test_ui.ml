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
  [
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

let a = (1, "a")
and b = (2, "b")
and c = (3, "c")
and d = (4, "d")

let () =
  Alcotest.run "ui"
    [
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
    ]
