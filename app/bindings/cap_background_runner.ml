let plugin = "backgroundRunner"

(* The plugin resolves with nothing when the handler gave [resolve] no
   argument; only a [json] that is there and not a string is malformed. *)
let json_of_result r =
  match Jv.is_some r && Jv.is_some (Jv.get r "json") with
  | false -> Ok None
  | true -> Result.map Option.some (Cap_call.string_field r "json")

let dispatch_event ~label ~event ~json =
  let details =
    match json with
    | None -> Jv.obj [||]
    | Some text -> Jv.obj [|("json", Jv.of_string text)|]
  in
  Cap_call.call plugin "dispatchEvent"
    [|
      Jv.obj
        [|
          ("label", Jv.of_string label);
          ("event", Jv.of_string event);
          ("details", details);
        |];
    |]
    ~ok:json_of_result
