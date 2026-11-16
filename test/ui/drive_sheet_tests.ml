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

let state ?(purpose = Drive_sheet.Change) ?(stored = None)
    ?(folder = Drive_text.Default) ?(picker = picker_ready) ?(error = None)
    phase : Drive_sheet.t =
  {Drive_sheet.purpose; stored; folder; picker; phase; error}

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

(* [Change] opens the same way with or without the Picker: without it, the
   sheet still chooses the account. *)
let open_tests =
  List.concat_map
    (fun picker ->
      let case name ~stored phase commands =
        ( Printf.sprintf "%s (%s)" name (Drive_text.show_picker_config picker),
          `Quick,
          fun () ->
            Alcotest.check step_t "open_"
              (state ~stored ~picker phase, commands)
              (Drive_sheet.open_ ~purpose:Drive_sheet.Change ~stored
                 ~folder:Drive_text.Default ~picker) )
      in
      [
        case "stored = None: Choosing, [Run_chooser]" ~stored:None
          (Drive_sheet.Choosing {previous = None})
          [Drive_sheet.Run_chooser];
        case "stored = Some e: Authorizing e, [Ask_token e]"
          ~stored:(Some "a@x.fr") (Drive_sheet.Authorizing "a@x.fr")
          [Drive_sheet.Ask_token "a@x.fr"];
        case "a padded stored account: trimmed" ~stored:(Some " a@x.fr ")
          (Drive_sheet.Authorizing "a@x.fr")
          [Drive_sheet.Ask_token "a@x.fr"];
        case "a blank stored account: the chooser" ~stored:(Some "  ")
          (Drive_sheet.Choosing {previous = None})
          [Drive_sheet.Run_chooser];
      ])
    [picker_ready; picker_unconfigured]

(* ---------- first open, no account ---------- *)

let first_open_cancel_closes_the_sheet () =
  let t0, (_ : Drive_sheet.command list) =
    Drive_sheet.open_ ~purpose:Drive_sheet.Change ~stored:None
      ~folder:Drive_text.Default ~picker:picker_ready
  in
  Alcotest.check step_t
    "the first choice was cancelled: Closed, Close, nothing else changed"
    (state Drive_sheet.Closed, [Drive_sheet.Close])
    (Drive_sheet.step t0 (Drive_sheet.Choose_failed Drive_account.Cancelled))

let first_open_success_chain () =
  let t0, (_ : Drive_sheet.command list) =
    Drive_sheet.open_ ~purpose:Drive_sheet.Change ~stored:None
      ~folder:Drive_text.Default ~picker:picker_ready
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

(* ---------- Turn_on: the 4m Drive radio's first choice ----------

   [Turn_on] is a straight line (chooser → token → Picker → store) with no
   sheet controls: every end other than a stored pick closes with nothing
   stored, the storage unchanged. Each case below checks the full (t,
   commands) pair, as the [Change] cases above do. *)

let all_denials =
  Drive_text.
    [
      Unconfigured;
      No_drive_account;
      Consent_needed;
      Consent_refused;
      Offline;
      Misconfigured;
      No_account;
      Failed;
    ]

let denial_name = function
  | Drive_text.Unconfigured -> "Unconfigured"
  | Drive_text.No_drive_account -> "No_drive_account"
  | Drive_text.Consent_needed -> "Consent_needed"
  | Drive_text.Consent_refused -> "Consent_refused"
  | Drive_text.Offline -> "Offline"
  | Drive_text.Misconfigured -> "Misconfigured"
  | Drive_text.No_account -> "No_account"
  | Drive_text.Failed -> "Failed"

let turn_on_closed ?error () =
  state ~purpose:Drive_sheet.Turn_on ?error Drive_sheet.Closed

(* open_ *)
let turn_on_open_tests =
  [
    ( "stored = None: Choosing, [Run_chooser]",
      `Quick,
      fun () ->
        Alcotest.check step_t "open_"
          ( state ~purpose:Drive_sheet.Turn_on
              (Drive_sheet.Choosing {previous = None}),
            [Drive_sheet.Run_chooser] )
          (Drive_sheet.open_ ~purpose:Drive_sheet.Turn_on ~stored:None
             ~folder:Drive_text.Default ~picker:picker_ready) );
    ( "a stored account: straight to Authorizing, [Ask_token], no chooser",
      `Quick,
      fun () ->
        Alcotest.check step_t "open_"
          ( state ~purpose:Drive_sheet.Turn_on ~stored:(Some " a@x.fr ")
              (Drive_sheet.Authorizing "a@x.fr"),
            [Drive_sheet.Ask_token "a@x.fr"] )
          (Drive_sheet.open_ ~purpose:Drive_sheet.Turn_on
             ~stored:(Some " a@x.fr ") ~folder:Drive_text.Default
             ~picker:picker_ready) );
    ( "Picker_unconfigured, no account stored: Closed, Picker_unavailable, \
       [Close] (the machine's own guard: never a chooser or a token)",
      `Quick,
      fun () ->
        Alcotest.check step_t "open_"
          ( state ~purpose:Drive_sheet.Turn_on ~picker:picker_unconfigured
              ~error:(Some Drive_text.Picker_unavailable) Drive_sheet.Closed,
            [Drive_sheet.Close] )
          (Drive_sheet.open_ ~purpose:Drive_sheet.Turn_on ~stored:None
             ~folder:Drive_text.Default ~picker:picker_unconfigured) );
    ( "Picker_unconfigured, an account stored: Closed too",
      `Quick,
      fun () ->
        Alcotest.check step_t "open_"
          ( state ~purpose:Drive_sheet.Turn_on ~stored:(Some "a@x.fr")
              ~picker:picker_unconfigured
              ~error:(Some Drive_text.Picker_unavailable) Drive_sheet.Closed,
            [Drive_sheet.Close] )
          (Drive_sheet.open_ ~purpose:Drive_sheet.Turn_on
             ~stored:(Some "a@x.fr") ~folder:Drive_text.Default
             ~picker:picker_unconfigured) );
  ]

(* cancel at the chooser *)
let turn_on_cancel_at_chooser_tests =
  let case name previous =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check step_t "step"
          (turn_on_closed (), [Drive_sheet.Close])
          (Drive_sheet.step
             (state ~purpose:Drive_sheet.Turn_on
                (Drive_sheet.Choosing {previous}))
             (Drive_sheet.Choose_failed Drive_account.Cancelled)) )
  in
  [
    case "Choosing {previous = None}, Choose_failed Cancelled: Closed, no error"
      None;
    case "Choosing {previous = Some _}, Choose_failed Cancelled: Closed too"
      (Some "a@x.fr");
  ]

(* the other chooser failures, and a blank Chosen *)
let turn_on_chooser_error_tests =
  let choosing =
    state ~purpose:Drive_sheet.Turn_on (Drive_sheet.Choosing {previous = None})
  in
  [
    ( "Choose_failed No_google_account: Closed, Chooser_no_account",
      `Quick,
      fun () ->
        Alcotest.check step_t "step"
          ( turn_on_closed ~error:(Some Drive_text.Chooser_no_account) (),
            [Drive_sheet.Close] )
          (Drive_sheet.step choosing
             (Drive_sheet.Choose_failed Drive_account.No_google_account)) );
    ( "Choose_failed Choose_failed: Closed, Chooser_failed",
      `Quick,
      fun () ->
        Alcotest.check step_t "step"
          ( turn_on_closed ~error:(Some Drive_text.Chooser_failed) (),
            [Drive_sheet.Close] )
          (Drive_sheet.step choosing
             (Drive_sheet.Choose_failed Drive_account.Choose_failed)) );
    ( "Chosen \"  \" (blank): Closed, Chooser_failed",
      `Quick,
      fun () ->
        Alcotest.check step_t "step"
          ( turn_on_closed ~error:(Some Drive_text.Chooser_failed) (),
            [Drive_sheet.Close] )
          (Drive_sheet.step choosing (Drive_sheet.Chosen "  ")) );
  ]

