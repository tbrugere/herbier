module Ref_search = Herbier_ui_model.Ref_search
module Resolve = Herbier_refs.Resolve
module Network_text = Herbier_ui_model.Network_text

let digitalis_taxon = Fixtures.digitalis_taxon
let cand : Resolve.Candidate.t = {taxon = digitalis_taxon; french = []}

(* ---------- banner ---------- *)

let banner_online_is_none () =
  List.iter
    (fun pending ->
      Alcotest.(check (option string))
        (Printf.sprintf "online, pending %d" pending)
        None
        (Network_text.banner ~online:true ~pending))
    [0; 3]

let banner_offline_no_pending () =
  List.iter
    (fun pending ->
      Alcotest.(check (option string))
        (Printf.sprintf "offline, pending %d" pending)
        (Some "hors-ligne")
        (Network_text.banner ~online:false ~pending))
    [0; -1]

let banner_offline_with_pending () =
  Alcotest.(check (option string))
    "pending 1" (Some "hors-ligne · 1 en attente")
    (Network_text.banner ~online:false ~pending:1);
  Alcotest.(check (option string))
    "pending 2" (Some "hors-ligne · 2 en attente")
    (Network_text.banner ~online:false ~pending:2)

let banner =
  [
    Alcotest.test_case "online: None whatever pending is" `Quick
      banner_online_is_none;
    Alcotest.test_case "offline, 0 or negative pending: \"hors-ligne\"" `Quick
      banner_offline_no_pending;
    Alcotest.test_case "offline with pending: \"hors-ligne · <n> en attente\""
      `Quick banner_offline_with_pending;
  ]

(* ---------- unlinked_offline (4g) ---------- *)

let unlinked_offline =
  [
    Alcotest.test_case "online: empty" `Quick (fun () ->
        Alcotest.(check string)
          "online" ""
          (Network_text.unlinked_offline ~online:true));
    Alcotest.test_case "offline: the sentence, leading space" `Quick (fun () ->
        Alcotest.(check string)
          "offline"
          " Hors-ligne : la recherche de noms reviendra avec le réseau."
          (Network_text.unlinked_offline ~online:false));
  ]

(* ---------- search_status (4i) ---------- *)

let search_status =
  [
    Alcotest.test_case "Blank: empty, online or offline" `Quick (fun () ->
        Alcotest.(check string)
          "online" ""
          (Network_text.search_status ~online:true Ref_search.Blank);
        Alcotest.(check string)
          "offline" ""
          (Network_text.search_status ~online:false Ref_search.Blank));
    Alcotest.test_case "Pending: \"Recherche…\"" `Quick (fun () ->
        Alcotest.(check string)
          "online" "Recherche…"
          (Network_text.search_status ~online:true Ref_search.Pending);
        Alcotest.(check string)
          "offline" "Recherche…"
          (Network_text.search_status ~online:false Ref_search.Pending));
    Alcotest.test_case "Found []: \"Aucune espèce trouvée dans GBIF.\"" `Quick
      (fun () ->
        Alcotest.(check string)
          "online" "Aucune espèce trouvée dans GBIF."
          (Network_text.search_status ~online:true (Ref_search.Found []));
        Alcotest.(check string)
          "offline" "Aucune espèce trouvée dans GBIF."
          (Network_text.search_status ~online:false (Ref_search.Found [])));
    Alcotest.test_case
      "Found [c]: empty online, « Hors-ligne : « + » … » offline" `Quick
      (fun () ->
        Alcotest.(check string)
          "online" ""
          (Network_text.search_status ~online:true (Ref_search.Found [cand]));
        Alcotest.(check string)
          "offline" "Hors-ligne : « + » reviendra avec le réseau."
          (Network_text.search_status ~online:false (Ref_search.Found [cand])));
    Alcotest.test_case "Offline: \"Recherche indisponible hors-ligne.\"" `Quick
      (fun () ->
        Alcotest.(check string)
          "offline" "Recherche indisponible hors-ligne."
          (Network_text.search_status ~online:false Ref_search.Offline);
        Alcotest.(check string)
          "online (still the offline text)" "Recherche indisponible hors-ligne."
          (Network_text.search_status ~online:true Ref_search.Offline));
    Alcotest.test_case "Failed _: \"La recherche n'a pas abouti.\"" `Quick
      (fun () ->
        Alcotest.(check string)
          "online" "La recherche n'a pas abouti."
          (Network_text.search_status ~online:true (Ref_search.Failed "m"));
        Alcotest.(check string)
          "offline" "La recherche n'a pas abouti."
          (Network_text.search_status ~online:false (Ref_search.Failed "m")));
  ]

let network_text = banner @ unlinked_offline @ search_status
