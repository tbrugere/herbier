(* France_text: 4m « Toute la France » texts and the mobile-data warning
   rule. Every example of france_text.mli exactly, plus the boundaries
   (estimate ~todo:1, warn_mobile at the threshold, retrying's second
   rounding and each reason, delete_all_question ~count:1,
   progress ~current:None). notification: the background service's title,
   pluralised on total, including total = 0 (singular, as complete's
   downloaded = 0 case below); notice: what that notification shows, with
   and without a cancel asked. *)

module France_text = Herbier_ui_model.France_text

(* ---------- fixed strings ---------- *)

let fixed_strings =
  Alcotest.test_case
    "button, loading, retry, no_departements, background_note, start, dismiss, \
     interrupt, cancelling, delete_all, delete_all_note are fixed strings"
    `Quick (fun () ->
      Alcotest.(check string) "button" "Toute la France" France_text.button;
      Alcotest.(check string) "loading" "Chargement\u{2026}" France_text.loading;
      Alcotest.(check string) "retry" "Réessayer" France_text.retry;
      Alcotest.(check string)
        "no_departements" "Aucun département reçu de l\u{2019}IGN."
        France_text.no_departements;
      Alcotest.(check string)
        "background_note"
        "Le téléchargement continue en arrière-plan ; vous pourrez \
         l\u{2019}interrompre et le reprendre."
        France_text.background_note;
      Alcotest.(check string) "start" "Télécharger" France_text.start;
      Alcotest.(check string) "dismiss" "Annuler" France_text.dismiss;
      Alcotest.(check string) "interrupt" "Interrompre" France_text.interrupt;
      Alcotest.(check string)
        "cancelling" "Interruption après le département en cours\u{2026}"
        France_text.cancelling;
      Alcotest.(check string)
        "delete_all" "Supprimer tout" France_text.delete_all;
      Alcotest.(check string)
        "delete_all_note" "Les noms déjà donnés aux observations restent."
        France_text.delete_all_note;
      Alcotest.(check int) "large_bytes" 10_000_000 France_text.large_bytes)

(* ---------- scope ---------- *)

let scope =
  Alcotest.test_case "scope: the outre-mer list, Fr_text.plural on total" `Quick
    (fun () ->
      Alcotest.(check string)
        "101"
        "Métropole, Corse et outre-mer (Guadeloupe, Martinique, Guyane, La \
         Réunion, Mayotte) : 101 départements."
        (France_text.scope ~total:101))

(* ---------- estimate ---------- *)

let estimate =
  Alcotest.test_case "estimate: todo = 0, todo = total, else, and todo = 1"
    `Quick (fun () ->
      Alcotest.(check string)
        "todo = 0" "Tous les départements sont déjà téléchargés."
        (France_text.estimate ~total:101 ~todo:0 ~bytes:0);
      Alcotest.(check string)
        "todo = total" "101 départements · environ 52,9 Mo"
        (France_text.estimate ~total:101 ~todo:101 ~bytes:52_900_000);
      Alcotest.(check string)
        "else" "96 à télécharger sur 101 · environ 50,4 Mo"
        (France_text.estimate ~total:101 ~todo:96 ~bytes:50_400_000);
      Alcotest.(check string)
        "todo = 1" "1 à télécharger sur 101 · environ 89 ko"
        (France_text.estimate ~total:101 ~todo:1 ~bytes:89_000))

(* ---------- warn_mobile ---------- *)

let warn_mobile =
  Alcotest.test_case
    "true on cellular at exactly large_bytes, false just under, false on Wi-Fi \
     for any size"
    `Quick (fun () ->
      Alcotest.(check bool)
        "cellular, exactly 10_000_000" true
        (France_text.warn_mobile ~cellular:true ~bytes:10_000_000);
      Alcotest.(check bool)
        "cellular, 9_999_999" false
        (France_text.warn_mobile ~cellular:true ~bytes:9_999_999);
      List.iter
        (fun bytes ->
          Alcotest.(check bool)
            (Printf.sprintf "wifi, %d bytes" bytes)
            false
            (France_text.warn_mobile ~cellular:false ~bytes))
        [0; 9_999_999; 10_000_000; 1_000_000_000])

