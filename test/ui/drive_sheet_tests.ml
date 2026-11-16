(* app/ui_model/drive_sheet.ml (Herbier_ui_model.Drive_sheet): the pure state
   machine behind 4m's « Dossier Drive » full-screen sheet. Each case checks
   the full returned (t, commands) pair of Drive_sheet.open_/step. *)

module Drive_sheet = Herbier_ui_model.Drive_sheet
module Drive_text = Herbier_ui_model.Drive_text
module Drive_account = Herbier_sync_core.Auth.Drive_account

(* ---------- testables ---------- *)

let t_t = Alcotest.testable Drive_sheet.pp Drive_sheet.equal

let command_t =
  Alcotest.testable Drive_sheet.pp_command Drive_sheet.equal_command

let commands_t = Alcotest.(list command_t)
let step_t = Alcotest.(pair t_t commands_t)
let phase_name p = Drive_sheet.show_phase p

(* ---------- building states ---------- *)

let picker_ready = Drive_text.Picker_ready
let picker_unconfigured = Drive_text.Picker_unconfigured

let state ?(stored = None) ?(folder = Drive_text.Default)
    ?(picker = picker_ready) ?(error = None) phase : Drive_sheet.t =
  {Drive_sheet.stored; folder; picker; phase; error}

(* An Idle sheet whose account is the stored one: the common base below. *)
let idle_with_account =
  state ~stored:(Some "a@x.fr") (Drive_sheet.Idle (Some "a@x.fr"))

let with_phase (t : Drive_sheet.t) phase = {t with Drive_sheet.phase}

(* Every phase but Closed, for a@x.fr. *)
let open_phases =
  Drive_sheet.
    [
      Choosing {previous = Some "a@x.fr"};
      Authorizing "a@x.fr";
      Browsing "a@x.fr";
      Storing "a@x.fr";
      Idle (Some "a@x.fr");
    ]

(* ---------- open_ ---------- *)

let open_tests =
  let case name ~stored expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check step_t "open_" expected
          (Drive_sheet.open_ ~stored ~folder:Drive_text.Default
             ~picker:picker_ready) )
  in
  [
    case "stored = None: Choosing, [Run_chooser]" ~stored:None
      (state (Drive_sheet.Choosing {previous = None}), [Drive_sheet.Run_chooser]);
    case "stored = Some e: Authorizing e, [Ask_token e]" ~stored:(Some "a@x.fr")
      ( state ~stored:(Some "a@x.fr") (Drive_sheet.Authorizing "a@x.fr"),
        [Drive_sheet.Ask_token "a@x.fr"] );
    case "a padded stored account: trimmed" ~stored:(Some " a@x.fr ")
      ( state ~stored:(Some " a@x.fr ") (Drive_sheet.Authorizing "a@x.fr"),
        [Drive_sheet.Ask_token "a@x.fr"] );
    case "a blank stored account: the chooser" ~stored:(Some "  ")
      ( state ~stored:(Some "  ") (Drive_sheet.Choosing {previous = None}),
        [Drive_sheet.Run_chooser] );
  ]

(* ---------- first open, no account ---------- *)

let first_open_cancel_closes_the_sheet () =
  let t0, (_ : Drive_sheet.command list) =
    Drive_sheet.open_ ~stored:None ~folder:Drive_text.Default
      ~picker:picker_ready
  in
  Alcotest.check step_t
    "the first choice was cancelled: Closed, Close, nothing else changed"
    (state Drive_sheet.Closed, [Drive_sheet.Close])
    (Drive_sheet.step t0 (Drive_sheet.Choose_failed Drive_account.Cancelled))

