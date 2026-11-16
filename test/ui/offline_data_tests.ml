(* Offline_data: 4m's "Données hors-ligne" row (sizes, "Libérer" texts). *)

module Offline_data = Herbier_ui_model.Offline_data

let measured previews reference_photos : Offline_data.state =
  Measured {previews; reference_photos}

(* ---------- detail ---------- *)

let detail =
  [
    Alcotest.test_case "Measuring and Unknown" `Quick (fun () ->
        Alcotest.(check string)
          "measuring" "Aperçus photos … · Photos de référence …"
          (Offline_data.detail Offline_data.Measuring);
        Alcotest.(check string)
          "unknown" "Taille inconnue"
          (Offline_data.detail Offline_data.Unknown));
    Alcotest.test_case "Measured: both sizes, Fr_text.size formatting" `Quick
      (fun () ->
        Alcotest.(check string)
          "48.0 / 12.3 Mo"
          "Aperçus photos 48,0 Mo · Photos de référence 12,3 Mo"
          (Offline_data.detail (measured 48_000_000. 12_300_000.)));
    Alcotest.test_case "Measured {0; 0}" `Quick (fun () ->
        Alcotest.(check string)
          "0 o · 0 o" "Aperçus photos 0 o · Photos de référence 0 o"
          (Offline_data.detail (measured 0. 0.)));
    Alcotest.test_case "Measured past 2^31 bytes" `Quick (fun () ->
        Alcotest.(check string)
          "3 Go" "Aperçus photos 3000,0 Mo · Photos de référence 2200,0 Mo"
          (Offline_data.detail (measured 3_000_000_000. 2_200_000_000.)));
  ]

(* ---------- can_free ---------- *)

let can_free =
  [
    Alcotest.test_case
      "Measuring and Unknown: false; Measured depends on reference_photos > 0"
      `Quick (fun () ->
        Alcotest.(check bool)
          "measuring" false
          (Offline_data.can_free Offline_data.Measuring);
        Alcotest.(check bool)
          "unknown" false
          (Offline_data.can_free Offline_data.Unknown);
        Alcotest.(check bool)
          "reference_photos = 0" false
          (Offline_data.can_free (measured 1_000. 0.));
        Alcotest.(check bool)
          "reference_photos = 1" true
          (Offline_data.can_free (measured 1_000. 1.)));
  ]

(* ---------- confirm dialog and free_failure_text ---------- *)

let dialog_texts =
  [
    Alcotest.test_case "confirm_title, confirm_text" `Quick (fun () ->
        Alcotest.(check string)
          "title" "Libérer les photos de référence ?" Offline_data.confirm_title;
        Alcotest.(check string)
          "text"
          "Elles seront retéléchargées à l\u{2019}ouverture de chaque fiche, \
           avec le réseau. Vos photos et vos fiches restent."
          Offline_data.confirm_text);
  ]

let free_failure_text =
  [
    Alcotest.test_case "each constructor's text" `Quick (fun () ->
        Alcotest.(check string)
          "Busy"
          "Des photos de référence se téléchargent : réessayez dans un instant."
          (Offline_data.free_failure_text Offline_data.Busy);
        Alcotest.(check string)
          "Failed" "La place n\u{2019}a pas pu être libérée."
          (Offline_data.free_failure_text Offline_data.Failed));
  ]

let freed_text =
  [
    Alcotest.test_case "the bytes freed, formatted" `Quick (fun () ->
        Alcotest.(check string) "0" "0 o libérés." (Offline_data.freed_text 0.);
        Alcotest.(check string)
          "850 000" "850 ko libérés."
          (Offline_data.freed_text 850_000.));
  ]

let freed =
  [
    Alcotest.test_case "Measured smaller after: the difference" `Quick (fun () ->
        Alcotest.(check string)
          "850 ko" "850 ko libérés."
          (Offline_data.freed ~before:900_000. (measured 5_000. 50_000.)));
    Alcotest.test_case "Measured larger after: 0" `Quick (fun () ->
        Alcotest.(check string)
          "0 o" "0 o libérés."
          (Offline_data.freed ~before:1_000. (measured 0. 4_000.)));
    Alcotest.test_case "Measuring and Unknown: all of before" `Quick (fun () ->
        Alcotest.(check string)
          "unknown" "850 ko libérés."
          (Offline_data.freed ~before:850_000. Offline_data.Unknown);
        Alcotest.(check string)
          "measuring" "850 ko libérés."
          (Offline_data.freed ~before:850_000. Offline_data.Measuring));
  ]

let offline_data =
  detail @ can_free @ dialog_texts @ free_failure_text @ freed_text @ freed
