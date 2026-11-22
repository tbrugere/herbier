(* The tag picker's list: [Tag_pick.suggestions] shown as labels, so a
   [Create] reads « Créer « … » ». *)

module Tag_pick = Herbier_ui_model.Tag_pick

let tag_pick =
  let t0 = Fixtures.utc 2026 1 1 0 0 in
  let tag name : Herbier_domain.Tag.t =
    {
      id = Fixtures.tag_id ();
      name;
      created_at = t0;
      updated_at = t0;
      deleted_at = None;
    }
  in
  (* In the store's order (name, case-insensitive), with their plant counts. *)
  let tags =
    [
      (tag "bois", 1);
      (tag "Forêt", 3);
      (tag "forêt humide", 0);
      (tag "jardin", 3);
      (tag "lisière", 5);
    ]
  in
  let list ?(current = []) text =
    List.map Tag_pick.label (Tag_pick.suggestions ~tags ~current text)
  in
  let strs = Alcotest.(list string) in
  let case name f = Alcotest.test_case name `Quick f in
  [
    case "blank: every tag, most used first, ties in store order" (fun () ->
        Alcotest.check strs "list"
          ["lisière"; "Forêt"; "jardin"; "bois"; "forêt humide"]
          (list "  "));
    case "the plant's tags are left out, folded" (fun () ->
        Alcotest.check strs "list"
          ["jardin"; "bois"; "forêt humide"]
          (list ~current:["LISIERE"; "forêt"] ""));
    case "typing filters, accents and case folded" (fun () ->
        Alcotest.check strs "list" ["Forêt"; "forêt humide"] (list "FORET"));
    case "a word of the name matches" (fun () ->
        Alcotest.check strs "list"
          ["forêt humide"; "Créer « hum »"]
          (list "hum"));
    case "the exact folded match comes first" (fun () ->
        Alcotest.check strs "list" ["Forêt"; "forêt humide"] (list " foret "));
    case "exact match: no « Créer »" (fun () ->
        Alcotest.check strs "list" ["bois"] (list "Bois"));
    case "no match: only « Créer », the text trimmed" (fun () ->
        Alcotest.check strs "list" ["Créer « Prairie »"] (list "  Prairie "));
    case "a prefix lists the tags, then « Créer »" (fun () ->
        Alcotest.check strs "list" ["jardin"; "Créer « jar »"] (list "jar"));
    case "a tag already on the plant: neither listed nor created" (fun () ->
        Alcotest.check strs "list" [] (list ~current:["bois"] "BOIS"));
    case "a name on the plant not yet saved: no « Créer »" (fun () ->
        Alcotest.check strs "list" [] (list ~current:["Prairie"] "prairie"));
    case "matching by use: most used first" (fun () ->
        Alcotest.check strs "list"
          ["Forêt"; "forêt humide"; "Créer « for »"]
          (list "for"));
    case "name: the tag's, or the trimmed text" (fun () ->
        Alcotest.check strs "names" ["bois"; "Prairie"]
          (List.map Tag_pick.name
             (Tag_pick.suggestions ~tags ~current:[] "bois"
             @ Tag_pick.suggestions ~tags ~current:[] " Prairie ")));
  ]
