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

let clear_token ~token =
  Cap_call.call plugin "clearToken"
    [|Jv.obj [|("token", Jv.of_string token)|]|]
    ~ok:Cap_call.unit_ok