let first_open_success_chain () =
  let t0, (_ : Drive_sheet.command list) =
    Drive_sheet.open_ ~stored:None ~folder:Drive_text.Default
      ~picker:picker_ready
  in
  let t1, cmds1 = Drive_sheet.step t0 (Drive_sheet.Chosen " b@x.fr ") in
  Alcotest.check step_t "Chosen is trimmed"
    (state (Drive_sheet.Authorizing "b@x.fr"), [Drive_sheet.Ask_token "b@x.fr"])
    (t1, cmds1);
  let t2, cmds2 = Drive_sheet.step t1 (Drive_sheet.Token (Ok "tok")) in
  Alcotest.check step_t "Token Ok, Picker_ready: Browsing, Open_picker"
    ( state (Drive_sheet.Browsing "b@x.fr"),
      [Drive_sheet.Open_picker {account = "b@x.fr"; token = "tok"}] )
    (t2, cmds2);
  let t3, cmds3 =
    Drive_sheet.step t2
      (Drive_sheet.Picker_picked {id = "f1"; name = "Plantes"})
  in
  Alcotest.check step_t "Picker_picked: Storing, Store_pick"
    ( state (Drive_sheet.Storing "b@x.fr"),
      [
        Drive_sheet.Store_pick
          {account = "b@x.fr"; folder_id = "f1"; folder_name = "Plantes"};
      ] )
    (t3, cmds3);
  Alcotest.check step_t "Stored Ok: Closed, Close"
    (state Drive_sheet.Closed, [Drive_sheet.Close])
    (Drive_sheet.step t3 (Drive_sheet.Stored (Ok ())))

let blank_chosen_is_a_failed_choice () =
  let choosing = state (Drive_sheet.Choosing {previous = None}) in
  Alcotest.check step_t "Chosen \"  \": Idle, Chooser_failed"
    (state ~error:(Some Drive_text.Chooser_failed) (Drive_sheet.Idle None), [])
    (Drive_sheet.step choosing (Drive_sheet.Chosen "  "))

let first_choice_refused_keeps_nothing () =
  let authorizing = state (Drive_sheet.Authorizing "b@x.fr") in
  Alcotest.check step_t
    "nothing stored, Token Error: Idle None, the token error itself"
    ( state ~error:(Some (Drive_text.Token Drive_text.Consent_refused))
        (Drive_sheet.Idle None),
      [] )
    (Drive_sheet.step authorizing
       (Drive_sheet.Token (Error Drive_text.Consent_refused)))

let first_open_tests =
  [
    ( "no account yet, the first cancel closes the sheet",
      `Quick,
      first_open_cancel_closes_the_sheet );
    ( "no account yet, choose, authorize, pick a folder, store: the full chain",
      `Quick,
      first_open_success_chain );
    ( "a blank choice is a failed choice",
      `Quick,
      blank_chosen_is_a_failed_choice );
    ( "the first account refused: no account kept",
      `Quick,
      first_choice_refused_keeps_nothing );
  ]

(* ---------- switching account ---------- *)

let switching_account () =
  let t1, cmds1 =
    Drive_sheet.step idle_with_account Drive_sheet.Tap_other_account
  in
  Alcotest.check step_t "Tap_other_account: Choosing, Run_chooser"
    ( with_phase idle_with_account
        (Drive_sheet.Choosing {previous = Some "a@x.fr"}),
      [Drive_sheet.Run_chooser] )
    (t1, cmds1);
  let t2, cmds2 =
    Drive_sheet.step t1 (Drive_sheet.Choose_failed Drive_account.Cancelled)
  in
  Alcotest.check step_t
    "cancelling while an account is chosen: back to Idle with that account"
    (idle_with_account, []) (t2, cmds2);
  let t2', (_ : Drive_sheet.command list) =
    Drive_sheet.step t2 Drive_sheet.Tap_other_account
  in
  let t3, cmds3 = Drive_sheet.step t2' (Drive_sheet.Chosen "c@x.fr") in
  Alcotest.check step_t "choosing another account: Authorizing, Ask_token"
    ( with_phase idle_with_account (Drive_sheet.Authorizing "c@x.fr"),
      [Drive_sheet.Ask_token "c@x.fr"] )
    (t3, cmds3);
  let (_ : Drive_sheet.t), cmds4 =
    Drive_sheet.step t3 (Drive_sheet.Token (Ok "tok2"))
  in
  Alcotest.check commands_t
    "the next Open_picker names the newly chosen account"
    [Drive_sheet.Open_picker {account = "c@x.fr"; token = "tok2"}]
    cmds4

(* A token refused for the new account: back to the stored one, so that
   « Par défaut » cannot then store an account Drive refuses. *)
let refused_new_account_goes_back_to_the_stored_one () =
  let authorizing =
    with_phase idle_with_account (Drive_sheet.Authorizing "c@x.fr")
  in
  let idle, cmds =
    Drive_sheet.step authorizing
      (Drive_sheet.Token (Error Drive_text.Consent_refused))
  in
  Alcotest.check step_t "Idle with the stored account, Other_account error"
    ( {
        idle_with_account with
        Drive_sheet.error =
          Some (Drive_text.Other_account Drive_text.Consent_refused);
      },
      [] )
    (idle, cmds);
  Alcotest.check step_t "Tap_default then: nothing (same account, Default)"
    (idle, [])
    (Drive_sheet.step idle Drive_sheet.Tap_default)

