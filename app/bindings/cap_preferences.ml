let plugin = "preferences"
let unit_ok = Cap_call.unit_ok

(* Only [value: null] (strictly null) means "absent"; a result that is not
   an object, or whose [value] is undefined, is malformed. *)
let value_of_result r =
  match Jv.is_some r && Jv.is_null (Jv.get r "value") with
  | true -> Ok None
  | false -> Result.map Option.some (Cap_call.string_field r "value")

let get ~key =
  Cap_call.call plugin "get"
    [|Jv.obj [|("key", Jv.of_string key)|]|]
    ~ok:value_of_result

let set ~key ~value =
  Cap_call.call plugin "set"
    [|Jv.obj [|("key", Jv.of_string key); ("value", Jv.of_string value)|]|]
    ~ok:unit_ok

let remove ~key =
  Cap_call.call plugin "remove"
    [|Jv.obj [|("key", Jv.of_string key)|]|]
    ~ok:unit_ok
