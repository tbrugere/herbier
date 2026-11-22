type listener = Jv.t

let plugin = "volumeKey"
let enable () = Cap_call.call plugin "enable" [||] ~ok:Cap_call.unit_ok
let disable () = Cap_call.call plugin "disable" [||] ~ok:Cap_call.unit_ok

let on_volume_down f =
  let callback = Jv.callback ~arity:1 (fun _ -> f ()) in
  Cap_call.call plugin "addListener"
    [|Jv.of_string "volumeDown"; callback|]
    ~ok:(fun handle -> Ok handle)

let remove handle = Cap_call.on handle "remove" [||] ~ok:Cap_call.unit_ok
