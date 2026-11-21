(* app/ui_model/drive_sheet.ml (Herbier_ui_model.Drive_sheet): the pure state
   machine behind 4m's « Dossier Drive » sheet and the 4m Drive radio (the
   account line, the folder name with « Renommer »). Each case checks the
   full returned (t, commands) pair of Drive_sheet.open_/step.

   Change opens on the stored account without a token; a rename is asked
   only from Idle (Some stored), a blank name refused with Blank_name, the
   current name sent too; another account goes
   Authorizing → Storing → Idle with the sheet left open; Turn_on never
   renames and emits Store_account only from Authorizing on Token (Ok _). *)

module Drive_sheet = Herbier_ui_model.Drive_sheet
module Drive_text = Herbier_ui_model.Drive_text
module Drive_account = Herbier_sync_core.Auth.Drive_account
module Text = Herbier_test_support.Text

(* ---------- testables ---------- *)

let t_t = Alcotest.testable Drive_sheet.pp Drive_sheet.equal

let command_t =
  Alcotest.testable Drive_sheet.pp_command Drive_sheet.equal_command

let commands_t = Alcotest.(list command_t)
let step_t = Alcotest.(pair t_t commands_t)
let phase_name p = Drive_sheet.show_phase p

(* ---------- building states ---------- *)

let state ?(purpose = Drive_sheet.Change) ?(stored = None) ?(folder = "Herbier")
    ?(error = None) phase : Drive_sheet.t =
  {Drive_sheet.purpose; stored; folder; phase; error}

let stored_a = Some "a@x.fr"

(* An Idle Change sheet on the stored account: the common base below. *)
let idle_a = state ~stored:stored_a (Drive_sheet.Idle stored_a)

let renaming_a name =
  state ~stored:stored_a (Drive_sheet.Renaming {account = "a@x.fr"; name})

(* Every phase but Closed, for a@x.fr. *)
let open_phases =
  Drive_sheet.
    [
      Choosing {previous = Some "a@x.fr"};
      Authorizing "a@x.fr";
      Storing "a@x.fr";
      Renaming {account = "a@x.fr"; name = "Plantes"};
      Idle (Some "a@x.fr");
    ]

let all_phases = Drive_sheet.Closed :: Drive_sheet.Idle None :: open_phases

(* One of each event, a token included. *)
let all_events =
  Drive_sheet.
    [
      Tap_other_account;
      Tap_rename "Plantes";
      Tap_rename "  ";
      Tap_close;
      Chosen "b@x.fr";
      Chosen "a@x.fr";
      Chosen " ";
      Choose_failed Drive_account.Cancelled;
      Choose_failed Drive_account.No_google_account;
      Choose_failed Drive_account.Choose_failed;
      Token (Ok "ya29.secret");
      Token (Error Drive_text.Consent_refused);
      Stored (Ok ());
      Stored (Error Drive_text.Not_saved);
      Renamed (Ok "Plantes");
      Renamed (Error Drive_text.Offline);
    ]

let step = Drive_sheet.step

(* ---------- open_ ---------- *)

