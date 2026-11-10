type listener = Jv.t
type state = Active | Inactive

let plugin = "app"

(* Only the error is logged, never the event: a URL may carry user data. *)
let dropped event e =
  Brr.Console.(
    warn [str ("Cap_app: dropped " ^ event); str (Cap_error.to_string e)])

let add_listener event read f =
  let callback =
    Jv.callback ~arity:1 (fun ev ->
        match read ev with Ok v -> f v | Error e -> dropped event e)
  in
  Cap_call.call plugin "addListener"
    [|Jv.of_string event; callback|]
    ~ok:(fun handle -> Ok handle)

let state_of_event ev =
  Result.map
    (function true -> Active | false -> Inactive)
    (Cap_call.bool_field ev "isActive")

let on_state_change f = add_listener "appStateChange" state_of_event f

let on_url_open f =
  add_listener "appUrlOpen" (fun ev -> Cap_call.string_field ev "url") f

let on_back_button f =
  add_listener "backButton"
    (fun ev -> Cap_call.bool_field ev "canGoBack")
    (fun can_go_back -> f ~can_go_back)

let exit_app () = Cap_call.call plugin "exitApp" [||] ~ok:Cap_call.unit_ok
let remove handle = Cap_call.on handle "remove" [||] ~ok:Cap_call.unit_ok