(* A token refused, for every denial. The stored account refused: the
   chooser, once (the radio has no « Utiliser un autre compte »); an account
   just chosen, or the stored one refused again: Closed. *)
let turn_on_token_error_tests =
  List.concat_map
    (fun d ->
      let refused = Some (Drive_text.Token d) in
      let case name ~stored ~error expected =
        ( Printf.sprintf "Token (Error %s), %s" (denial_name d) name,
          `Quick,
          fun () ->
            Alcotest.check step_t "step" expected
              (Drive_sheet.step
                 (state ~purpose:Drive_sheet.Turn_on ~stored ~error
                    (Drive_sheet.Authorizing "a@x.fr"))
                 (Drive_sheet.Token (Error d))) )
      in
      [
        case "no account stored: Closed, that error" ~stored:None ~error:None
          ( state ~purpose:Drive_sheet.Turn_on ~error:refused Drive_sheet.Closed,
            [Drive_sheet.Close] );
        case "another account stored: Closed, that error"
          ~stored:(Some "b@x.fr") ~error:None
          ( state ~purpose:Drive_sheet.Turn_on ~stored:(Some "b@x.fr")
              ~error:refused Drive_sheet.Closed,
            [Drive_sheet.Close] );
        case "the stored account: the chooser, the refusal kept"
          ~stored:(Some " A@x.fr ") ~error:None
          ( state ~purpose:Drive_sheet.Turn_on ~stored:(Some " A@x.fr ")
              ~error:refused
              (Drive_sheet.Choosing {previous = None}),
            [Drive_sheet.Run_chooser] );
        case "the stored account refused again: Closed, that error"
          ~stored:(Some "a@x.fr")
          ~error:(Some (Drive_text.Token Drive_text.No_account))
          ( state ~purpose:Drive_sheet.Turn_on ~stored:(Some "a@x.fr")
              ~error:refused Drive_sheet.Closed,
            [Drive_sheet.Close] );
      ])
    all_denials

(* the defensive branch: Authorizing + Picker_unconfigured cannot be reached
   through open_, but step still closes safely if built by
   hand. *)
let turn_on_authorizing_with_picker_unconfigured_by_hand_test =
  ( "Authorizing + Picker_unconfigured, built by hand (open_ never reaches \
     it): Token Ok still closes, with Picker_unavailable",
    `Quick,
    fun () ->
      let authorizing =
        state ~purpose:Drive_sheet.Turn_on ~picker:picker_unconfigured
          (Drive_sheet.Authorizing "a@x.fr")
      in
      Alcotest.check step_t "step"
        ( {
            authorizing with
            Drive_sheet.phase = Drive_sheet.Closed;
            error = Some Drive_text.Picker_unavailable;
          },
          [Drive_sheet.Close] )
        (Drive_sheet.step authorizing (Drive_sheet.Token (Ok "tok"))) )

(* cancel at the Picker *)
let turn_on_cancel_at_picker_test =
  ( "Browsing + Picker_cancelled: Closed, no error",
    `Quick,
    fun () ->
      Alcotest.check step_t "step"
        (turn_on_closed (), [Drive_sheet.Close])
        (Drive_sheet.step
           (state ~purpose:Drive_sheet.Turn_on (Drive_sheet.Browsing "a@x.fr"))
           Drive_sheet.Picker_cancelled) )

(* the Picker itself fails *)
let turn_on_picker_failed_tests =
  let case name e =
    ( Printf.sprintf "Picker_failed %s: Closed, that error" name,
      `Quick,
      fun () ->
        Alcotest.check step_t "step"
          (turn_on_closed ~error:(Some e) (), [Drive_sheet.Close])
          (Drive_sheet.step
             (state ~purpose:Drive_sheet.Turn_on (Drive_sheet.Browsing "a@x.fr"))
             (Drive_sheet.Picker_failed e)) )
  in
  [
    case "Offline" Drive_text.Offline;
    case "Picker_unavailable" Drive_text.Picker_unavailable;
  ]

(* a pick stores account, folder and storage together (the runner turns
   Drive on for a Turn_on Store_pick) *)
let turn_on_pick_stores_together_test =
  ( "Browsing + Picker_picked: Storing, Store_pick",
    `Quick,
    fun () ->
      Alcotest.check step_t "step"
        ( state ~purpose:Drive_sheet.Turn_on (Drive_sheet.Storing "a@x.fr"),
          [
            Drive_sheet.Store_pick
              {account = "a@x.fr"; folder_id = "F1"; folder_name = "Plantes"};
          ] )
        (Drive_sheet.step
           (state ~purpose:Drive_sheet.Turn_on (Drive_sheet.Browsing "a@x.fr"))
           (Drive_sheet.Picker_picked {id = "F1"; name = "Plantes"})) )

(* the store's own result *)
let turn_on_stored_tests =
  [
    ( "Stored (Ok ()): Closed, no error",
      `Quick,
      fun () ->
        Alcotest.check step_t "step"
          (turn_on_closed (), [Drive_sheet.Close])
          (Drive_sheet.step
             (state ~purpose:Drive_sheet.Turn_on (Drive_sheet.Storing "a@x.fr"))
             (Drive_sheet.Stored (Ok ()))) );
    ( "Stored (Error Not_saved): Closed, Not_saved",
      `Quick,
      fun () ->
        Alcotest.check step_t "step"
          ( turn_on_closed ~error:(Some Drive_text.Not_saved) (),
            [Drive_sheet.Close] )
          (Drive_sheet.step
             (state ~purpose:Drive_sheet.Turn_on (Drive_sheet.Storing "a@x.fr"))
             (Drive_sheet.Stored (Error Drive_text.Not_saved))) );
  ]

(* no controls in Turn_on, so these taps are always ignored *)
let turn_on_ignored_taps_test =
  ( "Tap_other_account, Tap_browse, Tap_default: unchanged, [], in every open \
     phase",
    `Quick,
    fun () ->
      List.iter
        (fun phase ->
          let base = state ~purpose:Drive_sheet.Turn_on phase in
          List.iter
            (fun event ->
              Alcotest.check step_t
                (Printf.sprintf "%s, %s" (phase_name phase)
                   (Drive_sheet.show_event event))
                (base, [])
                (Drive_sheet.step base event))
            Drive_sheet.[Tap_other_account; Tap_browse; Tap_default])
        open_phases )

(* The invariant, exhaustively: no Store_default in Turn_on, and a
   Store_pick only from Browsing on Picker_picked. *)
let invariant_phases =
  Drive_sheet.
    [
      Choosing {previous = None};
      Choosing {previous = Some "a@x.fr"};
      Authorizing "a@x.fr";
      Browsing "a@x.fr";
      Storing "a@x.fr";
      Idle None;
      Idle (Some "a@x.fr");
      Closed;
    ]

let invariant_events =
  Drive_sheet.
    [
      Tap_other_account;
      Tap_browse;
      Tap_default;
      Tap_close;
      Chosen "x@x.fr";
      Chosen "  ";
      Choose_failed Drive_account.Cancelled;
      Choose_failed Drive_account.No_google_account;
      Choose_failed Drive_account.Choose_failed;
      Token (Ok "tok");
    ]
  @ List.map (fun d -> Drive_sheet.Token (Error d)) all_denials
  @ Drive_sheet.
      [
        Picker_picked {id = "F1"; name = "Plantes"};
        Picker_cancelled;
        Picker_failed Drive_text.Offline;
        Picker_failed Drive_text.Picker_unavailable;
        Stored (Ok ());
        Stored (Error Drive_text.Not_saved);
      ]

let is_store_default (c : Drive_sheet.command) =
  match c with Store_default _ -> true | _ -> false

let is_store_pick (c : Drive_sheet.command) =
  match c with Store_pick _ -> true | _ -> false

let turn_on_invariant_test =
  ( "step with purpose = Turn_on never emits Store_default, and emits \
     Store_pick only from Browsing on Picker_picked",
    `Quick,
    fun () ->
      List.iter
        (fun picker ->
          List.iter
            (fun stored ->
              List.iter
                (fun phase ->
                  List.iter
                    (fun event ->
                      let t =
                        state ~purpose:Drive_sheet.Turn_on ~stored ~picker phase
                      in
                      let (_ : Drive_sheet.t), cmds =
                        Drive_sheet.step t event
                      in
                      let label =
                        Printf.sprintf "%s, %s, %s, %s"
                          (Drive_text.show_picker_config picker)
                          (Option.value ~default:"no account" stored)
                          (phase_name phase)
                          (Drive_sheet.show_event event)
                      in
                      Alcotest.(check bool)
                        (label ^ ": no Store_default")
                        false
                        (List.exists is_store_default cmds);
                      let expected =
                        match (phase, event) with
                        | Drive_sheet.Browsing _, Drive_sheet.Picker_picked _ ->
                            1
                        | _ -> 0
                      in
                      Alcotest.(check int)
                        (label ^ ": Store_pick commands")
                        expected
                        (List.length (List.filter is_store_pick cmds)))
                    invariant_events)
                invariant_phases)
            [None; Some "a@x.fr"])
        [picker_ready; picker_unconfigured] )

(* Walks, from open_, with no store command along the way except the one
   walk that reaches a pick (tested separately above). *)
let turn_on_walk_tests =
  [
    ( "chooser, choose, token Ok, then the Picker cancelled: Closed, never a \
       store command",
      `Quick,
      fun () ->
        let t0, cmds0 =
          Drive_sheet.open_ ~purpose:Drive_sheet.Turn_on ~stored:None
            ~folder:Drive_text.Default ~picker:picker_ready
        in
        let t1, cmds1 = Drive_sheet.step t0 (Drive_sheet.Chosen "a@x.fr") in
        let t2, cmds2 = Drive_sheet.step t1 (Drive_sheet.Token (Ok "tok")) in
        let t3, cmds3 = Drive_sheet.step t2 Drive_sheet.Picker_cancelled in
        Alcotest.check t_t "final state: Closed, no error" (turn_on_closed ())
          t3;
        Alcotest.(check bool)
          "never a store command" false
          (List.exists is_store_command (cmds0 @ cmds1 @ cmds2 @ cmds3)) );
    ( "the chooser cancelled at once: Closed, no error",
      `Quick,
      fun () ->
        let t0, cmds0 =
          Drive_sheet.open_ ~purpose:Drive_sheet.Turn_on ~stored:None
            ~folder:Drive_text.Default ~picker:picker_ready
        in
        let t1, cmds1 =
          Drive_sheet.step t0
            (Drive_sheet.Choose_failed Drive_account.Cancelled)
        in
        Alcotest.check t_t "final state" (turn_on_closed ()) t1;
        Alcotest.(check bool)
          "never a store command" false
          (List.exists is_store_command (cmds0 @ cmds1)) );
    ( "the stored account gone from the phone, then the chooser cancelled: \
       Closed with the refusal, never a store command",
      `Quick,
      fun () ->
        let t0, cmds0 =
          Drive_sheet.open_ ~purpose:Drive_sheet.Turn_on ~stored:(Some "a@x.fr")
            ~folder:Drive_text.Default ~picker:picker_ready
        in
        let t1, cmds1 =
          Drive_sheet.step t0 (Drive_sheet.Token (Error Drive_text.No_account))
        in
        Alcotest.(check commands_t)
          "the refusal opens the chooser" [Drive_sheet.Run_chooser] cmds1;
        let t2, cmds2 =
          Drive_sheet.step t1
            (Drive_sheet.Choose_failed Drive_account.Cancelled)
        in
        Alcotest.check t_t "final state"
          (state ~purpose:Drive_sheet.Turn_on ~stored:(Some "a@x.fr")
             ~error:(Some (Drive_text.Token Drive_text.No_account))
             Drive_sheet.Closed)
          t2;
        Alcotest.(check bool)
          "never a store command" false
          (List.exists is_store_command (cmds0 @ cmds1 @ cmds2)) );
    ( "the stored account refused, another chosen and picked: Store_pick for \
       the new account",
      `Quick,
      fun () ->
        let t0, (_ : Drive_sheet.command list) =
          Drive_sheet.open_ ~purpose:Drive_sheet.Turn_on ~stored:(Some "a@x.fr")
            ~folder:Drive_text.Default ~picker:picker_ready
        in
        let t1, (_ : Drive_sheet.command list) =
          Drive_sheet.step t0 (Drive_sheet.Token (Error Drive_text.No_account))
        in
        let t2, (_ : Drive_sheet.command list) =
          Drive_sheet.step t1 (Drive_sheet.Chosen "b@x.fr")
        in
        let t3, (_ : Drive_sheet.command list) =
          Drive_sheet.step t2 (Drive_sheet.Token (Ok "tok"))
        in
        let t4, cmds4 =
          Drive_sheet.step t3
            (Drive_sheet.Picker_picked {id = "F1"; name = "Plantes"})
        in
        Alcotest.(check commands_t)
          "the pick"
          [
            Drive_sheet.Store_pick
              {account = "b@x.fr"; folder_id = "F1"; folder_name = "Plantes"};
          ]
          cmds4;
        Alcotest.check step_t "stored: Closed, no error"
          ( state ~purpose:Drive_sheet.Turn_on ~stored:(Some "a@x.fr")
              Drive_sheet.Closed,
            [Drive_sheet.Close] )
          (Drive_sheet.step t4 (Drive_sheet.Stored (Ok ()))) );
  ]

(* can_browse, can_default, picker_note and status_line *)
let turn_on_helper_states =
  List.concat_map
    (fun picker ->
      List.concat_map
        (fun stored ->
          List.concat_map
            (fun folder ->
              List.map
                (fun phase ->
                  state ~purpose:Drive_sheet.Turn_on ~stored ~folder ~picker
                    phase)
                invariant_phases)
            Drive_text.[Default; Picked "Plantes"])
        [None; Some "a@x.fr"])
    [picker_ready; picker_unconfigured]

let turn_on_helpers_test =
  ( "can_browse, can_default are false and picker_note is None for every \
     Turn_on state",
    `Quick,
    fun () ->
      List.iter
        (fun t ->
          Alcotest.(check bool) "can_browse" false (Drive_sheet.can_browse t);
          Alcotest.(check bool) "can_default" false (Drive_sheet.can_default t);
          Alcotest.(check (option string))
            "picker_note" None
            (Drive_sheet.picker_note t))
        turn_on_helper_states )

let turn_on_status_line_tests =
  let case phase expected =
    ( Printf.sprintf "%s" (phase_name phase),
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "status_line, the same text as for Change" expected
          (Drive_sheet.status_line
             (state ~purpose:Drive_sheet.Turn_on ~stored:(Some "a@x.fr") phase))
    )
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

(* Tap_close in any open phase closes, error cleared, nothing stored; and a
   Closed machine ignores every event. *)
let turn_on_tap_close_tests =
  List.map
    (fun phase ->
      ( Printf.sprintf "%s + Tap_close: Closed, error cleared, [Close]"
          (phase_name phase),
        `Quick,
        fun () ->
          Alcotest.check step_t "step"
            (turn_on_closed (), [Drive_sheet.Close])
            (Drive_sheet.step
               (state ~purpose:Drive_sheet.Turn_on
                  ~error:(Some Drive_text.Offline) phase)
               Drive_sheet.Tap_close) ))
    open_phases

let turn_on_closed_ignores_events_test =
  ( "Closed ignores every event: unchanged, []",
    `Quick,
    fun () ->
      let closed = turn_on_closed ~error:(Some Drive_text.Not_saved) () in
      List.iter
        (fun event ->
          Alcotest.check step_t
            (Printf.sprintf "Closed, %s" (Drive_sheet.show_event event))
            (closed, [])
            (Drive_sheet.step closed event))
        invariant_events )

let turn_on_tests =
  List.concat
    [
      turn_on_open_tests;
      turn_on_cancel_at_chooser_tests;
      turn_on_chooser_error_tests;
      turn_on_token_error_tests;
      [turn_on_authorizing_with_picker_unconfigured_by_hand_test];
      [turn_on_cancel_at_picker_test];
      turn_on_picker_failed_tests;
      [turn_on_pick_stores_together_test];
      turn_on_stored_tests;
      [turn_on_ignored_taps_test];
      [turn_on_invariant_test];
      turn_on_walk_tests;
      [turn_on_helpers_test];
      turn_on_status_line_tests;
      turn_on_tap_close_tests;
      [turn_on_closed_ignores_events_test];
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
      turn_on_tests;
    ]
