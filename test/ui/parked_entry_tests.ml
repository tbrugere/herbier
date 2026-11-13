(* Parked_entry: a parked outbox entry as 4m lists it. *)

module Parked_entry = Herbier_ui_model.Parked_entry
module Synced = Herbier_sync_core.Synced

let parked_entry =
  let describe = Parked_entry.describe in
  let title_of table_name payload =
    (describe ~table_name ~payload ~last_error:"x").title
  in
  let detail_of last_error =
    (describe ~table_name:"plants" ~payload:(`Assoc []) ~last_error).detail
  in
  let str = Alcotest.string in
  [
    Alcotest.test_case "every table of Synced.all has a title of its own" `Quick
      (fun () ->
        List.iter
          (fun (Synced.Any t) ->
            let name = Synced.name t in
            Alcotest.(check bool)
              (name ^ ": not the bare table name")
              false
              (String.equal name (title_of name (`Assoc []))))
          Synced.all);
    Alcotest.test_case "one case per table: plants, tags" `Quick (fun () ->
        Alcotest.check str "plants" "Plante « Digitale »"
          (title_of "plants" (`Assoc [("display_name", `String "Digitale")]));
        Alcotest.check str "tags" "Étiquette « Forêt »"
          (title_of "tags" (`Assoc [("name", `String "Forêt")])));
    Alcotest.test_case "one case per table: observations, photos" `Quick
      (fun () ->
        Alcotest.check str "observations" "Observation"
          (title_of "observations" (`Assoc []));
        Alcotest.check str "photos" "Photo" (title_of "photos" (`Assoc [])));
    Alcotest.test_case "one case per table: plant_tags, plant_refs" `Quick
      (fun () ->
        Alcotest.check str "plant_tags" "Étiquette d’une plante"
          (title_of "plant_tags" (`Assoc []));
        Alcotest.check str "plant_refs" "Lien de référence"
          (title_of "plant_refs" (`Assoc [])));
    Alcotest.test_case
      "one case per table: reference, with and without a source" `Quick
      (fun () ->
        Alcotest.check str "reference with source" "Référence gbif"
          (title_of "reference" (`Assoc [("source", `String "gbif")]));
        Alcotest.check str "reference without source" "Référence"
          (title_of "reference" (`Assoc [])));
    Alcotest.test_case "a plant payload without display_name is the bare label"
      `Quick (fun () ->
        Alcotest.check str "missing field" "Plante"
          (title_of "plants" (`Assoc []));
        Alcotest.check str "non-string field" "Plante"
          (title_of "plants" (`Assoc [("display_name", `Int 1)])));
    Alcotest.test_case "an unknown table is the table name" `Quick (fun () ->
        Alcotest.check str "unknown" "widgets" (title_of "widgets" (`Assoc [])));
    Alcotest.test_case "the three last_error shapes" `Quick (fun () ->
        Alcotest.check str "HTTP <n>" "Refusée par le serveur (409)"
          (detail_of "HTTP 409");
        Alcotest.check str "invalid entry: …" "Entrée illisible"
          (detail_of "invalid entry: unknown table nope");
        Alcotest.check str "anything else: the text as is" "offline: boom"
          (detail_of "offline: boom"));
    Alcotest.test_case "last_error boundaries are the text as is" `Quick
      (fun () ->
        Alcotest.check str "HTTP <n> and more" "HTTP 409 conflict"
          (detail_of "HTTP 409 conflict");
        Alcotest.check str "HTTP and no status" "HTTP " (detail_of "HTTP "));
    Alcotest.test_case "a payload that is no object is the bare label" `Quick
      (fun () ->
        Alcotest.check str "plants, null" "Plante" (title_of "plants" `Null);
        Alcotest.check str "reference, list" "Référence"
          (title_of "reference" (`List [])));
  ]