let open_case name ~purpose ~stored ~folder expected =
  ( name,
    `Quick,
    fun () ->
      Alcotest.check step_t "open_" expected
        (Drive_sheet.open_ ~purpose ~stored ~folder) )

let open_tests =
  Drive_sheet.
    [
      open_case "Change, nothing stored: Choosing, [Run_chooser]"
        ~purpose:Change ~stored:None ~folder:"Herbier"
        (state (Choosing {previous = None}), [Run_chooser]);
      open_case "Change, a blank stored account: the chooser" ~purpose:Change
        ~stored:(Some "  ") ~folder:"Herbier"
        (state (Choosing {previous = None}), [Run_chooser]);
      open_case
        "Change, a stored account: Idle on it, no command (no token at open)"
        ~purpose:Change ~stored:stored_a ~folder:"Herbier"
        (state ~stored:stored_a (Idle stored_a), []);
      open_case "Change, a padded stored account: trimmed" ~purpose:Change
        ~stored:(Some " a@x.fr ") ~folder:"Herbier"
        (state ~stored:stored_a (Idle stored_a), []);
      open_case "Change: the folder name is kept verbatim" ~purpose:Change
        ~stored:stored_a ~folder:"Mes plantes"
        (state ~stored:stored_a ~folder:"Mes plantes" (Idle stored_a), []);
      open_case "Turn_on, nothing stored: Choosing, [Run_chooser]"
        ~purpose:Turn_on ~stored:None ~folder:"Herbier"
        (state ~purpose:Turn_on (Choosing {previous = None}), [Run_chooser]);
      open_case "Turn_on, a stored account: Authorizing it, [Ask_token]"
        ~purpose:Turn_on ~stored:(Some " a@x.fr ") ~folder:"Herbier"
        ( state ~purpose:Turn_on ~stored:stored_a (Authorizing "a@x.fr"),
          [Ask_token "a@x.fr"] );
    ]

(* ---------- Change: rename ---------- *)

let rename_tests =
  Drive_sheet.
    [
      ( "Tap_rename blank: Blank_name, no command, phase unchanged",
        `Quick,
        fun () ->
          Alcotest.check step_t "step"
            ({idle_a with error = Some Drive_text.Blank_name}, [])
            (step idle_a (Tap_rename "  ")) );
      ( "Tap_rename empty: Blank_name",
        `Quick,
        fun () ->
          Alcotest.check step_t "step"
            ({idle_a with error = Some Drive_text.Blank_name}, [])
            (step idle_a (Tap_rename "")) );
      ( "Tap_rename padded: Renaming the trimmed name, [Rename]",
        `Quick,
        fun () ->
          Alcotest.check step_t "step"
            ( renaming_a "Plantes",
              [Rename {account = "a@x.fr"; name = "Plantes"}] )
            (step idle_a (Tap_rename " Plantes ")) );
      ( "Tap_rename clears an earlier error",
        `Quick,
        fun () ->
          Alcotest.check step_t "step"
            ( renaming_a "Plantes",
              [Rename {account = "a@x.fr"; name = "Plantes"}] )
            (step
               {idle_a with error = Some Drive_text.Offline}
               (Tap_rename "Plantes")) );
      ( "Tap_rename with the current name: sent all the same (the name shown \
         may be stale), error cleared",
        `Quick,
        fun () ->
          Alcotest.check step_t "step"
            ( renaming_a "Herbier",
              [Rename {account = "a@x.fr"; name = "Herbier"}] )
            (step
               {idle_a with error = Some Drive_text.Blank_name}
               (Tap_rename " Herbier ")) );
      ( "Tap_rename with Idle None (no account): ignored",
        `Quick,
        fun () ->
          let t = state (Idle None) in
          Alcotest.check step_t "step" (t, []) (step t (Tap_rename "Plantes"))
      );
      ( "Renamed Ok: Idle on the account, folder = the name Drive gave",
        `Quick,
        fun () ->
          Alcotest.check step_t "step"
            ({idle_a with folder = "Plantes (1)"}, [])
            (step (renaming_a "Plantes") (Renamed (Ok "Plantes (1)"))) );
      ( "Renamed Error: Idle on the account, the error, folder kept",
        `Quick,
        fun () ->
          Alcotest.check step_t "step"
            ({idle_a with error = Some Drive_text.Offline}, [])
            (step (renaming_a "Plantes") (Renamed (Error Drive_text.Offline)))
      );
      ( "Tap_rename while Renaming, Storing, Authorizing or Choosing: ignored",
        `Quick,
        fun () ->
          List.iter
            (fun phase ->
              let t = state ~stored:stored_a phase in
              Alcotest.check step_t (phase_name phase) (t, [])
                (step t (Tap_rename "Autre")))
            [
              Renaming {account = "a@x.fr"; name = "Plantes"};
              Storing "a@x.fr";
              Authorizing "a@x.fr";
              Choosing {previous = stored_a};
            ] );
      ( "a full rename walk: open, rename, done",
        `Quick,
        fun () ->
          let t0, c0 =
            Drive_sheet.open_ ~purpose:Change ~stored:stored_a ~folder:"Herbier"
          in
          Alcotest.check commands_t "open: nothing" [] c0;
          let t1, c1 = step t0 (Tap_rename "Plantes") in
          Alcotest.check commands_t "rename asked"
            [Rename {account = "a@x.fr"; name = "Plantes"}]
            c1;
          Alcotest.(check (option string))
            "status while renaming" (Some "Renommage du dossier…")
            (Drive_sheet.status_line t1);
          Alcotest.check step_t "done"
            ({idle_a with folder = "Plantes"}, [])
            (step t1 (Renamed (Ok "Plantes"))) );
    ]

(* ---------- Change: another account ---------- *)

let account_tests =
  Drive_sheet.
    [
      ( "Tap_other_account: Choosing with the current account as previous, \
         error cleared",
        `Quick,
        fun () ->
          Alcotest.check step_t "step"
            ( state ~stored:stored_a (Choosing {previous = stored_a}),
              [Run_chooser] )
            (step
               {idle_a with error = Some Drive_text.Offline}
               Tap_other_account) );
      ( "another account: Authorizing, Storing, then Idle on it, stored, the \
         sheet open",
        `Quick,
        fun () ->
          let t1, c1 = step idle_a Tap_other_account in
          Alcotest.check commands_t "chooser" [Run_chooser] c1;
          let t2, c2 = step t1 (Chosen " b@x.fr ") in
          Alcotest.check step_t "chosen, trimmed"
            (state ~stored:stored_a (Authorizing "b@x.fr"), [Ask_token "b@x.fr"])
            (t2, c2);
          let t3, c3 = step t2 (Token (Ok "tok")) in
          Alcotest.check step_t "token: store it"
            (state ~stored:stored_a (Storing "b@x.fr"), [Store_account "b@x.fr"])
            (t3, c3);
          Alcotest.check step_t "stored: Idle on b, stored = b, no Close"
            (state ~stored:(Some "b@x.fr") (Idle (Some "b@x.fr")), [])
            (step t3 (Stored (Ok ()))) );
      ( "the stored account chosen again: Token Ok is Idle on it, nothing stored",
        `Quick,
        fun () ->
          let t = state ~stored:stored_a (Authorizing "A@x.fr") in
          Alcotest.check step_t "step"
            (state ~stored:stored_a (Idle (Some "A@x.fr")), [])
            (step t (Token (Ok "tok"))) );
      ( "the stored account's token refused: Idle on it, Token d",
        `Quick,
        fun () ->
          let t = state ~stored:stored_a (Authorizing "a@x.fr") in
          Alcotest.check step_t "step"
            ( state ~stored:stored_a
                ~error:(Some (Drive_text.Token Drive_text.Consent_refused))
                (Idle stored_a),
              [] )
            (step t (Token (Error Drive_text.Consent_refused))) );
      ( "another account's token refused: back to the stored one, \
         Other_account d",
        `Quick,
        fun () ->
          let t = state ~stored:stored_a (Authorizing "b@x.fr") in
          Alcotest.check step_t "step"
            ( state ~stored:stored_a
                ~error:(Some (Drive_text.Other_account Drive_text.Offline))
                (Idle stored_a),
              [] )
            (step t (Token (Error Drive_text.Offline))) );
      ( "nothing stored, the token refused: Idle None, Token d",
        `Quick,
        fun () ->
          let t = state (Authorizing "b@x.fr") in
          Alcotest.check step_t "step"
            ( state ~error:(Some (Drive_text.Token Drive_text.Failed))
                (Idle None),
              [] )
            (step t (Token (Error Drive_text.Failed))) );
      ( "Stored Error: Idle on the stored account, the error",
        `Quick,
        fun () ->
          let t = state ~stored:stored_a (Storing "b@x.fr") in
          Alcotest.check step_t "step"
            ( state ~stored:stored_a ~error:(Some Drive_text.Not_saved)
                (Idle stored_a),
              [] )
            (step t (Stored (Error Drive_text.Not_saved))) );
      ( "a blank Chosen: Idle previous, Chooser_failed",
        `Quick,
        fun () ->
          let t = state ~stored:stored_a (Choosing {previous = stored_a}) in
          Alcotest.check step_t "step"
            ({idle_a with error = Some Drive_text.Chooser_failed}, [])
            (step t (Chosen "  ")) );
      ( "first choice cancelled (no previous): Closed, [Close]",
        `Quick,
        fun () ->
          let t = state (Choosing {previous = None}) in
          Alcotest.check step_t "step"
            (state Closed, [Close])
            (step t (Choose_failed Drive_account.Cancelled)) );
      ( "a later choice cancelled: back to Idle previous, no command",
        `Quick,
        fun () ->
          let t = state ~stored:stored_a (Choosing {previous = stored_a}) in
          Alcotest.check step_t "step" (idle_a, [])
            (step t (Choose_failed Drive_account.Cancelled)) );
      ( "chooser without a Google account: Chooser_no_account; chooser failed: \
         Chooser_failed",
        `Quick,
        fun () ->
          let t = state ~stored:stored_a (Choosing {previous = stored_a}) in
          Alcotest.check step_t "no account"
            ({idle_a with error = Some Drive_text.Chooser_no_account}, [])
            (step t (Choose_failed Drive_account.No_google_account));
          Alcotest.check step_t "failed"
            ({idle_a with error = Some Drive_text.Chooser_failed}, [])
            (step t (Choose_failed Drive_account.Choose_failed)) );
    ]

