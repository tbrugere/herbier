type notice = {
  title : string;
  text : string option;
  value : int;
  max : int;
  action : string option;
}

type notifications = Granted | Denied
type reason = User | Timeout
type listener = Jv.t

let plugin = "foregroundRun"

let notice_jv {title; text; value; max; action} =
  let optional key = Option.map (fun s -> (key, Jv.of_string s)) in
  Jv.obj
    (Array.of_list
       (List.filter_map Fun.id
          [
            Some ("title", Jv.of_string title);
            optional "text" text;
            Some ("value", Jv.of_int value);
            Some ("max", Jv.of_int max);
            optional "action" action;
          ]))

let notifications_of r =
  match Cap_call.string_field r "notifications" with
  | Ok "granted" -> Ok Granted
  | Ok "denied" -> Ok Denied
  | Ok _ | Error _ -> Error (Cap_error.Unexpected "notifications")

let start notice =
  Cap_call.call plugin "start" [|notice_jv notice|] ~ok:notifications_of

let update notice =
  Cap_call.call plugin "update" [|notice_jv notice|] ~ok:Cap_call.unit_ok

let stop () = Cap_call.call plugin "stop" [||] ~ok:Cap_call.unit_ok

(* Never raises: it runs in the JS event's callback. *)
let reason_of data =
  match Cap_call.string_field data "reason" with
  | Ok "timeout" -> Timeout
  | Ok _ | Error _ -> User

let on_interrupt f =
  let callback = Jv.callback ~arity:1 (fun data -> f (reason_of data)) in
  Cap_call.call plugin "addListener"
    [|Jv.of_string "interrupt"; callback|]
    ~ok:(fun handle -> Ok handle)

let remove handle = Cap_call.on handle "remove" [||] ~ok:Cap_call.unit_ok
