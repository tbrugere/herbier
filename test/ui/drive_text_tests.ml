(* Herbier_ui_model.Drive_text (app/ui_model/drive_text.mli): the
   Drive-related texts of 4e, 4m and 5e. *)

module Drive_text = Herbier_ui_model.Drive_text
module Photo = Herbier_domain.Photo
module Ids = Herbier_domain.Ids
module Value = Herbier_test_support.Value
module Lifecycle = Herbier_sync_core.Auth.Lifecycle

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
  | Signed_out -> "Signed_out"
  | Consent_needed -> "Consent_needed"
  | Consent_refused -> "Consent_refused"
  | Offline -> "Offline"
  | Misconfigured -> "Misconfigured"
  | No_account -> "No_account"
  | Failed -> "Failed"

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

let pp_folder_row ppf (r : Drive_text.folder_row) =
  Format.fprintf ppf "{detail = %S; choose = %s; default = %b}" r.detail
    (match r.choose with
    | Enabled -> "Enabled"
    | Disabled s -> Printf.sprintf "Disabled %S" s)
    r.default

let folder_row_t = Alcotest.testable pp_folder_row Drive_text.equal_folder_row

let pick_error_to_string = function
  | Drive_text.Not_a_folder -> "Not_a_folder"
  | Drive_text.Trashed -> "Trashed"
  | Drive_text.No_access -> "No_access"
  | Drive_text.Offline -> "Offline"
  | Drive_text.Token d -> "Token " ^ denial_to_string d
  | Drive_text.Picker_unavailable -> "Picker_unavailable"
  | Drive_text.Not_saved -> "Not_saved"
  | Drive_text.Drive_failed -> "Drive_failed"

let pp_pick_error ppf e = Format.pp_print_string ppf (pick_error_to_string e)
let pick_error_t = Alcotest.testable pp_pick_error Drive_text.equal_pick_error

(* ---------- access ---------- *)

