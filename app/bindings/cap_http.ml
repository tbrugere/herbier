type response = Body of string | Status of int

let response r =
  let open Result.Syntax in
  let* status = Cap_call.int_field r "status" in
  match status >= 200 && status < 300 with
  | true ->
      let+ base64 = Cap_call.string_field r "data" in
      Body base64
  | false -> Ok (Status status)

let get_bytes ~url ~timeout_ms =
  Cap_call.call "http" "get"
    [|
      Jv.obj
        [|
          ("url", Jv.of_string url);
          ("responseType", Jv.of_string "blob");
          ("connectTimeout", Jv.of_int timeout_ms);
          ("readTimeout", Jv.of_int timeout_ms);
          ("disableRedirects", Jv.of_bool true);
        |];
    |]
    ~ok:response
