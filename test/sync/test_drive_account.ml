(* app/sync_core/auth/drive_account.ml (Auth.Drive_account): the Drive
   account, independent of the Supabase session (architecture §5). That
   independence is structural: request takes no session, so the case below
   only pins that a Chosen account is asked as it is. *)

module Drive_account = Herbier_sync_core.Auth.Drive_account

let t_t = Alcotest.testable Drive_account.pp Drive_account.equal

let unavailable_t =
  Alcotest.testable Drive_account.pp_unavailable Drive_account.equal_unavailable

let choose_error_t =
  Alcotest.testable Drive_account.pp_choose_error
    Drive_account.equal_choose_error

(* ---------- of_stored ---------- *)

let of_stored_cases =
  let case name ~configured stored expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check t_t "of_stored" expected
          (Drive_account.of_stored ~configured stored) )
  in
  Drive_account.
    [
      case "configured = false, a value stored: Unconfigured whatever is stored"
        ~configured:false (Some "a@b.fr") Unconfigured;
      case "configured = false, nothing stored: Unconfigured" ~configured:false
        None Unconfigured;
      case "configured = true, nothing stored: Unchosen" ~configured:true None
        Unchosen;
      case "configured = true, a blank value stored: Unchosen" ~configured:true
        (Some "  ") Unchosen;
      case "configured = true, a padded email: Chosen, trimmed" ~configured:true
        (Some " a@b.fr ")
        (Chosen {email = "a@b.fr"});
    ]

let email_cases =
  let case name t expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "email" expected (Drive_account.email t) )
  in
  Drive_account.
    [
      case "Chosen: Some the email" (Chosen {email = "a@b.fr"}) (Some "a@b.fr");
      case "Unchosen: None" Unchosen None;
      case "Unconfigured: None" Unconfigured None;
    ]

(* ---------- request ---------- *)

let request_cases =
  let case name t expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check
          (Alcotest.result Alcotest.string unavailable_t)
          "request" expected (Drive_account.request t) )
  in
  Drive_account.
    [
      case "a chosen account is asked: Ok email"
        (Chosen {email = "drive@x.fr"})
        (Ok "drive@x.fr");
      case "Unchosen: Error No_account" Unchosen (Error No_account);
      case "Unconfigured: Error No_client" Unconfigured (Error No_client);
    ]

(* ---------- choose_error_of_code ---------- *)

let choose_error_of_code_cases =
  let case name code expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check choose_error_t "choose_error_of_code" expected
          (Drive_account.choose_error_of_code code) )
  in
  Drive_account.
    [
      case "USER_CANCELLED is Cancelled" (Some "USER_CANCELLED") Cancelled;
      case "NO_CREDENTIAL is No_google_account" (Some "NO_CREDENTIAL")
        No_google_account;
      case "CHOOSE_FAILED is Choose_failed" (Some "CHOOSE_FAILED") Choose_failed;
      case "BUSY is Choose_failed" (Some "BUSY") Choose_failed;
      case "INVALID_ARGUMENT is Choose_failed" (Some "INVALID_ARGUMENT")
        Choose_failed;
      case "NO_ACTIVITY is Choose_failed" (Some "NO_ACTIVITY") Choose_failed;
      case "lowercase user_cancelled does not match (exact, case-sensitive)"
        (Some "user_cancelled") Choose_failed;
      case "no code at all is Choose_failed" None Choose_failed;
    ]

let tests =
  of_stored_cases @ email_cases @ request_cases @ choose_error_of_code_cases
