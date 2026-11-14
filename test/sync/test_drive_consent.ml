(* app/sync_core/auth/drive_consent.ml (Auth.Drive_consent): the drive.file
   scope string, and the GoogleAuthorizationPlugin rejection codes read as a
   refusal or a failure. Registered in test_sync's Alcotest.run under "Drive consent". *)

module Drive_consent = Herbier_sync_core.Auth.Drive_consent

let refusal_t =
  Alcotest.testable
    (fun ppf r ->
      Format.pp_print_string ppf
        (match r with
        | Drive_consent.Consent_needed -> "Consent_needed"
        | Drive_consent.Consent_refused -> "Consent_refused"))
    Drive_consent.equal_refusal

let option_refusal = Alcotest.option refusal_t

let scope_tests =
  [
    ( "scope is the drive.file auth URL",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "scope" "https://www.googleapis.com/auth/drive.file"
          Drive_consent.scope );
  ]

let refusal_of_code_tests =
  let case name code expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check option_refusal "refusal_of_code" expected
          (Drive_consent.refusal_of_code code) )
  in
  [
    case "NEEDS_CONSENT is Consent_needed" (Some "NEEDS_CONSENT")
      (Some Drive_consent.Consent_needed);
    case "USER_CANCELLED is Consent_refused" (Some "USER_CANCELLED")
      (Some Drive_consent.Consent_refused);
    case "SCOPE_NOT_GRANTED is Consent_refused" (Some "SCOPE_NOT_GRANTED")
      (Some Drive_consent.Consent_refused);
    case "lowercase needs_consent does not match (exact case)"
      (Some "needs_consent") None;
    case "AUTHORIZATION_FAILED is an ordinary failure"
      (Some "AUTHORIZATION_FAILED") None;
    case "an unrelated code" (Some "UNIMPLEMENTED") None;
    case "no code at all" None None;
  ]

let failure_t =
  Alcotest.testable
    (fun ppf f ->
      Format.pp_print_string ppf
        (match f with
        | Drive_consent.Offline -> "Offline"
        | Drive_consent.Misconfigured -> "Misconfigured"
        | Drive_consent.No_google_account -> "No_google_account"))
    Drive_consent.equal_failure

let failure_of_code_tests =
  let case name code expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check
          (Alcotest.option failure_t)
          "failure_of_code" expected
          (Drive_consent.failure_of_code code) )
  in
  [
    case "NETWORK_ERROR is Offline" (Some "NETWORK_ERROR")
      (Some Drive_consent.Offline);
    case "DEVELOPER_ERROR is Misconfigured" (Some "DEVELOPER_ERROR")
      (Some Drive_consent.Misconfigured);
    case "SIGN_IN_REQUIRED is No_google_account" (Some "SIGN_IN_REQUIRED")
      (Some Drive_consent.No_google_account);
    case "AUTHORIZATION_FAILED is no particular failure"
      (Some "AUTHORIZATION_FAILED") None;
    case "a refusal code is not a failure" (Some "NEEDS_CONSENT") None;
    case "no code at all" None None;
  ]

let tests = scope_tests @ refusal_of_code_tests @ failure_of_code_tests