let tap_default_for_a_new_account_stores_it () =
  let idle =
    with_phase idle_with_account (Drive_sheet.Idle (Some "new@x.fr"))
  in
  Alcotest.check step_t "Tap_default: Storing new, Store_default new"
    ( with_phase idle (Drive_sheet.Storing "new@x.fr"),
      [Drive_sheet.Store_default "new@x.fr"] )
    (Drive_sheet.step idle Drive_sheet.Tap_default)

let switching_account_tests =
  [
    ("switching account, step by step", `Quick, switching_account);
    ( "a refused new account goes back to the stored one",
      `Quick,
      refused_new_account_goes_back_to_the_stored_one );
    ( "« Par défaut » for a new account stores it",
      `Quick,
      tap_default_for_a_new_account_stores_it );
  ]

(* ---------- cancelling changes nothing ---------- *)

let tap_close_from_every_phase_closes_without_storing () =
  List.iter
    (fun phase ->
      let base = with_phase idle_with_account phase in
      Alcotest.check step_t
        (Printf.sprintf "Tap_close from %s" (phase_name phase))
        (with_phase base Drive_sheet.Closed, [Drive_sheet.Close])
        (Drive_sheet.step base Drive_sheet.Tap_close))
    open_phases

(* A store already running completes; its result is then ignored. *)
let tap_close_while_storing_ignores_the_result () =
  let storing = with_phase idle_with_account (Drive_sheet.Storing "a@x.fr") in
  let closed, (_ : Drive_sheet.command list) =
    Drive_sheet.step storing Drive_sheet.Tap_close
  in
  List.iter
    (fun result ->
      Alcotest.check step_t "Stored after Tap_close: unchanged, no command"
        (closed, [])
        (Drive_sheet.step closed (Drive_sheet.Stored result)))
    [Ok (); Error Drive_text.Not_saved]

let is_store_command (c : Drive_sheet.command) =
  match c with
  | Store_pick _ | Store_default _ -> true
  | Run_chooser | Ask_token _ | Open_picker _ | Close -> false

(* Every event but Picker_picked and Tap_default (the only two that may
   store), against every phase: none produces a Store_* command. *)
let non_storing_events =
  Drive_sheet.
    [
      Tap_other_account;
      Tap_browse;
      Tap_close;
      Chosen "x@x.fr";
      Choose_failed Drive_account.Cancelled;
      Choose_failed Drive_account.No_google_account;
      Choose_failed Drive_account.Choose_failed;
      Token (Ok "tok");
      Token (Error Drive_text.Consent_refused);
      Picker_cancelled;
      Picker_failed Drive_text.Picker_unavailable;
      Stored (Ok ());
      Stored (Error Drive_text.Not_saved);
    ]

let no_store_command_without_picker_picked_or_tap_default () =
  List.iter
    (fun phase ->
      List.iter
        (fun event ->
          let (_ : Drive_sheet.t), cmds =
            Drive_sheet.step (with_phase idle_with_account phase) event
          in
          Alcotest.(check bool)
            (Printf.sprintf "%s, %s: no Store_* command" (phase_name phase)
               (Drive_sheet.show_event event))
            false
            (List.exists is_store_command cmds))
        non_storing_events)
    (Drive_sheet.Closed :: open_phases)

let cancelling_tests =
  [
    ( "Tap_close from every phase closes the sheet, without storing anything",
      `Quick,
      tap_close_from_every_phase_closes_without_storing );
    ( "Tap_close while storing: the store's result is ignored",
      `Quick,
      tap_close_while_storing_ignores_the_result );
    ( "no path other than Picker_picked or Tap_default ever emits a Store_* \
       command",
      `Quick,
      no_store_command_without_picker_picked_or_tap_default );
  ]

(* ---------- Picker_unconfigured ---------- *)

let picker_unconfigured_note =
  "Choix du dossier indisponible dans cette version : les photos vont dans « \
   Herbier »."

