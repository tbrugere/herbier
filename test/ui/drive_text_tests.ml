(* Herbier_ui_model.Drive_text (app/ui_model/drive_text.mli): the
   Drive-related texts of 4e, 4m and 5e. *)

module Drive_text = Herbier_ui_model.Drive_text
module Photo = Herbier_domain.Photo
module Ids = Herbier_domain.Ids
module Value = Herbier_test_support.Value
module Text = Herbier_test_support.Text
module Drive_account = Herbier_sync_core.Auth.Drive_account

let utc = Fixtures.utc

(* ---------- photo fixture ---------- *)

let photo_id n = Value.id "photo id" Ids.Photo_id.of_string (Value.uuid7 n)

let observation_id =
  Value.id "observation id" Ids.Observation_id.of_string (Value.uuid7 90)

let t0 = Value.time "2026-01-01T00:00:00Z"

let photo ?(target = Photo.Original_target.Drive)
    ?(state = Photo.Upload_state.Pending) ?(file_id = None) n : Photo.t =
  {
    id = photo_id n;
    observation_id;
    taken_at = t0;
    width = 1024;
    height = 768;
    sha256 = String.make 64 'a';
    preview_path = Printf.sprintf "previews/%d.webp" n;
    preview_bucket_key = None;
    original_target = target;
    drive_file_id = file_id;
    upload_state = state;
    created_at = t0;
    updated_at = t0;
    deleted_at = None;
  }

(* ---------- testables ---------- *)

let denial_to_string = function
  | Drive_text.Unconfigured -> "Unconfigured"
  | No_drive_account -> "No_drive_account"
  | Consent_needed -> "Consent_needed"
  | Consent_refused -> "Consent_refused"
  | Offline -> "Offline"
  | Misconfigured -> "Misconfigured"
  | No_account -> "No_account"
  | Failed -> "Failed"

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

let pp_access ppf = function
  | Drive_text.Unknown -> Format.pp_print_string ppf "Unknown"
  | Granted -> Format.pp_print_string ppf "Granted"
  | Denied d -> Format.fprintf ppf "Denied %s" (denial_to_string d)

let access_t = Alcotest.testable pp_access Drive_text.equal_access

let pp_queue ppf (q : Drive_text.queue) =
  Format.fprintf ppf
    "{waiting = %d; failed = %d; sending = %d; last_upload = %a; queued = [%a]}"
    q.waiting q.failed q.sending
    (Format.pp_print_option
       ~none:(fun f () -> Format.pp_print_string f "None")
       (Ptime.pp_rfc3339 ()))
    q.last_upload
    (Format.pp_print_list
       ~pp_sep:(fun f () -> Format.pp_print_string f "; ")
       Ids.Photo_id.pp)
    q.queued

let queue_t = Alcotest.testable pp_queue Drive_text.equal_queue

let pp_viewer_drive ppf = function
  | Drive_text.Open s -> Format.fprintf ppf "Open %S" s
  | Missing -> Format.pp_print_string ppf "Missing"
  | Hidden -> Format.pp_print_string ppf "Hidden"

let viewer_drive_t =
  Alcotest.testable pp_viewer_drive Drive_text.equal_viewer_drive

let prompt_opt (p : Drive_text.prompt option) =
  Option.map (fun (p : Drive_text.prompt) -> (p.text, p.action)) p

let prompt_option_t = Alcotest.(option (pair string (option string)))

let card_opt (c : Drive_text.card option) =
  Option.map (fun (c : Drive_text.card) -> (c.title, c.detail)) c

let card_option_t = Alcotest.(option (pair string string))

let pp_folder ppf = function
  | Drive_text.Default -> Format.pp_print_string ppf "Default"
  | Drive_text.Picked n -> Format.fprintf ppf "Picked %S" n

let folder_t = Alcotest.testable pp_folder Drive_text.equal_folder

let pp_folder_button ppf (b : Drive_text.folder_button) =
  Format.fprintf ppf "{detail = %S; choose = %s}" b.detail
    (match b.choose with
    | Enabled -> "Enabled"
    | Disabled reason -> Printf.sprintf "Disabled %S" reason)

let folder_button_t =
  Alcotest.testable pp_folder_button Drive_text.equal_folder_button

let pick_error_to_string = function
  | Drive_text.Not_a_folder -> "Not_a_folder"
  | Drive_text.Trashed -> "Trashed"
  | Drive_text.No_access -> "No_access"
  | Drive_text.Offline -> "Offline"
  | Drive_text.Token d -> "Token " ^ denial_to_string d
  | Drive_text.Picker_unavailable -> "Picker_unavailable"
  | Drive_text.Not_saved -> "Not_saved"
  | Drive_text.Drive_failed -> "Drive_failed"
  | Drive_text.Chooser_no_account -> "Chooser_no_account"
  | Drive_text.Chooser_failed -> "Chooser_failed"
  | Drive_text.Other_account d -> "Other_account " ^ denial_to_string d

let pp_pick_error ppf e = Format.pp_print_string ppf (pick_error_to_string e)
let pick_error_t = Alcotest.testable pp_pick_error Drive_text.equal_pick_error

(* ---------- access ---------- *)

let access_tests =
  let case name drive last expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check access_t "access" expected
          (Drive_text.access ~drive ~last) )
  in
  let chosen = Drive_account.Chosen {email = "a@b.c"} in
  Drive_text.
    [
      case "Unconfigured, last Unknown: Denied Unconfigured"
        Drive_account.Unconfigured Unknown (Denied Unconfigured);
      case "Unconfigured, last Granted: Denied Unconfigured (whatever last was)"
        Drive_account.Unconfigured Granted (Denied Unconfigured);
      case "Unconfigured, last Denied Consent_needed: Denied Unconfigured"
        Drive_account.Unconfigured (Denied Consent_needed) (Denied Unconfigured);
      case "Unconfigured, last Denied No_drive_account: Denied Unconfigured"
        Drive_account.Unconfigured (Denied No_drive_account)
        (Denied Unconfigured);
      case "Unchosen, last Unknown: Denied No_drive_account"
        Drive_account.Unchosen Unknown (Denied No_drive_account);
      case "Unchosen, last Granted: Denied No_drive_account (whatever last was)"
        Drive_account.Unchosen Granted (Denied No_drive_account);
      case "Unchosen, last Denied Consent_needed: Denied No_drive_account"
        Drive_account.Unchosen (Denied Consent_needed) (Denied No_drive_account);
      case "Chosen, last Unknown: Unknown" chosen Unknown Unknown;
      case
        "Chosen, last Granted: Granted (no session argument at all: a \
         signed-out user with a chosen account is not denied)"
        chosen Granted Granted;
      case "Chosen, last Denied Consent_needed: kept, Denied Consent_needed"
        chosen (Denied Consent_needed) (Denied Consent_needed);
      case
        "Chosen, last Denied No_drive_account (stale, from before this account \
         was chosen): cleared to Unknown"
        chosen (Denied No_drive_account) Unknown;
      case
        "Chosen, last Denied Unconfigured (stale, from an earlier build): \
         cleared to Unknown"
        chosen (Denied Unconfigured) Unknown;
    ]

(* ---------- queue_of, pending_count ---------- *)

