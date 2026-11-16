module Cap_error = Herbier_bindings.Cap_error
module Cap_google_authorization = Herbier_bindings.Cap_google_authorization
module Drive_consent = Herbier_sync_core.Auth.Drive_consent
module Drive_account = Herbier_sync_core.Auth.Drive_account

(* Cap_error.t is plain data: structural equality is its equality. *)
type error =
  | Drive_unconfigured
  | Drive_no_account
  | Consent_needed
  | Consent_refused
  | Drive_offline
  | Drive_misconfigured
  | No_google_account
  | Drive_google of (Cap_error.t[@equal ( = )])
[@@deriving eq]

let error_to_string = function
  | Drive_unconfigured -> "Drive not configured in this build"
  | Drive_no_account -> "no Drive account chosen"
  | Consent_needed -> "Drive consent needed"
  | Consent_refused -> "Drive consent refused"
  | Drive_offline -> "Google unreachable"
  | Drive_misconfigured -> "Google client misconfigured"
  | No_google_account -> "no Google account on the device"
  | Drive_google e -> "google: " ^ Cap_error.to_string e

(* style: a mutable field because the flights start and end in future
   callbacks; nothing outside this module sees it. At most one entry per
   email, two in practice (a request made just before an account change). *)
type t = {mutable interactive : (string * (string, error) result Fut.t) list}

let create () = {interactive = []}
let configured = not (String.equal Backend.google_web_client_id "")

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
  match (Drive_account.request account, interactive) with
  | Error No_client, _ -> Fut.return (logged (Error Drive_unconfigured))
  | Error No_account, _ -> Fut.return (logged (Error Drive_no_account))
  | Ok email, false -> ask ~email ~interactive:false
  | Ok email, true -> (
      match List.assoc_opt email t.interactive with
      | Some flight -> flight
      | None ->
          let flight = ask ~email ~interactive:true in
          t.interactive <- (email, flight) :: t.interactive;
          Fut.await flight (fun _ ->
              t.interactive <- List.remove_assoc email t.interactive);
          flight)

type choose_error = Drive_account.choose_error =
  | Cancelled
  | No_google_account
  | Choose_failed

let choose_error_to_string = function
  | Cancelled -> "cancelled"
  | No_google_account -> "no Google account on the device"
  | Choose_failed -> "chooser failed"

let choose () =
  match configured with
  | false ->
      Console_line.warn Auth "drive account chooser failed: no web client id";
      Fut.return (Error Drive_account.Choose_failed)
  | true ->
      Fut.map
        (function
          | Ok email ->
              Console_line.log Auth "drive account chosen";
              Ok email
          | Error e ->
              let error =
                match e with
                | Cap_error.Rejected {code; _} ->
                    Drive_account.choose_error_of_code code
                | Unavailable _ | Unexpected _ | Invalid_path _ -> Choose_failed
              in
              Console_line.warn Auth
                ("drive account "
                ^ choose_error_to_string error
                ^ ": "
                ^ Cap_error.to_string e);
              Error error)
        (Cap_google_authorization.choose_account
           ~web_client_id:Backend.google_web_client_id)

let drop token =
  Fut.map
    (function
      | Ok () -> Console_line.log Auth "drive token dropped"
      | Error e ->
          Console_line.warn Auth
            ("drive token not dropped: " ^ Cap_error.to_string e))
    (Cap_google_authorization.clear_token ~token)
