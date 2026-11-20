type connection = Wifi | Cellular | No_connection | Unknown
type status = {connected : bool; connection : connection}

let connection_of_string = function
  | "wifi" -> Wifi
  | "cellular" -> Cellular
  | "none" -> No_connection
  | _ -> Unknown

let status () =
  Cap_call.call "network" "getStatus" [||] ~ok:(fun v ->
      Result.map
        (fun connected ->
          {
            connected;
            connection =
              (match Cap_call.string_field v "connectionType" with
              | Ok s -> connection_of_string s
              | Error (_ : Cap_error.t) -> Unknown);
          })
        (Cap_call.bool_field v "connected"))