let mobile_warning =
  Alcotest.test_case "mobile_warning: Fr_text.size of bytes" `Quick (fun () ->
      Alcotest.(check string)
        "65,7 Mo"
        "Connexion par données mobiles : environ 65,7 Mo seront téléchargés."
        (France_text.mobile_warning ~bytes:65_700_000))

(* ---------- progress ---------- *)

let progress =
  Alcotest.test_case "progress: with and without current" `Quick (fun () ->
      Alcotest.(check string)
        "with current" "37 / 101 · 12,4 Mo sur environ 52,9 Mo · Haut-Rhin"
        (France_text.progress ~position:37 ~total:101 ~bytes:12_400_000
           ~estimate:52_900_000 ~current:(Some "Haut-Rhin"));
      Alcotest.(check string)
        "current = None drops the \" · <current>\""
        "37 / 101 · 12,4 Mo sur environ 52,9 Mo"
        (France_text.progress ~position:37 ~total:101 ~bytes:12_400_000
           ~estimate:52_900_000 ~current:None))

(* ---------- retrying ---------- *)

let retrying =
  Alcotest.test_case
    "retrying: wait_ms rounded up to seconds, attempt/attempts shown" `Quick
    (fun () ->
      Alcotest.(check string)
        "20 s, 2/3"
        "Haut-Rhin : service indisponible, nouvel essai dans 20 s (2/3)."
        (France_text.retrying ~current:"Haut-Rhin" ~reason:Unavailable
           ~attempt:2 ~attempts:3 ~wait_ms:20_000);
      Alcotest.(check string)
        "wait_ms = 5000 rounds to 5 s"
        "Haut-Rhin : service indisponible, nouvel essai dans 5 s (1/3)."
        (France_text.retrying ~current:"Haut-Rhin" ~reason:Unavailable
           ~attempt:1 ~attempts:3 ~wait_ms:5_000);
      Alcotest.(check string)
        "wait_ms = 4001 also rounds up to 5 s"
        "Haut-Rhin : service indisponible, nouvel essai dans 5 s (1/3)."
        (France_text.retrying ~current:"Haut-Rhin" ~reason:Unavailable
           ~attempt:1 ~attempts:3 ~wait_ms:4_001);
      List.iter
        (fun (reason, text) ->
          Alcotest.(check string)
            text
            (Printf.sprintf "Haut-Rhin : %s, nouvel essai dans 5 s (1/3)." text)
            (France_text.retrying ~current:"Haut-Rhin" ~reason ~attempt:1
               ~attempts:3 ~wait_ms:5_000))
        [
          (France_text.Connection_lost, "connexion perdue");
          (Timed_out, "délai dépassé");
          (Unavailable, "service indisponible");
          (Bad_answer, "réponse invalide");
        ])

(* ---------- complete / cancelled / stopped ---------- *)

let complete =
  Alcotest.test_case
    "complete: no failures, some failures (joined titles), downloaded = 0"
    `Quick (fun () ->
      Alcotest.(check string)
        "no failures" "Terminé : 96 départements · 50,4 Mo."
        (France_text.complete ~downloaded:96 ~bytes:50_400_000 ~failed:[]);
      Alcotest.(check string)
        "some failures"
        "Terminé : 94 départements · 49,5 Mo. Non téléchargés : 2A · \
         Corse-du-Sud, 973 · Guyane. Relancez « Toute la France » pour \
         réessayer."
        (France_text.complete ~downloaded:94 ~bytes:49_500_000
           ~failed:["2A · Corse-du-Sud"; "973 · Guyane"]);
      Alcotest.(check string)
        "downloaded = 0 keeps the singular plural rule"
        "Terminé : 0 département · 0 o."
        (France_text.complete ~downloaded:0 ~bytes:0 ~failed:[]))

