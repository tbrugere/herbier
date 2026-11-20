(* [followed]'s sort is checked against the mint order of [ta; tb; tc; td]
   (fresh v7 ids, so [Tag_id.compare] agrees with it), not recomputed with
   [List.sort]. *)

module Tag_edits = Herbier_ui_model.Tag_edits
module Tag_id = Herbier_domain.Ids.Tag_id

let utc = Fixtures.utc
let tag_id = Fixtures.tag_id
let plant_id = Fixtures.plant_id

let tag_edits =
  let t0 = utc 2026 1 1 0 0 in
  let tag id name : Herbier_domain.Tag.t =
    {id; name; created_at = t0; updated_at = t0; deleted_at = None}
  in
  let p1 = plant_id () and p2 = plant_id () and p3 = plant_id () in
  (* Minted in this order: ta < tb < tc < td under [Tag_id.compare]. *)
  let ta = tag_id () and tb = tag_id () and tc = tag_id () and td = tag_id () in
  let bois = tag ta "bois" in
  let foret = tag tb "forêt" in
  let lisiere = tag tc "lisière" in
  let tags = [bois; foret; lisiere] in
  let tag_label id =
    List.assoc_opt id [(ta, "ta"); (tb, "tb"); (tc, "tc"); (td, "td")]
    |> Option.value ~default:(Tag_id.to_string id)
  and plant_label id =
    List.assoc_opt id [(p1, "p1"); (p2, "p2"); (p3, "p3")]
    |> Option.value ~default:"p?"
  in
  let edit tag plants = Tag_edits.Edit {tag; plants} in
  let new_tag = Tag_edits.New in
  let show_check = function
    | Tag_edits.Blank -> "Blank"
    | Tag_edits.Same -> "Same"
    | Tag_edits.Taken t -> "Taken " ^ t.name
    | Tag_edits.Free s -> "Free " ^ s
  in
  let check_str editor text = show_check (Tag_edits.check ~tags editor text) in
  let show_change = function
    | Tag_edits.Create n -> "Create " ^ n
    | Tag_edits.Rename {tag; name} ->
        Printf.sprintf "Rename {tag=%s; name=%s}" (tag_label tag.id) name
    | Tag_edits.Merge {from; into; plants} ->
        Printf.sprintf "Merge {from=%s; into=%s; plants=[%s]}" (tag_label from)
          (tag_label into)
          (String.concat ";" (List.map plant_label plants))
    | Tag_edits.Delete id -> "Delete " ^ tag_label id
  in
  let show_change_opt = function
    | None -> "None"
    | Some c -> "Some (" ^ show_change c ^ ")"
  in
  let show_op = function
    | Tag_edits.Insert_tag n -> "Insert " ^ n
    | Tag_edits.Rename_tag (t, n) ->
        Printf.sprintf "Rename (%s, %s)" (tag_label t.id) n
    | Tag_edits.Delete_tag id -> "Delete " ^ tag_label id
    | Tag_edits.Link {plant; tag} ->
        Printf.sprintf "Link {plant=%s; tag=%s}" (plant_label plant)
          (tag_label tag)
    | Tag_edits.Unlink {plant; tag} ->
        Printf.sprintf "Unlink {plant=%s; tag=%s}" (plant_label plant)
          (tag_label tag)
  in
  let ops_strs c = List.map show_op (Tag_edits.plan c) in
  let labels = List.map tag_label in
  let strs = Alcotest.(list string) in
  [
    (* 1. check, New. *)
    Alcotest.test_case "check New: empty is Blank" `Quick (fun () ->
        Alcotest.(check string) "check" "Blank" (check_str new_tag ""));
    Alcotest.test_case "check New: blank once trimmed is Blank" `Quick
      (fun () ->
        Alcotest.(check string) "check" "Blank" (check_str new_tag "   "));
    Alcotest.test_case "check New: an existing name (trimmed) is Taken" `Quick
      (fun () ->
        Alcotest.(check string)
          "check" "Taken forêt"
          (check_str new_tag " forêt "));
    Alcotest.test_case "check New: ASCII-only fold, Ê does not match ê" `Quick
      (fun () ->
        Alcotest.(check string) "check" "Free FORÊT" (check_str new_tag "FORÊT"));
    Alcotest.test_case "check New: ascii-case fold still matches on F/orêt"
      `Quick (fun () ->
        Alcotest.(check string)
          "check" "Taken forêt"
          (check_str new_tag "Forêt"));
    Alcotest.test_case "check New: a free name, trimmed" `Quick (fun () ->
        Alcotest.(check string) "check" "Free mare" (check_str new_tag " mare "));
    (* 2. check, Edit bois. *)
    Alcotest.test_case "check Edit: its own exact name is Same" `Quick
      (fun () ->
        Alcotest.(check string)
          "check" "Same"
          (check_str (edit bois [p1]) "bois"));
    Alcotest.test_case "check Edit: its own name, trimmed, is Same" `Quick
      (fun () ->
        Alcotest.(check string)
          "check" "Same"
          (check_str (edit bois [p1]) " bois "));
    Alcotest.test_case "check Edit: a case-only change of its own name is Free"
      `Quick (fun () ->
        Alcotest.(check string)
          "check" "Free Bois"
          (check_str (edit bois [p1]) "Bois"));
    Alcotest.test_case "check Edit: another tag's name is Taken" `Quick
      (fun () ->
        Alcotest.(check string)
          "check" "Taken forêt"
          (check_str (edit bois [p1]) "forêt"));
    Alcotest.test_case "check Edit: another tag's name, case-folded, is Taken"
      `Quick (fun () ->
        Alcotest.(check string)
          "check" "Taken forêt"
          (check_str (edit bois [p1]) "Forêt"));
    Alcotest.test_case "check Edit: an unused name is Free" `Quick (fun () ->
        Alcotest.(check string)
          "check" "Free bosquet"
          (check_str (edit bois [p1]) "bosquet"));
    Alcotest.test_case "check Edit: blank is Blank" `Quick (fun () ->
        Alcotest.(check string) "check" "Blank" (check_str (edit bois [p1]) ""));
    (* 3. primary: one row per case of the doc's table. *)
    Alcotest.test_case "primary New Blank: Créer, disabled, no line" `Quick
      (fun () ->
        let p = Tag_edits.primary new_tag Tag_edits.Blank in
        Alcotest.(check string) "label" "Créer" p.label;
        Alcotest.(check bool) "enabled" false p.enabled;
        Alcotest.(check (option string)) "line" None p.line);
    Alcotest.test_case "primary New Taken: Créer, disabled, exists line" `Quick
      (fun () ->
        let p = Tag_edits.primary new_tag (Tag_edits.Taken foret) in
        Alcotest.(check string) "label" "Créer" p.label;
        Alcotest.(check bool) "enabled" false p.enabled;
        Alcotest.(check (option string))
          "line" (Some "« forêt » existe déjà.") p.line);
    Alcotest.test_case "primary New Free: Créer, enabled, no line" `Quick
      (fun () ->
        let p = Tag_edits.primary new_tag (Tag_edits.Free "mare") in
        Alcotest.(check string) "label" "Créer" p.label;
        Alcotest.(check bool) "enabled" true p.enabled;
        Alcotest.(check (option string)) "line" None p.line);
    Alcotest.test_case "primary New Same: answered as Blank" `Quick (fun () ->
        let p = Tag_edits.primary new_tag Tag_edits.Same in
        Alcotest.(check string) "label" "Créer" p.label;
        Alcotest.(check bool) "enabled" false p.enabled;
        Alcotest.(check (option string)) "line" None p.line);
    Alcotest.test_case "primary Edit Blank: Enregistrer, disabled, no line"
      `Quick (fun () ->
        let p = Tag_edits.primary (edit bois [p1]) Tag_edits.Blank in
        Alcotest.(check string) "label" "Enregistrer" p.label;
        Alcotest.(check bool) "enabled" false p.enabled;
        Alcotest.(check (option string)) "line" None p.line);
    Alcotest.test_case "primary Edit Same: Enregistrer, disabled, no line"
      `Quick (fun () ->
        let p = Tag_edits.primary (edit bois [p1]) Tag_edits.Same in
        Alcotest.(check string) "label" "Enregistrer" p.label;
        Alcotest.(check bool) "enabled" false p.enabled;
        Alcotest.(check (option string)) "line" None p.line);
    Alcotest.test_case "primary Edit Free: Enregistrer, enabled, no line" `Quick
      (fun () ->
        let p = Tag_edits.primary (edit bois [p1]) (Tag_edits.Free "bosquet") in
        Alcotest.(check string) "label" "Enregistrer" p.label;
        Alcotest.(check bool) "enabled" true p.enabled;
        Alcotest.(check (option string)) "line" None p.line);
    Alcotest.test_case
      "primary Edit Taken: Fusionner, enabled, the merge-warning line" `Quick
      (fun () ->
        let p = Tag_edits.primary (edit bois [p1]) (Tag_edits.Taken foret) in
        Alcotest.(check string) "label" "Fusionner" p.label;
        Alcotest.(check bool) "enabled" true p.enabled;
        Alcotest.(check (option string))
          "line" (Some "« forêt » existe déjà : « bois » y sera fusionné.")
          p.line);
    (* 4. submit: None exactly when primary is disabled, over every case of
       1 and 2, plus the three enabled outcomes' exact shapes. *)
    Alcotest.test_case "submit is None exactly where primary is disabled" `Quick
      (fun () ->
        let cases =
          [
            (new_tag, "");
            (new_tag, "   ");
            (new_tag, " forêt ");
            (new_tag, "FORÊT");
            (new_tag, "Forêt");
            (new_tag, " mare ");
            (edit bois [p1], "bois");
            (edit bois [p1], " bois ");
            (edit bois [p1], "Bois");
            (edit bois [p1], "forêt");
            (edit bois [p1], "Forêt");
            (edit bois [p1], "bosquet");
            (edit bois [p1], "");
          ]
        in
        List.iter
          (fun (editor, text) ->
            let check = Tag_edits.check ~tags editor text in
            let enabled = (Tag_edits.primary editor check).enabled in
            let submitted = Tag_edits.submit ~tags editor text in
            Alcotest.(check bool)
              (Printf.sprintf "submit <> None iff enabled (%S)" text)
              enabled (Option.is_some submitted))
          cases);
    Alcotest.test_case "submit New Free: Create of the trimmed name" `Quick
      (fun () ->
        Alcotest.(check string)
          "submit" "Some (Create mare)"
          (show_change_opt (Tag_edits.submit ~tags new_tag " mare ")));
    Alcotest.test_case "submit Edit Free: Rename to the trimmed name" `Quick
      (fun () ->
        Alcotest.(check string)
          "submit" "Some (Rename {tag=ta; name=bosquet})"
          (show_change_opt (Tag_edits.submit ~tags (edit bois [p1]) "bosquet")));
    Alcotest.test_case "submit Edit Taken: Merge from this tag into the other"
      `Quick (fun () ->
        Alcotest.(check string)
          "submit" "Some (Merge {from=ta; into=tb; plants=[p1]})"
          (show_change_opt (Tag_edits.submit ~tags (edit bois [p1]) "forêt")));
    Alcotest.test_case "submit Edit Taken, case-folded: the same Merge" `Quick
      (fun () ->
        Alcotest.(check string)
          "submit" "Some (Merge {from=ta; into=tb; plants=[p1]})"
          (show_change_opt (Tag_edits.submit ~tags (edit bois [p1]) "Forêt")));
    Alcotest.test_case "submit Edit Taken of a tag no plant carries: no plants"
      `Quick (fun () ->
        Alcotest.(check string)
          "submit" "Some (Merge {from=tc; into=ta; plants=[]})"
          (show_change_opt (Tag_edits.submit ~tags (edit lisiere []) "bois")));
    (* 5. delete. *)
    Alcotest.test_case "delete New is None" `Quick (fun () ->
        Alcotest.(check bool)
          "delete" true
          (Option.is_none (Tag_edits.delete new_tag)));
    Alcotest.test_case "delete Edit is Some (Delete its id)" `Quick (fun () ->
        Alcotest.(check string)
          "delete" "Some (Delete ta)"
          (show_change_opt (Tag_edits.delete (edit bois [p1]))));
    (* 6. delete_title / delete_text. *)
    Alcotest.test_case "delete_title names the tag" `Quick (fun () ->
        Alcotest.(check string)
          "delete_title" "Supprimer « bois » ?"
          (Tag_edits.delete_title bois));
    Alcotest.test_case "delete_text with no plant" `Quick (fun () ->
        Alcotest.(check string)
          "delete_text" "Aucune plante ne le porte."
          (Tag_edits.delete_text ~plants:0));
    Alcotest.test_case "delete_text with one plant, French singular" `Quick
      (fun () ->
        Alcotest.(check string)
          "delete_text" "Il sera retiré de 1 plante. Les plantes restent."
          (Tag_edits.delete_text ~plants:1));
    Alcotest.test_case "delete_text with several plants, French plural" `Quick
      (fun () ->
        Alcotest.(check string)
          "delete_text" "Il sera retiré de 3 plantes. Les plantes restent."
          (Tag_edits.delete_text ~plants:3));
    Alcotest.test_case "delete_text below zero: as with no plant" `Quick
      (fun () ->
        Alcotest.(check string)
          "delete_text" "Aucune plante ne le porte."
          (Tag_edits.delete_text ~plants:(-1)));
    (* 7. plan. *)
    Alcotest.test_case "plan Create: one Insert" `Quick (fun () ->
        Alcotest.check strs "plan" ["Insert mare"]
          (ops_strs (Tag_edits.Create "mare")));
    Alcotest.test_case "plan Rename: one Rename op" `Quick (fun () ->
        Alcotest.check strs "plan" ["Rename (ta, bosquet)"]
          (ops_strs (Tag_edits.Rename {tag = bois; name = "bosquet"})));
    Alcotest.test_case
      "plan Merge: links the winner then unlinks the loser then deletes it, \
       plants in order"
      `Quick (fun () ->
        Alcotest.check strs "plan"
          [
            "Link {plant=p3; tag=tb}";
            "Link {plant=p1; tag=tb}";
            "Unlink {plant=p3; tag=tc}";
            "Unlink {plant=p1; tag=tc}";
            "Delete tc";
          ]
          (ops_strs (Tag_edits.Merge {from = tc; into = tb; plants = [p3; p1]})));
    Alcotest.test_case "plan Merge with no plants: only the Delete" `Quick
      (fun () ->
        Alcotest.check strs "plan" ["Delete tc"]
          (ops_strs (Tag_edits.Merge {from = tc; into = tb; plants = []})));
    Alcotest.test_case "plan Delete: one Delete op, links left alone" `Quick
      (fun () ->
        Alcotest.check strs "plan" ["Delete ta"]
          (ops_strs (Tag_edits.Delete ta)));
    (* 8. followed. *)
    Alcotest.test_case "followed: Delete drops the deleted id" `Quick (fun () ->
        Alcotest.check strs "followed" ["tc"]
          (labels (Tag_edits.followed (Tag_edits.Delete ta) [ta; tc])));
    Alcotest.test_case "followed: Merge turns the loser into the winner" `Quick
      (fun () ->
        Alcotest.check strs "followed" ["tb"]
          (labels
             (Tag_edits.followed
                (Tag_edits.Merge {from = ta; into = tb; plants = [p1]})
                [ta])));
    Alcotest.test_case
      "followed: Merge does not duplicate an already-present winner" `Quick
      (fun () ->
        Alcotest.check strs "followed" ["tb"]
          (labels
             (Tag_edits.followed
                (Tag_edits.Merge {from = ta; into = tb; plants = [p1]})
                [ta; tb])));
    Alcotest.test_case "followed: Rename changes nothing but the sort order"
      `Quick (fun () ->
        Alcotest.check strs "followed" ["ta"; "tc"]
          (labels
             (Tag_edits.followed
                (Tag_edits.Rename {tag = bois; name = "x"})
                [tc; ta])));
    Alcotest.test_case "followed: Create changes nothing but the sort order"
      `Quick (fun () ->
        Alcotest.check strs "followed" ["ta"; "tc"]
          (labels (Tag_edits.followed (Tag_edits.Create "y") [tc; ta])));
    Alcotest.test_case "followed: an id untouched by the change stays" `Quick
      (fun () ->
        Alcotest.check strs "followed" ["ta"; "tb"]
          (labels (Tag_edits.followed (Tag_edits.Delete td) [tb; ta])));
    Alcotest.test_case "followed: Merge keeps an id it does not touch" `Quick
      (fun () ->
        Alcotest.check strs "followed" ["tb"; "tc"]
          (labels
             (Tag_edits.followed
                (Tag_edits.Merge {from = ta; into = tb; plants = [p1]})
                [tc; ta])));
    (* 9. 4l's texts. *)
    Alcotest.test_case "subtitle: a failed read" `Quick (fun () ->
        Alcotest.(check string)
          "subtitle" "Lecture impossible"
          (Tag_edits.subtitle (Error ())));
    Alcotest.test_case "subtitle: no tag, the « + » hint" `Quick (fun () ->
        Alcotest.(check string)
          "subtitle" "Aucun tag pour l’instant. Touchez + pour en créer un."
          (Tag_edits.subtitle (Ok 0)));
    Alcotest.test_case "subtitle: one and several tags" `Quick (fun () ->
        Alcotest.(check string)
          "one" "1 tag · touchez pour filtrer la collection"
          (Tag_edits.subtitle (Ok 1));
        Alcotest.(check string)
          "several" "3 tags · touchez pour filtrer la collection"
          (Tag_edits.subtitle (Ok 3)));
    Alcotest.test_case "edit_label names the tag" `Quick (fun () ->
        Alcotest.(check string)
          "edit_label" "Modifier « bois »"
          (Tag_edits.edit_label bois));
    (* 10. title. *)
    Alcotest.test_case "title New: Nouveau tag" `Quick (fun () ->
        Alcotest.(check string) "title" "Nouveau tag" (Tag_edits.title new_tag));
    Alcotest.test_case "title Edit: Modifier le tag" `Quick (fun () ->
        Alcotest.(check string)
          "title" "Modifier le tag"
          (Tag_edits.title (edit bois [p1])));
  ]
