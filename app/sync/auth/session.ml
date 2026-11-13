(* Whole seconds, written as digits rather than an [int]: under js_of_ocaml
   an [int] is 32 bits and would wrap in 2038. *)
let seconds_to_json t =
  `Intlit (Printf.sprintf "%.0f" (Float.round (Ptime.to_float_s t)))

(* Yojson reads an integer too large for [int] as [`Intlit]. *)
let seconds_of_json json =
  let in_range f =
    Option.to_result ~none:"expires_at out of range" (Ptime.of_float_s f)
  in
  match json with
  | `Int n -> in_range (Float.of_int n)
  | `Intlit digits -> (
      match float_of_string_opt digits with
      | Some f -> in_range f
      | None -> Error "expires_at is not an int")
  | _ -> Error "expires_at is not an int"

let email_of_json = function
  | `Null | `String "" -> Ok None
  | `String e -> Ok (Some e)
  | _ -> Error "email is not a string"

type t = {
  access_token : string;
  refresh_token : string;
  expires_at : Ptime.t;
      [@to_yojson seconds_to_json] [@of_yojson seconds_of_json]
  user_id : string;
  email : string option; [@of_yojson email_of_json]
}
[@@deriving eq, yojson {strict = false}]

let version = 1

let to_string s =
  Yojson.Safe.(
    to_string (Util.combine (`Assoc [("v", `Int version)]) (to_yojson s)))

(* The derived decoder reports a missing or ill-typed field as its path,
   [<Module>.t.<field>] (the tests pin the reasons, so a ppx that changes the
   format fails them); [seconds_of_json] and [email_of_json] give their own.
   A reason names the field, never its value: the value may be a token. *)
let reason e =
  match
    List.find_opt
      (fun field -> String.ends_with ~suffix:(".t." ^ field) e)
      ["access_token"; "refresh_token"; "expires_at"; "user_id"; "email"]
  with
  | Some field -> field ^ " missing or ill-typed"
  | None -> e

let of_string text =
  let open Result.Syntax in
  let* json =
    match Yojson.Safe.from_string text with
    | json -> Ok json
    | exception Yojson.Json_error _ -> Error "not JSON"
  in
  let* fields =
    match json with `Assoc fields -> Ok fields | _ -> Error "not an object"
  in
  let* () =
    match List.assoc_opt "v" fields with
    | Some (`Int v) when v = version -> Ok ()
    | Some _ -> Error "unknown version"
    | None -> Error "no version"
  in
  (* Not [[@default None]]: it would also leave a [None] email out of
     {!to_string}, whose bytes keep ["email":null]. *)
  let fields =
    match List.mem_assoc "email" fields with
    | true -> fields
    | false -> ("email", `Null) :: fields
  in
  Result.map_error reason (of_yojson (`Assoc fields))

let refresh_margin = Ptime.Span.of_int_s 90
let left ~now s = Ptime.diff s.expires_at now
let due ~now s = Ptime.Span.compare (left ~now s) refresh_margin <= 0

let refresh_in ~now s =
  let d = Ptime.Span.sub (left ~now s) refresh_margin in
  match Ptime.Span.compare d Ptime.Span.zero <= 0 with
  | true -> Ptime.Span.zero
  | false -> d

let expired ~now s =
  Ptime.Span.compare (left ~now s) (Ptime.Span.of_int_s 5) <= 0

let retry_cap_s = 300

(* 10 × 2^5 = 320 > 300: from the sixth attempt on the cap applies, which
   keeps the shift small. *)
let retry_delay ~attempt =
  match attempt with
  | n when n <= 1 -> Ptime.Span.of_int_s 10
  | n when n >= 6 -> Ptime.Span.of_int_s retry_cap_s
  | n -> Ptime.Span.of_int_s (min retry_cap_s (10 lsl (n - 1)))

let with_expiry expires_at s = {s with expires_at}