let picker_unconfigured_cases () =
  (* folder = Picked, so that can_default is true below: « Par défaut » still
     works when the Picker is unconfigured. *)
  let authorizing =
    state ~stored:(Some "a@x.fr") ~folder:(Drive_text.Picked "Mes plantes")
      ~picker:picker_unconfigured (Drive_sheet.Authorizing "a@x.fr")
  in
  let idle, cmds =
    Drive_sheet.step authorizing (Drive_sheet.Token (Ok "tok"))
  in
  Alcotest.check step_t "Token Ok, Picker_unconfigured: Idle, no command"
    (with_phase authorizing (Drive_sheet.Idle (Some "a@x.fr")), [])
    (idle, cmds);
  Alcotest.(check bool)
    "can_browse is false" false
    (Drive_sheet.can_browse idle);
  Alcotest.(check (option string))
    "picker_note says why" (Some picker_unconfigured_note)
    (Drive_sheet.picker_note idle);
  Alcotest.check step_t "Tap_default still works: Storing, Store_default"
    ( with_phase idle (Drive_sheet.Storing "a@x.fr"),
      [Drive_sheet.Store_default "a@x.fr"] )
    (Drive_sheet.step idle Drive_sheet.Tap_default)

let picker_unconfigured_tests =
  [
    ( "Picker_unconfigured: no browsing, the note, « Par défaut » still works",
      `Quick,
      picker_unconfigured_cases );
  ]

(* ---------- can_default ---------- *)

let can_default_tests =
  let case name t expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check bool) "can_default" expected (Drive_sheet.can_default t)
    )
  in
  let idle ~stored ?(folder = Drive_text.Default) account =
    state ~stored ~folder (Drive_sheet.Idle account)
  in
  [
    case "same account, folder Default: false"
      (idle ~stored:(Some "a@x.fr") (Some "a@x.fr"))
      false;
    case "same account, folder Picked: true"
      (idle ~stored:(Some "a@x.fr") ~folder:(Drive_text.Picked "Mes plantes")
         (Some "a@x.fr"))
      true;
    case "the same account up to case and spaces, folder Default: false"
      (idle ~stored:(Some " A@X.fr") (Some "a@x.FR "))
      false;
    case "a different account, folder Default: true"
      (idle ~stored:(Some "a@x.fr") (Some "new@x.fr"))
      true;
    case "nothing stored yet, folder Default: true"
      (idle ~stored:None (Some "new@x.fr"))
      true;
    case "no account: false"
      (idle ~stored:None ~folder:(Drive_text.Picked "Mes plantes") None)
      false;
    case "not Idle: false"
      (state ~stored:(Some "a@x.fr") (Drive_sheet.Authorizing "new@x.fr"))
      false;
  ]

(* ---------- errors ---------- *)

let error_sets_and_is_cleared_by_the_next_tap () =
  let authorizing =
    with_phase idle_with_account (Drive_sheet.Authorizing "a@x.fr")
  in
  Alcotest.check step_t "Token Error for the stored account: Token d"
    ( {
        idle_with_account with
        Drive_sheet.error = Some (Drive_text.Token Drive_text.Consent_refused);
      },
      [] )
    (Drive_sheet.step authorizing
       (Drive_sheet.Token (Error Drive_text.Consent_refused)));
  let choosing =
    with_phase idle_with_account
      (Drive_sheet.Choosing {previous = Some "a@x.fr"})
  in
  Alcotest.check step_t
    "Choose_failed No_google_account: Idle previous, Chooser_no_account"
    ( {
        idle_with_account with
        Drive_sheet.error = Some Drive_text.Chooser_no_account;
      },
      [] )
    (Drive_sheet.step choosing
       (Drive_sheet.Choose_failed Drive_account.No_google_account));
  Alcotest.check step_t
    "Choose_failed Choose_failed: Idle previous, Chooser_failed"
    ( {idle_with_account with Drive_sheet.error = Some Drive_text.Chooser_failed},
      [] )
    (Drive_sheet.step choosing
       (Drive_sheet.Choose_failed Drive_account.Choose_failed));
  let browsing = with_phase idle_with_account (Drive_sheet.Browsing "a@x.fr") in
  Alcotest.check step_t "Picker_failed: Idle with that error"
    ( {
        idle_with_account with
        Drive_sheet.error = Some Drive_text.Picker_unavailable;
      },
      [] )
    (Drive_sheet.step browsing
       (Drive_sheet.Picker_failed Drive_text.Picker_unavailable));
  let storing = with_phase idle_with_account (Drive_sheet.Storing "a@x.fr") in
  let with_error, cmds =
    Drive_sheet.step storing (Drive_sheet.Stored (Error Drive_text.Not_saved))
  in
  Alcotest.check step_t "Stored (Error Not_saved): Idle, Not_saved"
    ({idle_with_account with Drive_sheet.error = Some Drive_text.Not_saved}, [])
    (with_error, cmds);
  Alcotest.check step_t "the next tap acted on clears the error"
    ( with_phase idle_with_account
        (Drive_sheet.Choosing {previous = Some "a@x.fr"}),
      [Drive_sheet.Run_chooser] )
    (Drive_sheet.step with_error Drive_sheet.Tap_other_account)

let error_tests =
  [
    ( "Token/Choose_failed/Picker_failed/Stored errors land in [error]",
      `Quick,
      error_sets_and_is_cleared_by_the_next_tap );
  ]