let entry ?state ?(running = false) n : Drive_text.entry =
  {Drive_text.photo_id = photo_id n; state; running}

let queue_of_tests =
  [
    ( "waiting (Pending) and failed counted; a running Pending also counts as \
       sending; an absent photo and a terminal state (Uploaded, \
       Original_missing) are not counted; every row's photo is queued; \
       last_upload passed through",
      `Quick,
      fun () ->
        let entries =
          Photo.Upload_state.
            [
              entry ~state:Pending 1;
              entry ~state:Pending ~running:true 2;
              entry ~state:Failed 3;
              entry ~state:Uploaded 4;
              entry 5;
              entry ~state:Original_missing 6;
            ]
        in
        let last_upload = Some (Value.time "2026-06-01T00:00:00Z") in
        let q = Drive_text.queue_of ~last_upload entries in
        Alcotest.check queue_t "queue_of"
          {
            Drive_text.waiting = 2;
            failed = 1;
            sending = 1;
            last_upload;
            queued = List.map photo_id [1; 2; 3; 4; 5; 6];
          }
          q;
        Alcotest.(check int) "pending_count" 3 (Drive_text.pending_count q) );
    ( "a running Failed row is failed, not sending",
      `Quick,
      fun () ->
        Alcotest.check queue_t "queue_of"
          {
            Drive_text.waiting = 0;
            failed = 1;
            sending = 0;
            last_upload = None;
            queued = [photo_id 1];
          }
          (Drive_text.queue_of ~last_upload:None
             [entry ~state:Photo.Upload_state.Failed ~running:true 1]) );
    ( "the empty list is empty_queue",
      `Quick,
      fun () ->
        Alcotest.check queue_t "queue_of []" Drive_text.empty_queue
          (Drive_text.queue_of ~last_upload:None []) );
  ]

(* ---------- queue_title ---------- *)

let queue ?(waiting = 0) ?(failed = 0) ?(sending = 0) ?(last_upload = None) () :
    Drive_text.queue =
  {Drive_text.waiting; failed; sending; last_upload; queued = []}

let queue_title_tests =
  [
    ( "0 waiting, 0 failed: \"Aucune photo en attente\"",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "queue_title" "Aucune photo en attente"
          (Drive_text.queue_title (queue ())) );
    ( "1 waiting: \"1 photo en attente\"",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "queue_title" "1 photo en attente"
          (Drive_text.queue_title (queue ~waiting:1 ())) );
    ( "3 waiting: \"3 photos en attente\"",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "queue_title" "3 photos en attente"
          (Drive_text.queue_title (queue ~waiting:3 ())) );
    ( "2 waiting + 1 failed (3 pending total): the failed count is appended to \
       the total",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "queue_title" "3 photos en attente \xc2\xb7 1 en \xc3\xa9chec"
          (Drive_text.queue_title (queue ~waiting:2 ~failed:1 ())) );
    ( "only failed: counted in the total and appended",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "queue_title" "1 photo en attente \xc2\xb7 1 en \xc3\xa9chec"
          (Drive_text.queue_title (queue ~failed:1 ())) );
  ]

(* ---------- blocker ---------- *)

let no_drive_account_text =
  "Choisissez le compte Google dans \xc2\xab Dossier Drive \xc2\xbb."

let not_authorized_text =
  "Google Drive n’est pas autorisé : autorisez-le, ou changez de compte dans « \
   Dossier Drive »."

let no_account_text =
  "Ce compte Google n\xe2\x80\x99est plus sur le t\xc3\xa9l\xc3\xa9phone : \
   changez-le dans \xc2\xab Dossier Drive \xc2\xbb."

let blocker_tests =
  let case name access ~online expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "blocker" expected
          (Drive_text.blocker access ~online) )
  in
  Drive_text.
    [
      case "Denied Unconfigured" (Denied Unconfigured) ~online:true
        (Some "Envoi vers Drive indisponible dans cette version.");
      case "Denied No_drive_account: points to Dossier Drive"
        (Denied No_drive_account) ~online:true (Some no_drive_account_text);
      case "Denied Consent_needed" (Denied Consent_needed) ~online:true
        (Some not_authorized_text);
      case "Denied Consent_refused" (Denied Consent_refused) ~online:true
        (Some not_authorized_text);
      case
        "Denied No_account: the chosen account is gone, points to Dossier Drive"
        (Denied No_account) ~online:true (Some no_account_text);
      case "Denied Misconfigured" (Denied Misconfigured) ~online:true
        (Some
           "Google refuse l\xe2\x80\x99acc\xc3\xa8s \xc3\xa0 Drive \
            (configuration de l\xe2\x80\x99app).");
      case "Denied Offline, online: true (the denial wins)" (Denied Offline)
        ~online:true (Some "Envoi d\xc3\xa8s le retour du r\xc3\xa9seau.");
      case "Denied Failed, online: true" (Denied Failed) ~online:true
        (Some "Envoi d\xc3\xa8s le retour du r\xc3\xa9seau.");
      case "Granted, offline: the network text, not None" Granted ~online:false
        (Some "Envoi d\xc3\xa8s le retour du r\xc3\xa9seau.");
      case "Granted, online: None" Granted ~online:true None;
      case "Unknown, online: None" Unknown ~online:true None;
      case "Denied Unconfigured, offline: its own text, not the network's"
        (Denied Unconfigured) ~online:false
        (Some "Envoi vers Drive indisponible dans cette version.");
      case "Denied No_drive_account, offline: its own text"
        (Denied No_drive_account) ~online:false (Some no_drive_account_text);
      case "Denied Consent_needed, offline: not authorized"
        (Denied Consent_needed) ~online:false (Some not_authorized_text);
      case "Denied Consent_refused, offline: not authorized"
        (Denied Consent_refused) ~online:false (Some not_authorized_text);
      case "Denied No_account, offline: its own text" (Denied No_account)
        ~online:false (Some no_account_text);
      case "Denied Misconfigured, offline: misconfigured" (Denied Misconfigured)
        ~online:false
        (Some
           "Google refuse l\xe2\x80\x99acc\xc3\xa8s \xc3\xa0 Drive \
            (configuration de l\xe2\x80\x99app).");
    ]

(* No denial's text invites a sign-in (the Drive account is not the Supabase
   session), and every denial the user can act on in the « Dossier Drive »
   sheet names it. *)
let blocker_never_says_connectez_vous () =
  List.iter
    (fun d ->
      match Drive_text.blocker (Drive_text.Denied d) ~online:true with
      | None -> ()
      | Some text ->
          Alcotest.(check bool)
            (Printf.sprintf "%s: no \xc2\xab Connectez-vous \xc2\xbb"
               (denial_to_string d))
            false
            (Text.contains ~sub:"Connectez-vous" text))
    all_denials;
  List.iter
    (fun d ->
      match
        Drive_text.drive_prompt ~storage:Photo.Original_target.Drive ~pending:1
          (Drive_text.Denied d)
      with
      | None -> ()
      | Some (p : Drive_text.prompt) ->
          Alcotest.(check bool)
            (Printf.sprintf
               "drive_prompt %s: no \xc2\xab Connectez-vous \xc2\xbb"
               (denial_to_string d))
            false
            (Text.contains ~sub:"Connectez-vous" p.text))
    all_denials

let blocker_account_denials_name_dossier_drive () =
  List.iter
    (fun d ->
      match Drive_text.blocker (Drive_text.Denied d) ~online:true with
      | Some text ->
          Alcotest.(check bool)
            (Printf.sprintf "%s names \xc2\xab Dossier Drive \xc2\xbb"
               (denial_to_string d))
            true
            (Text.contains ~sub:"Dossier Drive" text)
      | None ->
          Alcotest.failf "%s: expected a blocker text" (denial_to_string d))
    Drive_text.[No_drive_account; No_account; Consent_needed; Consent_refused]

let consent_prompts_name_dossier_drive () =
  List.iter
    (fun d ->
      match
        Drive_text.drive_prompt ~storage:Photo.Original_target.Drive ~pending:1
          (Drive_text.Denied d)
      with
      | Some (p : Drive_text.prompt) ->
          Alcotest.(check bool)
            (Printf.sprintf "drive_prompt %s names « Dossier Drive »"
               (denial_to_string d))
            true
            (Text.contains ~sub:"Dossier Drive" p.text)
      | None -> Alcotest.failf "%s: expected a prompt" (denial_to_string d))
    Drive_text.[Consent_needed; Consent_refused]

let blocker_extra_tests =
  [
    ( "no denial's text says \xc2\xab Connectez-vous \xc2\xbb any more",
      `Quick,
      blocker_never_says_connectez_vous );
    ( "No_drive_account, No_account and the consent denials name \xc2\xab \
       Dossier Drive \xc2\xbb",
      `Quick,
      blocker_account_denials_name_dossier_drive );
    ( "the 4m consent prompts name « Dossier Drive »",
      `Quick,
      consent_prompts_name_dossier_drive );
  ]