let cancelled =
  Alcotest.test_case "cancelled: position / total" `Quick (fun () ->
      Alcotest.(check string)
        "37 / 101"
        "Interrompu à 37 / 101. Relancez « Toute la France » pour reprendre."
        (France_text.cancelled ~position:37 ~total:101))

let stopped =
  Alcotest.test_case "stopped: position / total and the reason, verbatim" `Quick
    (fun () ->
      Alcotest.(check string)
        "37 / 101"
        "Arrêté à 37 / 101 : Hors-ligne : réessayez une fois connecté. \
         Relancez « Toute la France » pour reprendre."
        (France_text.stopped ~position:37 ~total:101
           ~reason:"Hors-ligne : réessayez une fois connecté."))

(* ---------- summary / delete_all_question ---------- *)

let summary =
  Alcotest.test_case "summary: count and Fr_text.size of bytes" `Quick
    (fun () ->
      Alcotest.(check string)
        "12 départements · 4,1 Mo" "12 départements · 4,1 Mo"
        (France_text.summary ~count:12 ~bytes:4_100_000))

let delete_all_question =
  Alcotest.test_case "delete_all_question: plural count, singular count = 1"
    `Quick (fun () ->
      Alcotest.(check string)
        "count = 12" "Supprimer les 12 départements (4,1 Mo) ?"
        (France_text.delete_all_question ~count:12 ~bytes:4_100_000);
      Alcotest.(check string)
        "count = 1" "Supprimer le département (89 ko) ?"
        (France_text.delete_all_question ~count:1 ~bytes:89_000))

(* ---------- notification ---------- *)

let notification =
  Alcotest.test_case
    "notification: \"IGN hors-ligne : position / total départements\", \
     pluralised on total, including total = 0"
    `Quick (fun () ->
      Alcotest.(check string)
        "37 / 101" "IGN hors-ligne : 37 / 101 départements"
        (France_text.notification ~position:37 ~total:101);
      Alcotest.(check string)
        "0 / 1 (singular)" "IGN hors-ligne : 0 / 1 département"
        (France_text.notification ~position:0 ~total:1);
      Alcotest.(check string)
        "1 / 1 (singular)" "IGN hors-ligne : 1 / 1 département"
        (France_text.notification ~position:1 ~total:1);
      Alcotest.(check string)
        "101 / 101" "IGN hors-ligne : 101 / 101 départements"
        (France_text.notification ~position:101 ~total:101);
      Alcotest.(check string)
        "0 / 0 keeps the singular plural rule"
        "IGN hors-ligne : 0 / 0 département"
        (France_text.notification ~position:0 ~total:0))

let string_of_notice ({title; text; value; max; action} : France_text.notice) =
  let opt = Option.value ~default:"-" in
  Printf.sprintf "%s | %s | %d/%d | %s" title (opt text) value max (opt action)

let notice =
  Alcotest.test_case
    "notice: progress and « Interrompre »; a cancel asked shows its text and \
     no action"
    `Quick (fun () ->
      Alcotest.(check string)
        "running"
        "IGN hors-ligne : 37 / 101 départements | - | 37/101 | Interrompre"
        (string_of_notice
           (France_text.notice ~position:37 ~total:101 ~cancelling:false));
      Alcotest.(check string)
        "cancelling"
        "IGN hors-ligne : 38 / 101 départements | Interruption après le \
         département en cours… | 38/101 | -"
        (string_of_notice
           (France_text.notice ~position:38 ~total:101 ~cancelling:true)))

let france_text =
  [
    fixed_strings;
    scope;
    estimate;
    warn_mobile;
    mobile_warning;
    progress;
    retrying;
    complete;
    cancelled;
    stopped;
    summary;
    delete_all_question;
    notification;
    notice;
  ]
