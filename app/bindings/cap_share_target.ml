type listener = Jv.t
type share = {title : string; texts : string list}

let plugin = "shareTarget"

let texts_of_event ev =
  match Cap_call.field ev "texts" with
  | Ok texts when Jv.is_array texts ->
      Ok
        (List.filter_map
           (fun v ->
             match Jstr.to_string (Jv.typeof v) with
             | "string" -> Some (Jv.to_string v)
             | _ -> None)
           (Jv.to_list Fun.id texts))
  | Ok _ -> Error (Cap_error.Unexpected "texts")
  | Error e -> Error e

let share_of_event ev =
  match (Cap_call.string_field ev "title", texts_of_event ev) with
  | Ok title, Ok texts -> Ok {title; texts}
  | Error e, _ | _, Error e -> Error e

(* Only the error is logged, never the event: a share may carry user data. *)
let dropped e =
  Brr.Console.(
    warn
      [
        str "Cap_share_target: dropped shareReceived";
        str (Cap_error.to_string e);
      ])

let on_share_received f =
  let callback =
    Jv.callback ~arity:1 (fun ev ->
        match share_of_event ev with Ok s -> f s | Error e -> dropped e)
  in
  Cap_call.call plugin "addListener"
    [|Jv.of_string "shareReceived"; callback|]
    ~ok:(fun handle -> Ok handle)

let remove handle = Cap_call.on handle "remove" [||] ~ok:Cap_call.unit_ok