(* ---------- Change: close ---------- *)

let close_tests =
  List.map
    (fun phase ->
      ( Printf.sprintf "Change, %s + Tap_close: Closed, [Close], error cleared"
          (phase_name phase),
        `Quick,
        fun () ->
          Alcotest.check step_t "step"
            (state ~stored:stored_a Drive_sheet.Closed, [Drive_sheet.Close])
            (step
               (state ~stored:stored_a ~error:(Some Drive_text.Offline) phase)
               Drive_sheet.Tap_close) ))
    open_phases
  @ [
      ( "Change, Closed ignores every event",
        `Quick,
        fun () ->
          let closed = state ~stored:stored_a Drive_sheet.Closed in
          List.iter
            (fun e ->
              Alcotest.check step_t (Drive_sheet.show_event e) (closed, [])
                (step closed e))
            all_events );
    ]

(* ---------- Turn_on ---------- *)

let turn_on ?(stored = None) ?(error = None) phase =
  state ~purpose:Drive_sheet.Turn_on ~stored ~error phase

let turn_on_tests =
  Drive_sheet.
    [
      ( "Turn_on: Token Ok for the stored account still stores (the storage \
         must be written)",
        `Quick,
        fun () ->
          Alcotest.check step_t "step"
            ( turn_on ~stored:stored_a (Storing "a@x.fr"),
              [Store_account "a@x.fr"] )
            (step
               (turn_on ~stored:stored_a (Authorizing "a@x.fr"))
               (Token (Ok "tok"))) );
      ( "Turn_on: Chosen is Authorizing, trimmed",
        `Quick,
        fun () ->
          Alcotest.check step_t "step"
            (turn_on (Authorizing "b@x.fr"), [Ask_token "b@x.fr"])
            (step (turn_on (Choosing {previous = None})) (Chosen " b@x.fr ")) );
      ( "Turn_on: a blank Chosen closes with Chooser_failed",
        `Quick,
        fun () ->
          Alcotest.check step_t "step"
            (turn_on ~error:(Some Drive_text.Chooser_failed) Closed, [Close])
            (step (turn_on (Choosing {previous = None})) (Chosen " ")) );
      ( "Turn_on: chooser cancelled closes, the error kept",
        `Quick,
        fun () ->
          let err = Some (Drive_text.Token Drive_text.No_account) in
          Alcotest.check step_t "step"
            (turn_on ~error:err Closed, [Close])
            (step
               (turn_on ~error:err (Choosing {previous = None}))
               (Choose_failed Drive_account.Cancelled)) );
      ( "Turn_on: chooser errors close with their error",
        `Quick,
        fun () ->
          let t = turn_on (Choosing {previous = None}) in
          Alcotest.check step_t "no account"
            (turn_on ~error:(Some Drive_text.Chooser_no_account) Closed, [Close])
            (step t (Choose_failed Drive_account.No_google_account));
          Alcotest.check step_t "failed"
            (turn_on ~error:(Some Drive_text.Chooser_failed) Closed, [Close])
            (step t (Choose_failed Drive_account.Choose_failed)) );
      ( "Turn_on: the stored account refused, first time: the chooser opens, \
         the refusal kept",
        `Quick,
        fun () ->
          Alcotest.check step_t "step"
            ( turn_on ~stored:stored_a
                ~error:(Some (Drive_text.Token Drive_text.No_account))
                (Choosing {previous = None}),
              [Run_chooser] )
            (step
               (turn_on ~stored:stored_a (Authorizing "a@x.fr"))
               (Token (Error Drive_text.No_account))) );
      ( "Turn_on: another account refused: Closed, Token d",
        `Quick,
        fun () ->
          Alcotest.check step_t "step"
            ( turn_on ~stored:stored_a
                ~error:(Some (Drive_text.Token Drive_text.Consent_refused))
                Closed,
              [Close] )
            (step
               (turn_on ~stored:stored_a (Authorizing "b@x.fr"))
               (Token (Error Drive_text.Consent_refused))) );
      ( "Turn_on: the stored account refused again (an error already shown): \
         Closed",
        `Quick,
        fun () ->
          Alcotest.check step_t "step"
            ( turn_on ~stored:stored_a
                ~error:(Some (Drive_text.Token Drive_text.Failed)) Closed,
              [Close] )
            (step
               (turn_on ~stored:stored_a
                  ~error:(Some (Drive_text.Token Drive_text.No_account))
                  (Authorizing "a@x.fr"))
               (Token (Error Drive_text.Failed))) );
      ( "Turn_on: Stored Ok closes without error; Stored Error closes with it",
        `Quick,
        fun () ->
          let t = turn_on (Storing "b@x.fr") in
          Alcotest.check step_t "ok"
            (turn_on Closed, [Close])
            (step t (Stored (Ok ())));
          Alcotest.check step_t "error"
            (turn_on ~error:(Some Drive_text.Not_saved) Closed, [Close])
            (step t (Stored (Error Drive_text.Not_saved))) );
      ( "Turn_on: Tap_close closes from every open phase, error cleared",
        `Quick,
        fun () ->
          List.iter
            (fun phase ->
              Alcotest.check step_t (phase_name phase)
                (turn_on Closed, [Close])
                (step
                   (turn_on ~error:(Some Drive_text.Offline) phase)
                   Tap_close))
            open_phases );
      ( "Turn_on: Tap_other_account and Tap_rename are ignored everywhere",
        `Quick,
        fun () ->
          List.iter
            (fun phase ->
              let t = turn_on ~stored:stored_a phase in
              List.iter
                (fun e ->
                  Alcotest.check step_t
                    (phase_name phase ^ ", " ^ show_event e)
                    (t, []) (step t e))
                [Tap_other_account; Tap_rename "Plantes"])
            all_phases );
    ]

(* ---------- invariants over every (phase, event) pair ---------- *)

let pairs purpose =
  List.concat_map
    (fun phase ->
      List.concat_map
        (fun stored ->
          List.map
            (fun event -> (state ~purpose ~stored phase, event))
            all_events)
        [None; stored_a])
    all_phases

let is_rename = function
  | Drive_sheet.Rename _ -> true
  | Drive_sheet.(Run_chooser | Ask_token _ | Store_account _ | Close) -> false

let is_store = function
  | Drive_sheet.Store_account _ -> true
  | Drive_sheet.(Run_chooser | Ask_token _ | Rename _ | Close) -> false

let pair_name (t : Drive_sheet.t) event =
  Printf.sprintf "%s, %s" (phase_name t.phase) (Drive_sheet.show_event event)

let invariant_tests =
  [
    ( "Turn_on never emits Rename; Store_account only from Authorizing on \
       Token (Ok _)",
      `Quick,
      fun () ->
        List.iter
          (fun ((t : Drive_sheet.t), event) ->
            let (_ : Drive_sheet.t), cmds = step t event in
            let what = pair_name t event in
            Alcotest.(check bool)
              (what ^ ": no Rename") false
              (List.exists is_rename cmds);
            let from_token_ok =
              match (t.phase, event) with
              | Drive_sheet.Authorizing (_ : string), Drive_sheet.Token (Ok _)
                ->
                  true
              | _ -> false
            in
            Alcotest.(check bool)
              (what ^ ": Store_account exactly from Authorizing + Token Ok")
              from_token_ok
              (List.exists is_store cmds))
          (pairs Drive_sheet.Turn_on) );
    ( "Change emits Rename only from Idle (Some _) on Tap_rename",
      `Quick,
      fun () ->
        List.iter
          (fun ((t : Drive_sheet.t), event) ->
            let (_ : Drive_sheet.t), cmds = step t event in
            match List.exists is_rename cmds with
            | false -> ()
            | true ->
                let ok =
                  match (t.phase, event) with
                  | Drive_sheet.Idle (Some _), Drive_sheet.Tap_rename _ -> true
                  | _ -> false
                in
                Alcotest.(check bool) (pair_name t event) true ok)
          (pairs Drive_sheet.Change) );
  ]

(* ---------- can_rename, busy, status_line, account lines ---------- *)

(* all_phases, in order: Closed; Idle None; Choosing; Authorizing; Storing;
   Renaming; Idle (Some a). *)
let per_phase name f expected =
  ( name,
    `Quick,
    fun () ->
      List.iter2
        (fun phase e ->
          Alcotest.(check bool)
            (phase_name phase) e
            (f (state ~stored:stored_a phase)))
        all_phases expected )

let helper_tests =
  [
    per_phase "can_rename: only Change, Idle (Some _)" Drive_sheet.can_rename
      [false; false; false; false; false; false; true];
    per_phase "busy: Choosing, Authorizing, Storing, Renaming" Drive_sheet.busy
      [false; false; true; true; true; true; false];
    ( "can_rename is false for Turn_on, even Idle (Some _)",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "Turn_on" false
          (Drive_sheet.can_rename
             (state ~purpose:Drive_sheet.Turn_on ~stored:stored_a
                (Drive_sheet.Idle stored_a))) );
    ( "status_line per phase",
      `Quick,
      fun () ->
        List.iter2
          (fun phase expected ->
            Alcotest.(check (option string))
              (phase_name phase) expected
              (Drive_sheet.status_line (state ~stored:stored_a phase)))
          all_phases
          [
            None;
            None;
            None;
            Some "Connexion à Google Drive…";
            Some "Enregistrement…";
            Some "Renommage du dossier…";
            None;
          ] );
    ( "account_line and other_account_label, with and without an account",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "an account" "Compte : a@x.fr"
          (Drive_sheet.account_line idle_a);
        Alcotest.(check string)
          "an account: another one" "Utiliser un autre compte"
          (Drive_sheet.other_account_label idle_a);
        let none = state (Drive_sheet.Idle None) in
        Alcotest.(check string)
          "none" "Aucun compte choisi"
          (Drive_sheet.account_line none);
        Alcotest.(check string)
          "none: choose one" "Choisir un compte"
          (Drive_sheet.other_account_label none) );
    ( "account: Renaming's account, Choosing's previous, None when Closed",
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "Renaming" (Some "a@x.fr")
          (Drive_sheet.account (renaming_a "Plantes"));
        Alcotest.(check (option string))
          "Choosing previous" stored_a
          (Drive_sheet.account
             (state (Drive_sheet.Choosing {previous = stored_a})));
        Alcotest.(check (option string))
          "Closed" None
          (Drive_sheet.account (state Drive_sheet.Closed)) );
  ]

(* ---------- printers ---------- *)

let printer_tests =
  [
    ( "a Token event never prints the token",
      `Quick,
      fun () ->
        let printed =
          Drive_sheet.show_event (Drive_sheet.Token (Ok "ya29.secret"))
        in
        Alcotest.(check bool)
          "no token text" false
          (Text.contains ~sub:"ya29" printed);
        Alcotest.(check bool)
          "shows <token>" true
          (Text.contains ~sub:"<token>" printed) );
  ]

let tests =
  List.concat
    [
      open_tests;
      rename_tests;
      account_tests;
      close_tests;
      turn_on_tests;
      invariant_tests;
      helper_tests;
      printer_tests;
    ]