let access_tests =
  let case name account last expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check access_t "access" expected
          (Drive_text.access ~account ~last) )
  in
  let signed_in = Lifecycle.Signed_in {email = Some "a@b.c"} in
  Drive_text.
    [
      case "Unconfigured, last Unknown: Denied Unconfigured"
        Lifecycle.Unconfigured Unknown (Denied Unconfigured);
      case "Unconfigured, last Granted: Denied Unconfigured"
        Lifecycle.Unconfigured Granted (Denied Unconfigured);
      case "Unconfigured, last Denied Consent_needed: Denied Unconfigured"
        Lifecycle.Unconfigured (Denied Consent_needed) (Denied Unconfigured);
      case "Unconfigured, last Denied Signed_out: Denied Unconfigured"
        Lifecycle.Unconfigured (Denied Signed_out) (Denied Unconfigured);
      case "Signed_out, last Unknown: Denied Signed_out" Lifecycle.Signed_out
        Unknown (Denied Signed_out);
      case "Signed_out, last Granted: Denied Signed_out" Lifecycle.Signed_out
        Granted (Denied Signed_out);
      case "Signed_out, last Denied Consent_needed: Denied Signed_out"
        Lifecycle.Signed_out (Denied Consent_needed) (Denied Signed_out);
      case "Signed_out, last Denied Signed_out: Denied Signed_out"
        Lifecycle.Signed_out (Denied Signed_out) (Denied Signed_out);
      case "Restoring, last Unknown: Unknown" Lifecycle.Restoring Unknown
        Unknown;
      case "Restoring, last Granted: Unknown" Lifecycle.Restoring Granted
        Unknown;
      case "Restoring, last Denied Consent_needed: Unknown" Lifecycle.Restoring
        (Denied Consent_needed) Unknown;
      case "Restoring, last Denied Signed_out: Unknown" Lifecycle.Restoring
        (Denied Signed_out) Unknown;
      case "Signed_in, last Unknown: Unknown" signed_in Unknown Unknown;
      case "Signed_in, last Granted: Granted" signed_in Granted Granted;
      case "Signed_in without an address, last Granted: Granted"
        (Lifecycle.Signed_in {email = None})
        Granted Granted;
      case "Signed_in, last Denied Consent_needed: Denied Consent_needed"
        signed_in (Denied Consent_needed) (Denied Consent_needed);
      case "Signed_in, last Denied Signed_out (a stale denial): Unknown"
        signed_in (Denied Signed_out) Unknown;
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
      case "Denied Signed_out" (Denied Signed_out) ~online:true
        (Some "Connectez-vous pour envoyer les photos.");
      case "Denied Consent_needed" (Denied Consent_needed) ~online:true
        (Some "Google Drive n\xe2\x80\x99est pas autoris\xc3\xa9.");
      case "Denied Consent_refused" (Denied Consent_refused) ~online:true
        (Some "Google Drive n\xe2\x80\x99est pas autoris\xc3\xa9.");
      case "Denied No_account" (Denied No_account) ~online:true
        (Some "Aucun compte Google sur le t\xc3\xa9l\xc3\xa9phone.");
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
      case "Denied Signed_out, offline: the sign-in text" (Denied Signed_out)
        ~online:false (Some "Connectez-vous pour envoyer les photos.");
      case "Denied Consent_needed, offline: not authorized"
        (Denied Consent_needed) ~online:false
        (Some "Google Drive n\xe2\x80\x99est pas autoris\xc3\xa9.");
      case "Denied Consent_refused, offline: not authorized"
        (Denied Consent_refused) ~online:false
        (Some "Google Drive n\xe2\x80\x99est pas autoris\xc3\xa9.");
      case "Denied No_account, offline: no account" (Denied No_account)
        ~online:false
        (Some "Aucun compte Google sur le t\xc3\xa9l\xc3\xa9phone.");
      case "Denied Misconfigured, offline: misconfigured" (Denied Misconfigured)
        ~online:false
        (Some
           "Google refuse l\xe2\x80\x99acc\xc3\xa8s \xc3\xa0 Drive \
            (configuration de l\xe2\x80\x99app).");
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
            "queue_status" (Some "Connectez-vous pour envoyer les photos.")
            (Drive_text.queue_status (Denied Signed_out) ~online:true
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
            "queue_status" (Some "Connectez-vous pour envoyer les photos.")
            (Drive_text.queue_status (Denied Signed_out) ~online:true
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

let account_meta_tests =
  [
    ( "email, Drive, Granted: the email then \" \xc2\xb7 Drive\"",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "account_meta" "a@b.c \xc2\xb7 Drive"
          (Drive_text.account_meta ~email:(Some "a@b.c")
             ~storage:Photo.Original_target.Drive Drive_text.Granted) );
    ( "email, App_only, Granted: just the email",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "account_meta" "a@b.c"
          (Drive_text.account_meta ~email:(Some "a@b.c")
             ~storage:Photo.Original_target.App_only Drive_text.Granted) );
    ( "email, Drive, Denied: just the email (no suffix without Granted)",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "account_meta" "a@b.c"
          (Drive_text.account_meta ~email:(Some "a@b.c")
             ~storage:Photo.Original_target.Drive
             (Drive_text.Denied Drive_text.Consent_needed)) );
    ( "no email: the fallback address text",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "account_meta" "Adresse inconnue"
          (Drive_text.account_meta ~email:None
             ~storage:Photo.Original_target.App_only Drive_text.Granted) );
  ]

(* ---------- drive_prompt ---------- *)

let drive_prompt_tests =
  let consent_prompt =
    Some
      ( "Google Drive n\xe2\x80\x99est pas autoris\xc3\xa9 : les photos \
         attendent sur le t\xc3\xa9l\xc3\xa9phone.",
        Some "Autoriser" )
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
      (Some ("Aucun compte Google sur le t\xc3\xa9l\xc3\xa9phone.", None));
    case "Drive, Denied Misconfigured: its blocker text, no action" O.Drive
      (D.Denied D.Misconfigured)
      (Some
         ( "Google refuse l\xe2\x80\x99acc\xc3\xa8s \xc3\xa0 Drive \
            (configuration de l\xe2\x80\x99app).",
           None ));
    case "Drive, Denied Signed_out: the sign-in text, no action" O.Drive
      (D.Denied D.Signed_out)
      (Some ("Connectez-vous pour envoyer les photos vers Drive.", None));
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
    case ~pending:1 "App_only with a photo waiting, Denied Signed_out: sign in"
      O.App_only (D.Denied D.Signed_out)
      (Some ("Connectez-vous pour envoyer les photos vers Drive.", None));
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

(* ---------- folder_row ---------- *)

let unconfigured_reason = "Choix du dossier indisponible dans cette version."
let herbier_detail = "Herbier \xc2\xb7 cr\xc3\xa9\xc3\xa9 par l\xe2\x80\x99app"

let folder_row_tests =
  let case name config access folder expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check folder_row_t "folder_row" expected
          (Drive_text.folder_row config access folder) )
  in
  Drive_text.
    [
      case "Picker_unconfigured, Granted, Default: disabled, not resettable"
        Picker_unconfigured Granted Default
        {
          detail = herbier_detail;
          default = false;
          choose = Disabled unconfigured_reason;
        };
      case
        "Picker_unconfigured, Granted, Picked: disabled, but resettable \
         (default is true for a Picked folder even when unconfigured)"
        Picker_unconfigured Granted (Picked "Mes plantes")
        {
          detail = "Mes plantes";
          default = true;
          choose = Disabled unconfigured_reason;
        };
      case
        "Picker_unconfigured, Denied Signed_out: the build reason wins over \
         the sign-in line (first that applies)"
        Picker_unconfigured (Denied Signed_out) Default
        {
          detail = herbier_detail;
          default = false;
          choose = Disabled unconfigured_reason;
        };
      case "Picker_ready, Denied Unconfigured: disabled, the same reason"
        Picker_ready (Denied Unconfigured) Default
        {
          detail = herbier_detail;
          default = false;
          choose = Disabled unconfigured_reason;
        };
      case "Picker_ready, Denied Signed_out: disabled, the sign-in line"
        Picker_ready (Denied Signed_out) Default
        {
          detail = herbier_detail;
          default = false;
          choose = Disabled "Connectez-vous pour choisir un dossier.";
        };
      case "Picker_ready, Denied No_account: disabled, its blocker text"
        Picker_ready (Denied No_account) Default
        {
          detail = herbier_detail;
          default = false;
          choose =
            Disabled "Aucun compte Google sur le t\xc3\xa9l\xc3\xa9phone.";
        };
      case "Picker_ready, Denied Misconfigured: disabled, its blocker text"
        Picker_ready (Denied Misconfigured) Default
        {
          detail = herbier_detail;
          default = false;
          choose =
            Disabled
              "Google refuse l\xe2\x80\x99acc\xc3\xa8s \xc3\xa0 Drive \
               (configuration de l\xe2\x80\x99app).";
        };
      case "Picker_ready, Unknown, Default: enabled, no reason" Picker_ready
        Unknown Default
        {detail = herbier_detail; choose = Enabled; default = false};
      case "Picker_ready, Granted, Picked: enabled, resettable, named"
        Picker_ready Granted (Picked "Mes plantes")
        {detail = "Mes plantes"; choose = Enabled; default = true};
      case
        "Picker_ready, Denied Consent_needed: enabled (the tap asks \
         interactively and reports)"
        Picker_ready (Denied Consent_needed) Default
        {detail = herbier_detail; choose = Enabled; default = false};
      case "Picker_ready, Denied Consent_refused: enabled" Picker_ready
        (Denied Consent_refused) Default
        {detail = herbier_detail; choose = Enabled; default = false};
      case "Picker_ready, Denied Offline: enabled" Picker_ready (Denied Offline)
        Default
        {detail = herbier_detail; choose = Enabled; default = false};
      case "Picker_ready, Denied Failed: enabled" Picker_ready (Denied Failed)
        Default
        {detail = herbier_detail; choose = Enabled; default = false};
      case
        "Picker_ready, Granted, Picked \"\": enabled, resettable, the \
         blank-name fallback in detail"
        Picker_ready Granted (Picked "")
        {detail = "(sans nom)"; choose = Enabled; default = true};
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
      case "Token Signed_out" (Token Signed_out)
        "Connectez-vous pour envoyer les photos.";
      case "Token Consent_needed" (Token Consent_needed)
        "Google Drive n\xe2\x80\x99est pas autoris\xc3\xa9.";
      case "Token Consent_refused" (Token Consent_refused)
        "Google Drive n\xe2\x80\x99est pas autoris\xc3\xa9.";
      case "Token No_account" (Token No_account)
        "Aucun compte Google sur le t\xc3\xa9l\xc3\xa9phone.";
      case "Token Misconfigured" (Token Misconfigured)
        "Google refuse l\xe2\x80\x99acc\xc3\xa8s \xc3\xa0 Drive (configuration \
         de l\xe2\x80\x99app).";
      case "Token Offline" (Token Offline)
        "Envoi d\xc3\xa8s le retour du r\xc3\xa9seau.";
      case "Token Failed" (Token Failed)
        "Envoi d\xc3\xa8s le retour du r\xc3\xa9seau.";
      case "Picker_unavailable" Picker_unavailable
        "Google Picker n\xe2\x80\x99a pas pu s\xe2\x80\x99ouvrir.";
      case "Not_saved" Not_saved
        "Le r\xc3\xa9glage n\xe2\x80\x99a pas pu \xc3\xaatre enregistr\xc3\xa9.";
      case "Drive_failed" Drive_failed
        "Drive n\xe2\x80\x99a pas r\xc3\xa9pondu : r\xc3\xa9essayez.";
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
                (Drive_text.Denied Drive_text.Signed_out) ~online:true
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
               "Connectez-vous pour envoyer les photos." ))
          (card_opt
             (saved_card (Drive_text.Denied Drive_text.Signed_out) ~online:true
                ~wifi_only:false photos)) );
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
    ( "Denied Signed_out, nothing failed: the sign-in blocker text",
      `Quick,
      fun () ->
        let photos = [photo ~state:Photo.Upload_state.Pending 1] in
        Alcotest.check card_option_t "saved_card"
          (Some
             ( "1 photo \xe2\x86\x92 Google Drive, dossier Herbier",
               "Connectez-vous pour envoyer les photos." ))
          (card_opt
             (saved_card (Drive_text.Denied Drive_text.Signed_out) ~online:true
                ~wifi_only:false photos)) );
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

let drive_text =
  List.concat
    [
      access_tests;
      queue_of_tests;
      queue_title_tests;
      blocker_tests;
      queue_status_tests;
      last_sent_tests;
      send_enabled_tests;
      account_meta_tests;
      drive_prompt_tests;
      stop_dialog_tests;
      folder_tests;
      folder_name_tests;
      folder_row_tests;
      picker_config_tests;
      pick_error_text_tests;
      saved_card_tests;
      has_drive_photo_tests;
      viewer_badge_tests;
      viewer_drive_tests;
    ]
