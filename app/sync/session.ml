type t = {
  access_token : string;
  refresh_token : string;
  expires_at : Ptime.t;
  user_id : string;
  email : string option;
}

let equal a b =
  String.equal a.access_token b.access_token
  && String.equal a.refresh_token b.refresh_token
  && Ptime.equal a.expires_at b.expires_at
  && String.equal a.user_id b.user_id
  && Option.equal String.equal a.email b.email

let version = 1

(* Whole seconds, written as digits rather than an [int]: under js_of_ocaml
   an [int] is 32 bits and would wrap in 2038. *)
let seconds_of t = Printf.sprintf "%.0f" (Float.round (Ptime.to_float_s t))

let to_string s =
  Yojson.Safe.to_string
    (`Assoc
       [
         ("v", `Int version);
         ("access_token", `String s.access_token);
         ("refresh_token", `String s.refresh_token);
         ("expires_at", `Intlit (seconds_of s.expires_at));
         ("user_id", `String s.user_id);
         ("email", match s.email with None -> `Null | Some e -> `String e);
       ])

(* The reasons name the field, never its value: the value may be a token. *)
let string_field fields name =
  match List.assoc_opt name fields with
  | Some (`String s) -> Ok s
  | Some _ -> Error (name ^ " is not a string")
  | None -> Error ("no " ^ name)

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
  let* access_token = string_field fields "access_token" in
  let* refresh_token = string_field fields "refresh_token" in
  let* expires_at =
    (* Yojson reads an integer too large for [int] as [`Intlit]. *)
    let in_range f =
      Option.to_result ~none:"expires_at out of range" (Ptime.of_float_s f)
    in
    match List.assoc_opt "expires_at" fields with
    | Some (`Int n) -> in_range (Float.of_int n)
    | Some (`Intlit digits) -> (
        match float_of_string_opt digits with
        | Some f -> in_range f
        | None -> Error "expires_at is not an int")
    | Some _ -> Error "expires_at is not an int"
    | None -> Error "no expires_at"
  in
  let* user_id = string_field fields "user_id" in
  let+ email =
    match List.assoc_opt "email" fields with
    | None | Some `Null | Some (`String "") -> Ok None
    | Some (`String e) -> Ok (Some e)
    | Some _ -> Error "email is not a string"
  in
  {access_token; refresh_token; expires_at; user_id; email}

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