(* ---------- queue_status ---------- *)

let queue_status_tests =
  Drive_text.
    [
      ( "an empty queue is None whatever the access (Denied)",
        `Quick,
        fun () ->
          Alcotest.(check (option string))
            "queue_status" None
            (Drive_text.queue_status (Denied Unconfigured) ~online:true
               ~wifi_only:false (queue ())) );
      ( "an empty queue is None whatever the access (Granted)",
        `Quick,
        fun () ->
          Alcotest.(check (option string))
            "queue_status" None
            (Drive_text.queue_status Granted ~online:true ~wifi_only:false
               (queue ())) );
      ( "blocker wins first",
        `Quick,
        fun () ->
          Alcotest.(check (option string))
            "queue_status" (Some no_drive_account_text)
            (Drive_text.queue_status (Denied No_drive_account) ~online:true
               ~wifi_only:false (queue ~waiting:1 ())) );
      ( "failed, no blocker: the retry text",
        `Quick,
        fun () ->
          Alcotest.(check (option string))
            "queue_status"
            (Some
               "\xc3\x89chec de l\xe2\x80\x99envoi : \xc2\xab Envoyer \
                maintenant \xc2\xbb pour r\xc3\xa9essayer.")
            (Drive_text.queue_status Granted ~online:true ~wifi_only:false
               (queue ~failed:1 ())) );
      ( "sending, no blocker, no failed: in progress",
        `Quick,
        fun () ->
          Alcotest.(check (option string))
            "queue_status" (Some "Envoi en cours\xe2\x80\xa6")
            (Drive_text.queue_status Granted ~online:true ~wifi_only:false
               (queue ~waiting:1 ~sending:1 ())) );
      ( "wifi_only, no blocker, no failed, nothing sending",
        `Quick,
        fun () ->
          Alcotest.(check (option string))
            "queue_status" (Some "Envoi en Wi-Fi seulement.")
            (Drive_text.queue_status Granted ~online:true ~wifi_only:true
               (queue ~waiting:1 ())) );
      ( "the default: waiting",
        `Quick,
        fun () ->
          Alcotest.(check (option string))
            "queue_status" (Some "Envoi en attente.")
            (Drive_text.queue_status Granted ~online:true ~wifi_only:false
               (queue ~waiting:1 ())) );
      ( "failed beats sending and wifi_only",
        `Quick,
        fun () ->
          Alcotest.(check (option string))
            "queue_status"
            (Some
               "\xc3\x89chec de l\xe2\x80\x99envoi : \xc2\xab Envoyer \
                maintenant \xc2\xbb pour r\xc3\xa9essayer.")
            (Drive_text.queue_status Granted ~online:true ~wifi_only:true
               (queue ~waiting:1 ~failed:1 ~sending:1 ())) );
      ( "sending beats wifi_only",
        `Quick,
        fun () ->
          Alcotest.(check (option string))
            "queue_status" (Some "Envoi en cours\xe2\x80\xa6")
            (Drive_text.queue_status Granted ~online:true ~wifi_only:true
               (queue ~waiting:1 ~sending:1 ())) );
      ( "a blocker beats failed",
        `Quick,
        fun () ->
          Alcotest.(check (option string))
            "queue_status" (Some no_drive_account_text)
            (Drive_text.queue_status (Denied No_drive_account) ~online:true
               ~wifi_only:false (queue ~failed:1 ())) );
    ]

(* ---------- last_sent ---------- *)

