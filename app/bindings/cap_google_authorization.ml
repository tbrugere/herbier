let plugin = "googleAuthorization"

let authorize ~scopes ~account ~interactive =
  let account =
    match account with
    | Some email -> [|("account", Jv.of_string email)|]
    | None -> [||]
  in
  Cap_call.call plugin "authorize"
    [|
      Jv.obj
        (Array.append
           [|
             ("scopes", Jv.of_list Jv.of_string scopes);
             ("interactive", Jv.of_bool interactive);
           |]
           account);
    |]
    ~ok:(fun r -> Cap_call.string_field r "accessToken")

let non_empty_email r =
  match Cap_call.string_field r "email" with
  | Ok "" -> Error (Cap_error.Unexpected "email")
  | (Ok (_ : string) | Error (_ : Cap_error.t)) as email -> email

let choose_account ~web_client_id =
  Cap_call.call plugin "chooseAccount"
    [|Jv.obj [|("webClientId", Jv.of_string web_client_id)|]|]
    ~ok:non_empty_email

let clear_token ~token =
  Cap_call.call plugin "clearToken"
    [|Jv.obj [|("token", Jv.of_string token)|]|]
    ~ok:Cap_call.unit_ok
