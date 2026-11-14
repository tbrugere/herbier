module Cap_error = Herbier_bindings.Cap_error
module Cap_google_authorization = Herbier_bindings.Cap_google_authorization
module Drive_consent = Herbier_sync_core.Auth.Drive_consent

(* Cap_error.t is plain data: structural equality is its equality. *)
type error =
  | Drive_unconfigured
  | Drive_signed_out
  | Consent_needed
  | Consent_refused
  | Drive_offline
  | Drive_misconfigured
  | No_google_account
  | Drive_google of (Cap_error.t[@equal ( = )])
[@@deriving eq]

let error_to_string = function
  | Drive_unconfigured -> "sign-in not configured in this build"
  | Drive_signed_out -> "signed out"
  | Consent_needed -> "Drive consent needed"
  | Consent_refused -> "Drive consent refused"
  | Drive_offline -> "Google unreachable"
  | Drive_misconfigured -> "Google client misconfigured"
  | No_google_account -> "no Google account on the device"
  | Drive_google e -> "google: " ^ Cap_error.to_string e

type account = Unconfigured | Signed_out | Signed_in of {email : string}

(* style: a mutable field because the flight starts and ends in future
   callbacks; nothing outside this module sees it. *)
type t = {mutable interactive : (string, error) result Fut.t option}

let create () = {interactive = None}

let of_cap_error = function
  | Cap_error.Rejected {code; _} as e -> (
      match
        (Drive_consent.refusal_of_code code, Drive_consent.failure_of_code code)
      with
      | Some Drive_consent.Consent_needed, _ -> Consent_needed
      | Some Drive_consent.Consent_refused, _ -> Consent_refused
      | None, Some Drive_consent.Offline -> Drive_offline
      | None, Some Drive_consent.Misconfigured -> Drive_misconfigured
      | None, Some Drive_consent.No_google_account -> No_google_account
      | None, None -> Drive_google e)
  | (Cap_error.Unavailable _ | Unexpected _ | Invalid_path _) as e ->
      Drive_google e

let logged result =
  (match result with
  | Ok (_ : string) -> Console_line.log Auth "drive token ok"
  | Error e -> Console_line.warn Auth ("drive token " ^ error_to_string e));
  result

let ask ~email ~interactive =
  Fut.map
    (fun r -> logged (Result.map_error of_cap_error r))
    (Cap_google_authorization.authorize ~scopes:[Drive_consent.scope]
       ~account:(Some email) ~interactive)

let token t account ~interactive =
  match (account, interactive) with
  | Unconfigured, _ -> Fut.return (logged (Error Drive_unconfigured))
  | Signed_out, _ -> Fut.return (logged (Error Drive_signed_out))
  | Signed_in {email}, false -> ask ~email ~interactive:false
  | Signed_in {email}, true -> (
      match t.interactive with
      | Some flight -> flight
      | None ->
          let flight = ask ~email ~interactive:true in
          t.interactive <- Some flight;
          Fut.await flight (fun _ -> t.interactive <- None);
          flight)

let drop token =
  Fut.map
    (function
      | Ok () -> Console_line.log Auth "drive token dropped"
      | Error e ->
          Console_line.warn Auth
            ("drive token not dropped: " ^ Cap_error.to_string e))
    (Cap_google_authorization.clear_token ~token)