let last_sent_tests =
  [
    ( "the same local day, tz +3600: \"aujourd'hui, HH:MM\"",
      `Quick,
      fun () ->
        let now = utc 2026 6 12 13 7 in
        Alcotest.(check string)
          "last_sent" "Dernier envoi : aujourd\xe2\x80\x99hui, 14:07"
          (Drive_text.last_sent ~now ~tz_offset_s:3600 (Some now)) );
    ( "the same local day, tz +7200",
      `Quick,
      fun () ->
        let now = utc 2026 6 12 12 7 in
        Alcotest.(check string)
          "last_sent" "Dernier envoi : aujourd\xe2\x80\x99hui, 14:07"
          (Drive_text.last_sent ~now ~tz_offset_s:7200 (Some now)) );
    ( "an instant that crosses midnight in UTC lands on the right local day \
       (one local day before now, not two): \"hier\"",
      `Quick,
      fun () ->
        let now = utc 2026 6 13 10 0 in
        (* 23:30 UTC on the 11th is 00:30 local (+1 h) on the 12th: one
           local day, not two, before now's local day (the 13th). *)
        let last_upload = utc 2026 6 11 23 30 in
        Alcotest.(check string)
          "last_sent" "Dernier envoi : hier, 00:30"
          (Drive_text.last_sent ~now ~tz_offset_s:3600 (Some last_upload)) );
    ( "two local days ago: day_header, no year (this year)",
      `Quick,
      fun () ->
        let now = utc 2026 6 13 10 0 in
        let last_upload = utc 2026 6 11 8 15 in
        Alcotest.(check string)
          "last_sent" "Dernier envoi : Jeu. 11 juin, 09:15"
          (Drive_text.last_sent ~now ~tz_offset_s:3600 (Some last_upload)) );
    ( "the previous year: day_header shows the year",
      `Quick,
      fun () ->
        let now = utc 2026 6 13 10 0 in
        let last_upload = utc 2025 12 31 17 0 in
        Alcotest.(check string)
          "last_sent" "Dernier envoi : Mer. 31 d\xc3\xa9cembre 2025, 18:00"
          (Drive_text.last_sent ~now ~tz_offset_s:3600 (Some last_upload)) );
    ( "None: never sent",
      `Quick,
      fun () ->
        let now = utc 2026 6 13 10 0 in
        Alcotest.(check string)
          "last_sent" "Aucun envoi pour l\xe2\x80\x99instant."
          (Drive_text.last_sent ~now ~tz_offset_s:3600 None) );
    ( "an instant after now reads as today",
      `Quick,
      fun () ->
        let now = utc 2026 6 13 10 0 in
        let later = utc 2026 6 13 11 0 in
        Alcotest.(check string)
          "last_sent" "Dernier envoi : aujourd\xe2\x80\x99hui, 12:00"
          (Drive_text.last_sent ~now ~tz_offset_s:3600 (Some later)) );
  ]

(* ---------- send_enabled ---------- *)

let send_enabled_tests =
  [
    ( "empty_queue: false",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "send_enabled" false
          (Drive_text.send_enabled Drive_text.empty_queue) );
    ( "some waiting: true",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "send_enabled" true
          (Drive_text.send_enabled (queue ~waiting:1 ())) );
    ( "only failed: true",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "send_enabled" true
          (Drive_text.send_enabled (queue ~failed:1 ())) );
  ]

(* ---------- account_meta ---------- *)

(* account_meta is the sync (Supabase) account's address, or its fallback,
   with no Drive suffix: the Drive account may differ. *)
let account_meta_tests =
  [
    ( "an address: itself, verbatim",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "account_meta" "a@b"
          (Drive_text.account_meta ~email:(Some "a@b")) );
    ( "no address: the fallback text",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "account_meta" "Adresse inconnue"
          (Drive_text.account_meta ~email:None) );
  ]

(* ---------- drive_prompt ---------- *)

let drive_prompt_tests =
  let consent_prompt =
    Some
      ( "Google Drive n’est pas autorisé pour ce compte : les photos attendent \
         sur le téléphone. Autorisez-le, ou changez de compte dans « Dossier \
         Drive ».",
        Some "Autoriser" )
  in
  let no_drive_account_prompt =
    Some
      ( "Les photos attendent sur le t\xc3\xa9l\xc3\xa9phone : choisissez le \
         compte et le dossier dans \xc2\xab Dossier Drive \xc2\xbb.",
        None )
  in
  let case ?(pending = 0) name storage access expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check prompt_option_t "drive_prompt" expected
          (prompt_opt (Drive_text.drive_prompt ~storage ~pending access)) )
  in
  let module O = Photo.Original_target in
  let module D = Drive_text in
  [
    case "App_only, Granted: None" O.App_only D.Granted None;
    case "App_only, Denied Consent_needed: None" O.App_only
      (D.Denied D.Consent_needed) None;
    case "Drive, Denied Consent_needed: the consent prompt" O.Drive
      (D.Denied D.Consent_needed) consent_prompt;
    case "Drive, Denied Consent_refused: the consent prompt" O.Drive
      (D.Denied D.Consent_refused) consent_prompt;
    case "Drive, Denied No_account: its blocker text, no action" O.Drive
      (D.Denied D.No_account)
      (Some (no_account_text, None));
    case "Drive, Denied Misconfigured: its blocker text, no action" O.Drive
      (D.Denied D.Misconfigured)
      (Some
         ( "Google refuse l\xe2\x80\x99acc\xc3\xa8s \xc3\xa0 Drive \
            (configuration de l\xe2\x80\x99app).",
           None ));
    case "Drive, Denied No_drive_account: choose the account, no action" O.Drive
      (D.Denied D.No_drive_account) no_drive_account_prompt;
    case "Drive, Denied Unconfigured: None" O.Drive (D.Denied D.Unconfigured)
      None;
    case "Drive, Denied Offline: None" O.Drive (D.Denied D.Offline) None;
    case "Drive, Denied Failed: None" O.Drive (D.Denied D.Failed) None;
    case "Drive, Granted: None" O.Drive D.Granted None;
    case "Drive, Unknown: None" O.Drive D.Unknown None;
    case ~pending:2
      "App_only with photos still waiting, Denied Consent_needed: the consent \
       prompt"
      O.App_only (D.Denied D.Consent_needed) consent_prompt;
    case ~pending:1
      "App_only with a photo waiting, Denied No_drive_account: choose the \
       account"
      O.App_only (D.Denied D.No_drive_account) no_drive_account_prompt;
    case ~pending:1 "App_only with a photo waiting, Granted: None" O.App_only
      D.Granted None;
  ]

(* ---------- stop_dialog ---------- *)

let dialog (d : Drive_text.dialog) = (d.title, d.text)

let stop_dialog_tests =
  [
    ( "1 photo",
      `Quick,
      fun () ->
        Alcotest.(check (pair string string))
          "stop_dialog 1"
          ( "1 photo attend l\xe2\x80\x99envoi vers Drive",
            "Sans envoi, leur original est effac\xc3\xa9 du \
             t\xc3\xa9l\xc3\xa9phone ; la copie compress\xc3\xa9e reste." )
          (dialog (Drive_text.stop_dialog 1)) );
    ( "3 photos",
      `Quick,
      fun () ->
        Alcotest.(check (pair string string))
          "stop_dialog 3"
          ( "3 photos attendent l\xe2\x80\x99envoi vers Drive",
            "Sans envoi, leur original est effac\xc3\xa9 du \
             t\xc3\xa9l\xc3\xa9phone ; la copie compress\xc3\xa9e reste." )
          (dialog (Drive_text.stop_dialog 3)) );
  ]

(* ---------- folder, folder_name ---------- *)

let drive_folder ~id ~name : Herbier_store.Settings.drive_folder = {id; name}

let folder_tests =
  let case name ~root ~picked expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check folder_t "folder" expected
          (Drive_text.folder ~root ~picked) )
  in
  [
    case "picked id = root: Picked, the picked name" ~root:(Some "F1")
      ~picked:(Some (drive_folder ~id:"F1" ~name:"Mes plantes"))
      (Drive_text.Picked "Mes plantes");
    case "picked id <> root (a pass replaced it): Default" ~root:(Some "OTHER")
      ~picked:(Some (drive_folder ~id:"F1" ~name:"Mes plantes"))
      Drive_text.Default;
    case "root None, picked present: Default" ~root:None
      ~picked:(Some (drive_folder ~id:"F1" ~name:"Mes plantes"))
      Drive_text.Default;
    case "root present, no picked value: Default" ~root:(Some "F1") ~picked:None
      Drive_text.Default;
    case "neither root nor picked: Default" ~root:None ~picked:None
      Drive_text.Default;
  ]

let folder_name_tests =
  [
    ( "Default: \"Herbier\"",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "folder_name" "Herbier"
          (Drive_text.folder_name Drive_text.Default) );
    ( "Picked n: n verbatim",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "folder_name" "Mes plantes"
          (Drive_text.folder_name (Drive_text.Picked "Mes plantes")) );
    ( "Picked \"\" (blank): \"(sans nom)\"",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "folder_name" "(sans nom)"
          (Drive_text.folder_name (Drive_text.Picked "")) );
    ( "Picked \"  \" (whitespace only): \"(sans nom)\"",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "folder_name" "(sans nom)"
          (Drive_text.folder_name (Drive_text.Picked "  ")) );
  ]

(* ---------- folder_button ---------- *)

(* folder_button is the single « Dossier Drive » button. The Picker's
   availability never disables it (the sheet still chooses the account
   without it): only the Drive account's state does. *)
let unconfigured_reason = "Envoi vers Drive indisponible dans cette version."
let herbier_detail = "Herbier \xc2\xb7 cr\xc3\xa9\xc3\xa9 par l\xe2\x80\x99app"
let chosen_a = Drive_account.Chosen {email = "a@x.fr"}

let folder_button_tests =
  let case name drive folder expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check folder_button_t "folder_button" expected
          (Drive_text.folder_button ~drive folder) )
  in
  Drive_text.
    [
      case
        "Unconfigured, Default: disabled, the build reason, detail \xc2\xab \
         Herbier \xc2\xbb alone (no email, no account known)"
        Drive_account.Unconfigured Default
        {detail = "Herbier"; choose = Disabled unconfigured_reason};
      case
        "Unconfigured, Picked: still \xc2\xab Herbier \xc2\xbb alone - the \
         folder is irrelevant without a usable build"
        Drive_account.Unconfigured (Picked "Mes plantes")
        {detail = "Herbier"; choose = Disabled unconfigured_reason};
      case "Unchosen, Default: enabled, no account chosen yet, no reason"
        Drive_account.Unchosen Default
        {detail = "Aucun compte choisi"; choose = Enabled};
      case
        "Unchosen, Picked: still \xc2\xab Aucun compte choisi \xc2\xbb - the \
         folder belongs to no account yet"
        Drive_account.Unchosen (Picked "Mes plantes")
        {detail = "Aucun compte choisi"; choose = Enabled};
      case
        "Chosen, Default: Herbier, created by the app, then this account's \
         email"
        chosen_a Default
        {detail = herbier_detail ^ " \xc2\xb7 a@x.fr"; choose = Enabled};
      case "Chosen, Picked: the picked name, then this account's email" chosen_a
        (Picked "Mes plantes")
        {detail = "Mes plantes \xc2\xb7 a@x.fr"; choose = Enabled};
      case "Chosen, Picked \"\": the blank-name fallback, then the email"
        chosen_a (Picked "")
        {detail = "(sans nom) \xc2\xb7 a@x.fr"; choose = Enabled};
    ]

(* ---------- picker_config_of_project_number ---------- *)

let picker_config_tests =
  let case name number ready =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "Picker_ready" ready
          (Drive_text.equal_picker_config
             (Drive_text.picker_config_of_project_number number)
             Picker_ready) )
  in
  [
    case "\"\": unconfigured" "" false;
    case "all digits: ready" "123456789012" true;
    case "a leading space: unconfigured (not trimmed)" " 123" false;
    case "a trailing newline: unconfigured (not trimmed)" "123\n" false;
    case "letters: unconfigured" "abc" false;
    case "a placeholder: unconfigured" "<project-number>" false;
  ]

(* ---------- pick_error_text ---------- *)

let pick_error_text_tests =
  let case name e expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check string)
          "pick_error_text" expected
          (Drive_text.pick_error_text e) )
  in
  Drive_text.
    [
      case "Not_a_folder" Not_a_folder "Ce n\xe2\x80\x99est pas un dossier.";
      case "Trashed" Trashed "Ce dossier est dans la corbeille.";
      case "No_access" No_access
        "Herbier n\xe2\x80\x99a pas acc\xc3\xa8s \xc3\xa0 ce dossier.";
      case "Offline" Offline
        "Pas de r\xc3\xa9seau : r\xc3\xa9essayez plus tard.";
      case "Token Unconfigured" (Token Unconfigured)
        "Envoi vers Drive indisponible dans cette version.";
      case "Token No_drive_account (blocker (Denied d) ~online:true)"
        (Token No_drive_account) no_drive_account_text;
      case "Token Consent_needed: this account, inside the sheet"
        (Token Consent_needed) "Google Drive n’est pas autorisé pour ce compte.";
      case "Token Consent_refused: this account, inside the sheet"
        (Token Consent_refused)
        "Google Drive n’est pas autorisé pour ce compte.";
      case "Token No_account: inside the sheet, use another account"
        (Token No_account)
        "Ce compte Google n’est plus sur le téléphone : utilisez un autre \
         compte.";
      case "Token Misconfigured" (Token Misconfigured)
        "Google refuse l\xe2\x80\x99acc\xc3\xa8s \xc3\xa0 Drive (configuration \
         de l\xe2\x80\x99app).";
      case "Token Offline" (Token Offline)
        "Envoi d\xc3\xa8s le retour du r\xc3\xa9seau.";
      case "Token Failed: retry or another account, not the network line"
        (Token Failed)
        "Google Drive n’a pas répondu pour ce compte : réessayez, ou utilisez \
         un autre compte.";
      case "Picker_unavailable" Picker_unavailable
        "Google Picker n\xe2\x80\x99a pas pu s\xe2\x80\x99ouvrir.";
      case "Not_saved" Not_saved
        "Le r\xc3\xa9glage n\xe2\x80\x99a pas pu \xc3\xaatre enregistr\xc3\xa9.";
      case "Drive_failed" Drive_failed
        "Drive n\xe2\x80\x99a pas r\xc3\xa9pondu : r\xc3\xa9essayez.";
      case "Chooser_no_account" Chooser_no_account
        "Aucun compte Google sur le t\xc3\xa9l\xc3\xa9phone : ajoutez-en un \
         dans les r\xc3\xa9glages d\xe2\x80\x99Android.";
      case "Chooser_failed" Chooser_failed
        "Le choix du compte n\xe2\x80\x99a pas pu s\xe2\x80\x99ouvrir. \
         R\xc3\xa9essayez.";
      case "Other_account Offline" (Other_account Offline)
        "Pas de réseau : rien n’a changé.";
      case "Other_account Consent_refused" (Other_account Consent_refused)
        "L’autre compte n’a pas autorisé Google Drive : rien n’a changé.";
      case "Other_account Consent_needed" (Other_account Consent_needed)
        "L’autre compte n’a pas autorisé Google Drive : rien n’a changé.";
      case "Other_account No_account" (Other_account No_account)
        "L’autre compte n’a pas pu être utilisé : rien n’a changé.";
      case "Other_account Failed" (Other_account Failed)
        "L’autre compte n’a pas pu être utilisé : rien n’a changé.";
    ]

(* ---------- saved_card ---------- *)

let saved_card ?(queued = []) ?(folder = Drive_text.Default) access ~online
    ~wifi_only photos =
  Drive_text.saved_card access ~online ~wifi_only ~queued ~folder photos

let saved_card_tests =
  [
    ( "no Drive-bound photo: None",
      `Quick,
      fun () ->
        Alcotest.check card_option_t "saved_card" None
          (card_opt
             (saved_card Drive_text.Granted ~online:true ~wifi_only:false
                [photo ~target:Photo.Original_target.App_only 1])) );
    ( "2 Uploaded: the title counts them, detail says sent",
      `Quick,
      fun () ->
        let photos =
          [
            photo ~state:Photo.Upload_state.Uploaded 1;
            photo ~state:Photo.Upload_state.Uploaded 2;
          ]
        in
        Alcotest.check card_option_t "saved_card"
          (Some
             ( "2 photos \xe2\x86\x92 Google Drive, dossier Herbier",
               "Envoy\xc3\xa9es dans Google Drive. Copies compress\xc3\xa9es \
                gard\xc3\xa9es sur le t\xc3\xa9l\xc3\xa9phone." ))
          (card_opt
             (saved_card Drive_text.Granted ~online:true ~wifi_only:false photos))
    );
    ( "1 Uploaded (singular agreement)",
      `Quick,
      fun () ->
        let photos = [photo ~state:Photo.Upload_state.Uploaded 1] in
        Alcotest.check card_option_t "saved_card"
          (Some
             ( "1 photo \xe2\x86\x92 Google Drive, dossier Herbier",
               "Envoy\xc3\xa9e dans Google Drive. Copies compress\xc3\xa9es \
                gard\xc3\xa9es sur le t\xc3\xa9l\xc3\xa9phone." ))
          (card_opt
             (saved_card Drive_text.Granted ~online:true ~wifi_only:false photos))
    );
    ( "1 Uploaded + 1 Original_missing: the missing text wins",
      `Quick,
      fun () ->
        let photos =
          [
            photo ~state:Photo.Upload_state.Uploaded 1;
            photo ~state:Photo.Upload_state.Original_missing 2;
          ]
        in
        Alcotest.check card_option_t "saved_card"
          (Some
             ( "2 photos \xe2\x86\x92 Google Drive, dossier Herbier",
               "Original introuvable dans Google Drive : la copie \
                compress\xc3\xa9e reste." ))
          (card_opt
             (saved_card Drive_text.Granted ~online:true ~wifi_only:false photos))
    );
    ( "a Failed photo beats a blocking access",
      `Quick,
      fun () ->
        let photos = [photo ~state:Photo.Upload_state.Failed 1] in
        Alcotest.check card_option_t "saved_card"
          (Some
             ( "1 photo \xe2\x86\x92 Google Drive, dossier Herbier",
               "\xc3\x89chec de l\xe2\x80\x99envoi : \xc2\xab Envoyer \
                maintenant \xc2\xbb dans R\xc3\xa9glages." ))
          (card_opt
             (saved_card
                ~queued:[photo_id 1]
                (Drive_text.Denied Drive_text.No_drive_account) ~online:true
                ~wifi_only:false photos)) );
    ( "a Failed photo without a queue row: its original was not kept",
      `Quick,
      fun () ->
        let photos = [photo ~state:Photo.Upload_state.Failed 1] in
        Alcotest.check card_option_t "saved_card"
          (Some
             ( "1 photo \xe2\x86\x92 Google Drive, dossier Herbier",
               "Original non conserv\xc3\xa9 : la copie compress\xc3\xa9e \
                reste." ))
          (card_opt
             (saved_card
                ~queued:[photo_id 2]
                Drive_text.Granted ~online:true ~wifi_only:false photos)) );
    ( "a Failed photo with a row beats one without",
      `Quick,
      fun () ->
        let photos =
          [
            photo ~state:Photo.Upload_state.Failed 1;
            photo ~state:Photo.Upload_state.Failed 2;
          ]
        in
        Alcotest.check card_option_t "saved_card"
          (Some
             ( "2 photos \xe2\x86\x92 Google Drive, dossier Herbier",
               "\xc3\x89chec de l\xe2\x80\x99envoi : \xc2\xab Envoyer \
                maintenant \xc2\xbb dans R\xc3\xa9glages." ))
          (card_opt
             (saved_card
                ~queued:[photo_id 2]
                Drive_text.Granted ~online:true ~wifi_only:false photos)) );
    ( "Original_missing beats Failed",
      `Quick,
      fun () ->
        let photos =
          [
            photo ~state:Photo.Upload_state.Original_missing 1;
            photo ~state:Photo.Upload_state.Failed 2;
          ]
        in
        Alcotest.check card_option_t "saved_card"
          (Some
             ( "2 photos \xe2\x86\x92 Google Drive, dossier Herbier",
               "Original introuvable dans Google Drive : la copie \
                compress\xc3\xa9e reste." ))
          (card_opt
             (saved_card
                ~queued:[photo_id 2]
                Drive_text.Granted ~online:true ~wifi_only:false photos)) );
    ( "a blocker beats the fraction",
      `Quick,
      fun () ->
        let photos =
          [
            photo ~state:Photo.Upload_state.Uploaded 1;
            photo ~state:Photo.Upload_state.Pending 2;
          ]
        in
        Alcotest.check card_option_t "saved_card"
          (Some
             ( "2 photos \xe2\x86\x92 Google Drive, dossier Herbier",
               no_drive_account_text ))
          (card_opt
             (saved_card (Drive_text.Denied Drive_text.No_drive_account)
                ~online:true ~wifi_only:false photos)) );
    ( "wifi_only beats the fraction",
      `Quick,
      fun () ->
        let photos =
          [
            photo ~state:Photo.Upload_state.Uploaded 1;
            photo ~state:Photo.Upload_state.Pending 2;
            photo ~state:Photo.Upload_state.Pending 3;
          ]
        in
        Alcotest.check card_option_t "saved_card"
          (Some
             ( "3 photos \xe2\x86\x92 Google Drive, dossier Herbier",
               "Envoi en Wi-Fi seulement. Copies compress\xc3\xa9es \
                gard\xc3\xa9es sur le t\xc3\xa9l\xc3\xa9phone." ))
          (card_opt
             (saved_card Drive_text.Granted ~online:true ~wifi_only:true photos))
    );
    ( "offline, Pending: the network blocker text",
      `Quick,
      fun () ->
        let photos = [photo ~state:Photo.Upload_state.Pending 1] in
        Alcotest.check card_option_t "saved_card"
          (Some
             ( "1 photo \xe2\x86\x92 Google Drive, dossier Herbier",
               "Envoi d\xc3\xa8s le retour du r\xc3\xa9seau." ))
          (card_opt
             (saved_card Drive_text.Granted ~online:false ~wifi_only:false
                photos)) );
    ( "Denied No_drive_account, nothing failed: points to Dossier Drive",
      `Quick,
      fun () ->
        let photos = [photo ~state:Photo.Upload_state.Pending 1] in
        Alcotest.check card_option_t "saved_card"
          (Some
             ( "1 photo \xe2\x86\x92 Google Drive, dossier Herbier",
               no_drive_account_text ))
          (card_opt
             (saved_card (Drive_text.Denied Drive_text.No_drive_account)
                ~online:true ~wifi_only:false photos)) );
    ( "wifi_only, no blocker, nothing failed or missing",
      `Quick,
      fun () ->
        let photos = [photo ~state:Photo.Upload_state.Pending 1] in
        Alcotest.check card_option_t "saved_card"
          (Some
             ( "1 photo \xe2\x86\x92 Google Drive, dossier Herbier",
               "Envoi en Wi-Fi seulement. Copies compress\xc3\xa9es \
                gard\xc3\xa9es sur le t\xc3\xa9l\xc3\xa9phone." ))
          (card_opt
             (saved_card Drive_text.Granted ~online:true ~wifi_only:true photos))
    );
    ( "1 of 3 uploaded: the fraction",
      `Quick,
      fun () ->
        let photos =
          [
            photo ~state:Photo.Upload_state.Uploaded 1;
            photo ~state:Photo.Upload_state.Pending 2;
            photo ~state:Photo.Upload_state.Pending 3;
          ]
        in
        Alcotest.check card_option_t "saved_card"
          (Some
             ( "3 photos \xe2\x86\x92 Google Drive, dossier Herbier",
               "1 sur 3 envoy\xc3\xa9es." ))
          (card_opt
             (saved_card Drive_text.Granted ~online:true ~wifi_only:false photos))
    );
    ( "nothing uploaded, no blocker, no wifi_only: the default in-progress text",
      `Quick,
      fun () ->
        let photos = [photo ~state:Photo.Upload_state.Pending 1] in
        Alcotest.check card_option_t "saved_card"
          (Some
             ( "1 photo \xe2\x86\x92 Google Drive, dossier Herbier",
               "Envoi en cours. Copies compress\xc3\xa9es gard\xc3\xa9es sur \
                le t\xc3\xa9l\xc3\xa9phone." ))
          (card_opt
             (saved_card Drive_text.Granted ~online:true ~wifi_only:false photos))
    );
    ( "a picked folder names itself in the title, not \"Herbier\"",
      `Quick,
      fun () ->
        let photos =
          [
            photo ~state:Photo.Upload_state.Uploaded 1;
            photo ~state:Photo.Upload_state.Uploaded 2;
          ]
        in
        Alcotest.check card_option_t "saved_card"
          (Some
             ( "2 photos \xe2\x86\x92 Google Drive, dossier Mes plantes",
               "Envoy\xc3\xa9es dans Google Drive. Copies compress\xc3\xa9es \
                gard\xc3\xa9es sur le t\xc3\xa9l\xc3\xa9phone." ))
          (card_opt
             (saved_card ~folder:(Drive_text.Picked "Mes plantes")
                Drive_text.Granted ~online:true ~wifi_only:false photos)) );
    ( "App_only photos are ignored in the count",
      `Quick,
      fun () ->
        let photos =
          [
            photo ~state:Photo.Upload_state.Uploaded 1;
            photo ~state:Photo.Upload_state.Uploaded 2;
            photo ~target:Photo.Original_target.App_only
              ~state:Photo.Upload_state.Uploaded 3;
          ]
        in
        Alcotest.check card_option_t "saved_card"
          (Some
             ( "2 photos \xe2\x86\x92 Google Drive, dossier Herbier",
               "Envoy\xc3\xa9es dans Google Drive. Copies compress\xc3\xa9es \
                gard\xc3\xa9es sur le t\xc3\xa9l\xc3\xa9phone." ))
          (card_opt
             (saved_card Drive_text.Granted ~online:true ~wifi_only:false photos))
    );
  ]

