let plugin = "exifr"

let options ~pick =
  Jv.obj
    [|
      ("pick", Jv.of_list Jv.of_string pick);
      ("reviveValues", Jv.false');
      ("translateValues", Jv.false');
    |]

let json_text v =
  match Jv.is_none v with
  | true -> Ok None
  | false -> Ok (Some (Jstr.to_string (Brr.Json.encode v)))

let parse ~pick blob =
  Cap_call.call plugin "parse"
    [|Brr.Blob.to_jv blob; options ~pick|]
    ~ok:json_text
