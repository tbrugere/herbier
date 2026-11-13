type request = {
  url : string;
  headers : (string * string) list;
  body : string option;
}

let endpoint base_url path =
  Herbier_net.Url.strip_trailing_slashes base_url ^ "/auth/v1/" ^ path

let json_headers apikey =
  [("apikey", apikey); ("Content-Type", "application/json")]

let post_json ~base_url ~apikey path fields =
  {
    url = endpoint base_url path;
    headers = json_headers apikey;
    body = Some (Yojson.Safe.to_string (`Assoc fields));
  }

let id_token_grant ~base_url ~apikey ~id_token ~nonce =
  post_json ~base_url ~apikey "token?grant_type=id_token"
    [
      ("provider", `String "google");
      ("id_token", `String id_token);
      ("nonce", `String nonce);
    ]

let refresh_grant ~base_url ~apikey ~refresh_token =
  post_json ~base_url ~apikey "token?grant_type=refresh_token"
    [("refresh_token", `String refresh_token)]

let logout ~base_url ~apikey ~access_token =
  {
    url = endpoint base_url "logout?scope=local";
    headers = [("apikey", apikey); ("Authorization", "Bearer " ^ access_token)];
    body = None;
  }

type error =
  | Rejected of {status : int; code : string option; message : string}
  | Malformed of string

(* A body kept as the message may be a whole HTML page: one line, cut at a
   UTF-8 character boundary. *)
let one_line s =
  let s = String.map (function '\n' | '\r' -> ' ' | c -> c) s in
  match String.length s > 200 with
  | false -> s
  | true ->
      let rec boundary n =
        match n > 0 && Char.code s.[n] land 0xC0 = 0x80 with
        | true -> boundary (n - 1)
        | false -> n
      in
      String.sub s 0 (boundary 200) ^ "…"

let error_to_string = function
  | Rejected {status; code = Some code; message} ->
      Printf.sprintf "HTTP %d %s: %s" status code (one_line message)
  | Rejected {status; code = None; message} ->
      Printf.sprintf "HTTP %d: %s" status (one_line message)
  | Malformed what -> "malformed session: " ^ one_line what

(* Yojson's message quotes the input it stopped at, which may be token text:
   only that the body is not JSON is kept. *)
let parse body =
  match Yojson.Safe.from_string body with
  | json -> Ok json
  | exception Yojson.Json_error _ -> Error "not JSON"

let success status = status >= 200 && status <= 299

(* GoTrue's error envelope, {"code":<int>,"error_code":<str>,"msg":<str>},
   or its OAuth-style one, {"error":<str>,"error_description":<str>} (the
   id-token grant's checks of the token). Anything else (a proxy's HTML
   page, an empty body) is kept as text. *)
let rejected ~status body =
  let text = Rejected {status; code = None; message = body} in
  let string name fields =
    match List.assoc_opt name fields with
    | Some (`String s) -> Some s
    | Some _ | None -> None
  in
  match parse body with
  | Ok (`Assoc fields) -> (
      match
        ( string "error_code" fields,
          string "msg" fields,
          string "error" fields,
          string "error_description" fields )
      with
      | code, Some message, _, _ -> Rejected {status; code; message}
      | None, None, Some code, Some message ->
          Rejected {status; code = Some code; message}
      | _ -> text)
  | Ok _ | Error _ -> text

type user = {
  id : string;
  email : string option;
      [@default None]
      (* Its error is the path [user.email], which [malformed] reads as it
         reads a derived one. *)
      [@of_yojson
        fun j ->
          Result.map_error
            (fun (_ : string) -> "user.email")
            (Session.email_of_json j)]
}
[@@deriving of_yojson {strict = false}]

type answer = {
  access_token : string;
  refresh_token : string;
  expires_in : int;
  user : user;
}
[@@deriving of_yojson {strict = false}]

(* The derived decoder's errors are paths: [<Module>.answer] or
   [<Module>.user] for a value that is not an object, [<Module>.answer.<field>]
   or [<Module>.user.<field>] for a missing or ill-typed field, kept as the
   field, [user.] prefixed. The tests pin each reason. *)
let malformed e =
  Malformed
    (match List.rev (String.split_on_char '.' e) with
    | "answer" :: _ -> "not an object"
    | "user" :: _ -> "user"
    | f :: "answer" :: _ -> f
    | f :: "user" :: _ -> "user." ^ f
    | _ -> e)

(* The expiry is [now + expires_in], not the answer's [expires_at]: both are
   compared with the device clock, which may be set wrong. *)
let session_of_json ~now json =
  let open Result.Syntax in
  let* a = Result.map_error malformed (answer_of_yojson json) in
  let+ expires_at =
    match a.expires_in > 0 with
    | false -> Error (Malformed "expires_in")
    | true ->
        Option.to_result ~none:(Malformed "expires_in")
          (Ptime.add_span
             (Ptime.truncate ~frac_s:0 now)
             (Ptime.Span.of_int_s a.expires_in))
  in
  {
    Session.access_token = a.access_token;
    refresh_token = a.refresh_token;
    expires_at;
    user_id = a.user.id;
    email = a.user.email;
  }

let decode_session ~now ~status body =
  match success status with
  | false -> Error (rejected ~status body)
  | true -> (
      match parse body with
      | Ok json -> session_of_json ~now json
      | Error m -> Error (Malformed m))

let decode_empty ~status body =
  match success status with
  | true -> Ok ()
  | false -> Error (rejected ~status body)

let revokes_session = function
  | Rejected {status = 408 | 429; _} | Rejected {code = None; _} -> false
  | Rejected {status; code = Some _; _} -> status >= 400 && status <= 499
  | Malformed _ -> false

let signup_disabled = function
  | Rejected {code = Some "signup_disabled"; _} -> true
  | Rejected _ | Malformed _ -> false