(* ---------- has_drive_photo ---------- *)

let has_drive_photo_tests =
  let case name photos expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "has_drive_photo" expected
          (Drive_text.has_drive_photo photos);
        Alcotest.(check bool)
          "saved_card is Some exactly then" expected
          (Option.is_some
             (saved_card Drive_text.Granted ~online:true ~wifi_only:false photos))
    )
  in
  [
    case "no photo: false" [] false;
    case "only App_only: false"
      [photo ~target:Photo.Original_target.App_only 1]
      false;
    case "one Drive photo among App_only ones: true"
      [
        photo ~target:Photo.Original_target.App_only 1;
        photo ~state:Photo.Upload_state.Failed 2;
      ]
      true;
  ]

(* ---------- viewer_badge ---------- *)

let viewer_badge_tests =
  let case name p expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check string)
          "viewer_badge" expected
          (Drive_text.viewer_badge p) )
  in
  Photo.
    [
      case "Drive, Uploaded: Google Drive"
        (photo ~target:Original_target.Drive ~state:Upload_state.Uploaded 1)
        "Google Drive";
      case "Drive, Pending: waiting"
        (photo ~target:Original_target.Drive ~state:Upload_state.Pending 2)
        "\xe2\x86\x91 en attente";
      case "Drive, Failed: waiting"
        (photo ~target:Original_target.Drive ~state:Upload_state.Failed 3)
        "\xe2\x86\x91 en attente";
      case "Drive, Original_missing: local (5e's own line says introuvable)"
        (photo ~target:Original_target.Drive
           ~state:Upload_state.Original_missing 4)
        "local";
      case "App_only: local"
        (photo ~target:Original_target.App_only ~state:Upload_state.Uploaded 5)
        "local";
    ]