(* ---------- stray events ---------- *)

let stray_events_are_ignored () =
  let idle = idle_with_account in
  Alcotest.check step_t "Token _ in Idle: unchanged" (idle, [])
    (Drive_sheet.step idle (Drive_sheet.Token (Ok "tok")));
  let browsing = with_phase idle (Drive_sheet.Browsing "a@x.fr") in
  Alcotest.check step_t "Stored _ in Browsing: unchanged" (browsing, [])
    (Drive_sheet.step browsing (Drive_sheet.Stored (Ok ())));
  let closed = with_phase idle Drive_sheet.Closed in
  List.iter
    (fun event ->
      Alcotest.check step_t "any event once Closed: unchanged" (closed, [])
        (Drive_sheet.step closed event))
    Drive_sheet.
      [
        Tap_other_account;
        Tap_browse;
        Tap_default;
        Tap_close;
        Chosen "x@x.fr";
        Token (Ok "tok");
        Picker_cancelled;
        Stored (Ok ());
      ];
  let authorizing = with_phase idle (Drive_sheet.Authorizing "a@x.fr") in
  Alcotest.check step_t "Tap_browse while Authorizing: unchanged"
    (authorizing, [])
    (Drive_sheet.step authorizing Drive_sheet.Tap_browse)

let stray_events_tests =
  [
    ( "stray events leave the state and commands unchanged",
      `Quick,
      stray_events_are_ignored );
  ]

(* ---------- the remaining transitions of step ---------- *)

let remaining_step_tests =
  let case name f = (name, `Quick, f) in
  [
    case "Tap_browse when can_browse: Authorizing, Ask_token, error cleared"
      (fun () ->
        Alcotest.check step_t "step"
          ( with_phase idle_with_account (Drive_sheet.Authorizing "a@x.fr"),
            [Drive_sheet.Ask_token "a@x.fr"] )
          (Drive_sheet.step
             {
               idle_with_account with
               Drive_sheet.error = Some Drive_text.Not_saved;
             }
             Drive_sheet.Tap_browse));
    case "Tap_browse without the Picker: unchanged" (fun () ->
        let idle =
          {idle_with_account with Drive_sheet.picker = picker_unconfigured}
        in
        Alcotest.check step_t "step" (idle, [])
          (Drive_sheet.step idle Drive_sheet.Tap_browse));
    case "Tap_default that would change nothing: unchanged" (fun () ->
        Alcotest.check step_t "step" (idle_with_account, [])
          (Drive_sheet.step idle_with_account Drive_sheet.Tap_default));
    case "Picker_cancelled in Browsing: Idle, no command" (fun () ->
        Alcotest.check step_t "step" (idle_with_account, [])
          (Drive_sheet.step
             (with_phase idle_with_account (Drive_sheet.Browsing "a@x.fr"))
             Drive_sheet.Picker_cancelled));
  ]

(* ---------- texts ---------- *)

let account_line_tests =
  [
    ( "an account: « Compte : <email> »",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "account_line" "Compte : a@x.fr"
          (Drive_sheet.account_line idle_with_account) );
    ( "no account: « Aucun compte choisi »",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "account_line" "Aucun compte choisi"
          (Drive_sheet.account_line (state (Drive_sheet.Idle None))) );
    ( "while choosing: the account before the chooser",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "account_line" "Compte : a@x.fr"
          (Drive_sheet.account_line
             (state (Drive_sheet.Choosing {previous = Some "a@x.fr"}))) );
  ]

let other_account_label_tests =
  [
    ( "an account: « Utiliser un autre compte »",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "other_account_label" "Utiliser un autre compte"
          (Drive_sheet.other_account_label idle_with_account) );
    ( "no account: « Choisir un compte »",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "other_account_label" "Choisir un compte"
          (Drive_sheet.other_account_label (state (Drive_sheet.Idle None))) );
  ]

(* The folder line follows the sheet's account: another account's folder is
   its « Herbier », not the stored account's pick. *)
let folder_line_tests =
  let case name t expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "folder_line" expected
          (Drive_sheet.folder_line t) )
  in
  let picked = Drive_text.Picked "Mes plantes" in
  [
    case "the stored account, a pick: its name"
      (state ~stored:(Some "a@x.fr") ~folder:picked
         (Drive_sheet.Idle (Some "A@x.fr")))
      (Some "Dossier : Mes plantes");
    case "the stored account, Default: the app's folder" idle_with_account
      (Some ("Dossier : " ^ Drive_text.app_folder));
    case "another account: its own « Herbier », not the stored pick"
      (state ~stored:(Some "a@x.fr") ~folder:picked
         (Drive_sheet.Idle (Some "new@x.fr")))
      (Some ("Dossier : " ^ Drive_text.app_folder));
    case "no account: no line" (state (Drive_sheet.Idle None)) None;
  ]

let status_line_tests =
  let case phase expected =
    ( Printf.sprintf "%s" (phase_name phase),
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "status_line" expected
          (Drive_sheet.status_line (with_phase idle_with_account phase)) )
  in
  Drive_sheet.
    [
      case (Choosing {previous = None}) None;
      case (Authorizing "a@x.fr") (Some "Connexion à Google Drive…");
      case (Browsing "a@x.fr") (Some "Ouverture de Google Drive…");
      case (Storing "a@x.fr") (Some "Enregistrement…");
      case (Idle (Some "a@x.fr")) None;
      case Closed None;
    ]

let picker_title_tests =
  [
    ( "« Dossier Drive · <email> »",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "picker_title" "Dossier Drive · a@x.fr"
          (Drive_sheet.picker_title "a@x.fr") );
  ]

(* The printers never show a Drive access token. *)
let printer_tests =
  [
    ( "Open_picker and Token print <token>",
      `Quick,
      fun () ->
        let shown =
          Drive_sheet.show_command
            (Open_picker {account = "a@x.fr"; token = "secret-tok"})
          ^ Drive_sheet.show_event (Token (Ok "secret-tok"))
        in
        Alcotest.(check bool)
          "no token" false
          (Herbier_test_support.Text.contains ~sub:"secret-tok" shown) );
  ]

(* ---------- can_browse, busy ---------- *)

let can_browse_tests =
  let case name t expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check bool) "can_browse" expected (Drive_sheet.can_browse t)
    )
  in
  [
    case "Idle, an account, Picker_ready: true" idle_with_account true;
    case "Idle, no account: false" (state (Drive_sheet.Idle None)) false;
    case "Idle, an account, Picker_unconfigured: false"
      {idle_with_account with Drive_sheet.picker = picker_unconfigured}
      false;
    case "Authorizing: false"
      (with_phase idle_with_account (Drive_sheet.Authorizing "a@x.fr"))
      false;
  ]

let busy_tests =
  let case phase expected =
    ( Printf.sprintf "%s: %b" (phase_name phase) expected,
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "busy" expected
          (Drive_sheet.busy (with_phase idle_with_account phase)) )
  in
  Drive_sheet.
    [
      case (Choosing {previous = None}) true;
      case (Authorizing "a@x.fr") true;
      case (Browsing "a@x.fr") true;
      case (Storing "a@x.fr") true;
      case (Idle None) false;
      case Closed false;
    ]

let tests =
  List.concat
    [
      open_tests;
      first_open_tests;
      switching_account_tests;
      cancelling_tests;
      picker_unconfigured_tests;
      can_default_tests;
      error_tests;
      stray_events_tests;
      remaining_step_tests;
      account_line_tests;
      other_account_label_tests;
      folder_line_tests;
      status_line_tests;
      picker_title_tests;
      printer_tests;
      can_browse_tests;
      busy_tests;
    ]
