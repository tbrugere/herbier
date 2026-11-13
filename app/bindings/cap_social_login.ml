let plugin = "socialLogin"

let initialize_google ~web_client_id =
  Cap_call.call plugin "initialize"
    [|
      Jv.obj
        [|
          ( "google",
            Jv.obj
              [|
                ("webClientId", Jv.of_string web_client_id);
                ("mode", Jv.of_string "online");
              |] );
        |];
    |]
    ~ok:Cap_call.unit_ok

let response_type r =
  match Cap_call.string_field r "result.responseType" with
  | Ok "online" -> Ok ()
  | Ok _ | Error _ -> Error (Cap_error.Unexpected "result.responseType")

let id_token r =
  Result.bind (response_type r) (fun () ->
      Cap_call.string_field r "result.idToken")

(* "standard" is the button flow (GetSignInWithGoogleOption): it always shows
   the account chooser, which « Changer » relies on. *)
let login_google ~nonce =
  Cap_call.call plugin "login"
    [|
      Jv.obj
        [|
          ("provider", Jv.of_string "google");
          ( "options",
            Jv.obj
              [|
                ("nonce", Jv.of_string nonce); ("style", Jv.of_string "standard");
              |] );
        |];
    |]
    ~ok:id_token

let logout_google () =
  Cap_call.call plugin "logout"
    [|Jv.obj [|("provider", Jv.of_string "google")|]|]
    ~ok:Cap_call.unit_ok

let cancelled = function
  | Cap_error.Rejected {code = Some "USER_CANCELLED"; _} -> true
  | Cap_error.Rejected _ | Unavailable _ | Unexpected _ | Invalid_path _ ->
      false