(* ---------- viewer_drive ---------- *)

let viewer_drive_tests =
  let case name p expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check viewer_drive_t "viewer_drive" expected
          (Drive_text.viewer_drive p) )
  in
  Photo.
    [
      case "Drive, Uploaded, a padded file id: Open, trimmed"
        (photo ~target:Original_target.Drive ~state:Upload_state.Uploaded
           ~file_id:(Some " f ") 10)
        (Drive_text.Open "f");
      case "Drive, Uploaded, no file id: Hidden"
        (photo ~target:Original_target.Drive ~state:Upload_state.Uploaded
           ~file_id:None 11)
        Drive_text.Hidden;
      case "Drive, Uploaded, a blank file id: Hidden"
        (photo ~target:Original_target.Drive ~state:Upload_state.Uploaded
           ~file_id:(Some "") 12)
        Drive_text.Hidden;
      case "Drive, Original_missing: Missing"
        (photo ~target:Original_target.Drive
           ~state:Upload_state.Original_missing 13)
        Drive_text.Missing;
      case "Drive, Pending: Hidden"
        (photo ~target:Original_target.Drive ~state:Upload_state.Pending 14)
        Drive_text.Hidden;
      case "App_only: Hidden"
        (photo ~target:Original_target.App_only ~state:Upload_state.Uploaded 15)
        Drive_text.Hidden;
    ]

(* ---------- drive_option (4m's Drive radio) ---------- *)

let chosen_of (o : Drive_text.drive_option) = o.chosen
let choose_of (o : Drive_text.drive_option) = o.choose

let choose_t =
  Alcotest.testable
    (fun ppf (c : Drive_text.choose) ->
      match c with
      | Enabled -> Format.pp_print_string ppf "Enabled"
      | Disabled reason -> Format.fprintf ppf "Disabled %S" reason)
    (fun a b ->
      match (a, b) with
      | Drive_text.Enabled, Drive_text.Enabled -> true
      | Disabled a, Disabled b -> String.equal a b
      | (Enabled | Disabled _), _ -> false)

let picker_unconfigured_option_reason =
  "Choix du dossier indisponible dans cette version."

(* title = "Google Drive" always, and never mentions the old wording ("…
   dossier « Herbier »"), over a representative spread of drive/picker/storage
   /folder combinations. *)
let drive_option_title_tests =
  let module D = Drive_account in
  let module O = Photo.Original_target in
  let case name ~drive ~picker ~storage folder =
    ( name,
      `Quick,
      fun () ->
        let o = Drive_text.drive_option ~drive ~picker ~storage folder in
        Alcotest.(check string) "title" "Google Drive" o.title;
        Alcotest.(check string)
          "detail, fixed"
          "Un sous-dossier par esp\xc3\xa8ce. Aper\xc3\xa7us gard\xc3\xa9s sur \
           le t\xc3\xa9l\xc3\xa9phone."
          o.detail;
        Alcotest.(check bool)
          "no \xc2\xab dossier \xc2\xbb in the title" false
          (Text.contains ~sub:"dossier" o.title);
        Alcotest.(check bool)
          "no \xc2\xab Herbier \xc2\xbb in the title" false
          (Text.contains ~sub:"Herbier" o.title) )
  in
  Drive_text.
    [
      case "Unconfigured, Default, App_only, Picker_ready" ~drive:D.Unconfigured
        ~picker:Picker_ready ~storage:O.App_only Default;
      case "Unchosen, Default, App_only, Picker_ready" ~drive:D.Unchosen
        ~picker:Picker_ready ~storage:O.App_only Default;
      case "Chosen, Picked, Drive, Picker_ready" ~drive:chosen_a
        ~picker:Picker_ready ~storage:O.Drive (Picked "Plantes");
      case "Chosen, Default, Drive, Picker_unconfigured" ~drive:chosen_a
        ~picker:Picker_unconfigured ~storage:O.Drive Default;
    ]

(* chosen: the folder (and account) once the storage is actually Drive and an
   account is known; None otherwise (App_only, or the legacy Drive/Unchosen
   state the « Dossier Drive » row prompts for). *)
let drive_option_chosen_tests =
  let module D = Drive_account in
  let module O = Photo.Original_target in
  let case ?(picker = Drive_text.Picker_ready) name ~drive ~storage folder
      expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "chosen" expected
          (chosen_of (Drive_text.drive_option ~drive ~picker ~storage folder))
    )
  in
  [
    case "Drive, Chosen, Picked: the folder name \xc2\xb7 the email"
      ~drive:chosen_a ~storage:O.Drive (Picked "Plantes")
      (Some "Plantes \xc2\xb7 a@x.fr");
    case
      "Drive, Chosen, Default: \xc2\xab Herbier \xc2\xbb, created by the app, \
       then the email"
      ~drive:chosen_a ~storage:O.Drive Default
      (Some (herbier_detail ^ " \xc2\xb7 a@x.fr"));
    case
      "Drive, Chosen, Picked \" \" (blank): the blank-name fallback, then the \
       email"
      ~drive:chosen_a ~storage:O.Drive (Picked " ")
      (Some "(sans nom) \xc2\xb7 a@x.fr");
    case "App_only, Chosen: None - an old choice is not where photos go"
      ~drive:chosen_a ~storage:O.App_only Default None;
    case
      "Drive, Unchosen: None - the legacy state, \xc2\xab Dossier Drive \
       \xc2\xbb prompts instead"
      ~drive:D.Unchosen ~storage:O.Drive Default None;
    case "Drive, Unconfigured: None" ~drive:D.Unconfigured ~storage:O.Drive
      Default None;
    case "App_only, Unchosen: None" ~drive:D.Unchosen ~storage:O.App_only
      Default None;
    case "Drive, Chosen, Picked, without the Picker: the same line"
      ~picker:Drive_text.Picker_unconfigured ~drive:chosen_a ~storage:O.Drive
      (Picked "Plantes") (Some "Plantes \xc2\xb7 a@x.fr");
  ]

(* A tap starts a choice only from App_only, enabled, with none running. *)
let drive_option_starts_tests =
  let module O = Photo.Original_target in
  let option choose : Drive_text.drive_option =
    {title = "Google Drive"; detail = ""; chosen = None; choose}
  in
  let case ~storage ~running choose expected =
    ( Printf.sprintf "%s, %s, %s: %b"
        (match storage with O.Drive -> "Drive" | O.App_only -> "App_only")
        (match choose with
        | Drive_text.Enabled -> "Enabled"
        | Disabled (_ : string) -> "Disabled")
        (match running with true -> "running" | false -> "idle")
        expected,
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "starts" expected
          (Drive_text.drive_option_starts ~storage ~running (option choose)) )
  in
  List.concat_map
    (fun storage ->
      List.concat_map
        (fun choose ->
          List.map
            (fun running ->
              let expected =
                match (storage, choose, running) with
                | O.App_only, Drive_text.Enabled, false -> true
                | _ -> false
              in
              case ~storage ~running choose expected)
            [false; true])
        Drive_text.[Enabled; Disabled "no"])
    [O.App_only; O.Drive]

(* choose: Unconfigured (no Drive at all) before Picker_unconfigured (the
   Picker's own build reason), else Enabled, whatever the storage. *)
let drive_option_choose_tests =
  let module D = Drive_account in
  let module O = Photo.Original_target in
  let case name ~drive ~picker ~storage folder expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check choose_t "choose" expected
          (choose_of (Drive_text.drive_option ~drive ~picker ~storage folder))
    )
  in
  Drive_text.
    [
      case "Unconfigured, App_only, Picker_ready: disabled, the build reason"
        ~drive:D.Unconfigured ~picker:Picker_ready ~storage:O.App_only Default
        (Disabled unconfigured_reason);
      case "Unconfigured, Picker_unconfigured too: the build reason wins"
        ~drive:D.Unconfigured ~picker:Picker_unconfigured ~storage:O.Drive
        Default (Disabled unconfigured_reason);
      case
        "Unchosen, App_only, Picker_unconfigured: disabled, the Picker reason"
        ~drive:D.Unchosen ~picker:Picker_unconfigured ~storage:O.App_only
        Default (Disabled picker_unconfigured_option_reason);
      case
        "Unchosen, Drive, Picker_unconfigured: disabled, the Picker reason too"
        ~drive:D.Unchosen ~picker:Picker_unconfigured ~storage:O.Drive Default
        (Disabled picker_unconfigured_option_reason);
      case
        "Chosen, Drive, Picker_unconfigured: disabled, the Picker reason (a \
         legacy install sees the radio checked but disabled)"
        ~drive:chosen_a ~picker:Picker_unconfigured ~storage:O.Drive
        (Picked "Plantes") (Disabled picker_unconfigured_option_reason);
      case "Unchosen, App_only, Picker_ready: enabled" ~drive:D.Unchosen
        ~picker:Picker_ready ~storage:O.App_only Default Enabled;
      case "Chosen, Drive, Picker_ready: enabled" ~drive:chosen_a
        ~picker:Picker_ready ~storage:O.Drive Default Enabled;
    ]

let drive_text =
  List.concat
    [
      access_tests;
      queue_of_tests;
      queue_title_tests;
      blocker_tests;
      blocker_extra_tests;
      queue_status_tests;
      last_sent_tests;
      send_enabled_tests;
      account_meta_tests;
      drive_prompt_tests;
      stop_dialog_tests;
      folder_tests;
      folder_name_tests;
      folder_button_tests;
      picker_config_tests;
      pick_error_text_tests;
      saved_card_tests;
      has_drive_photo_tests;
      viewer_badge_tests;
      viewer_drive_tests;
      drive_option_title_tests;
      drive_option_chosen_tests;
      drive_option_choose_tests;
      drive_option_starts_tests;
    ]
