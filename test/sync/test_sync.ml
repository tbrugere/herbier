(* Native checks of app/sync_core/auth/session.ml, nonce.ml, gotrue.ml and
   grant.ml (Auth.Session, Auth.Nonce, Auth.Gotrue and Auth.Grant of
   herbier_sync_core). Fixture
   bodies are read from test/fixtures/; the status that goes with each is
   given by the test, matching the fixture's name. No test sends a request or
   touches Preferences: auth.ml, the binding and the screen are
   device-checked. *)

module Backoff = Herbier_sync_core.Backoff
module Session = Herbier_sync_core.Auth.Session
module Nonce = Herbier_sync_core.Auth.Nonce
module Gotrue = Herbier_sync_core.Auth.Gotrue
module Grant = Herbier_sync_core.Auth.Grant
module Fixture = Herbier_test_support.Fixture
module Text = Herbier_test_support.Text

(* ---------- Session ---------- *)

let t0 =
  match Ptime.of_float_s 1_800_000_000. with
  | Some t -> t
  | None -> Alcotest.fail "Ptime.of_float_s rejected the reference instant"

let shift secs t =
  match Ptime.add_span t (Ptime.Span.of_int_s secs) with
  | Some t -> t
  | None -> Alcotest.failf "shift %d overflowed Ptime" secs

let session ?(email = Some "person@example.com") ~expires_at () : Session.t =
  {
    Session.access_token = "AT-token";
    refresh_token = "RT-token";
    expires_at;
    user_id = "user-1";
    email;
  }

let session_json (s : Session.t) : Yojson.Safe.t =
  `Assoc
    [
      ("access_token", `String s.access_token);
      ("refresh_token", `String s.refresh_token);
      ("expires_at", `String (Ptime.to_rfc3339 ~tz_offset_s:0 s.expires_at));
      ("user_id", `String s.user_id);
      ("email", match s.email with None -> `Null | Some e -> `String e);
    ]

let session_t =
  Alcotest.testable
    (fun f s ->
      Format.pp_print_string f (Yojson.Safe.pretty_to_string (session_json s)))
    Session.equal

let session_round_trips_through_its_string_form () =
  let with_email = session ~email:(Some "a@b.example") ~expires_at:t0 () in
  (match Session.of_string (Session.to_string with_email) with
  | Ok s -> Alcotest.(check session_t) "email Some round-trips" with_email s
  | Error e -> Alcotest.failf "of_string (to_string _) gave Error %S" e);
  let no_email = session ~email:None ~expires_at:t0 () in
  match Session.of_string (Session.to_string no_email) with
  | Ok s -> Alcotest.(check session_t) "email None round-trips" no_email s
  | Error e -> Alcotest.failf "of_string (to_string _) gave Error %S" e

let session_of_json () =
  let s = session ~email:(Some "a@b.example") ~expires_at:t0 () in
  Alcotest.(check (result session_t string))
    "of_json (to_json s)" (Ok s)
    (Session.of_json (Session.to_json s));
  Alcotest.(check (result session_t string))
    "not an object" (Error "not an object")
    (Session.of_json (`Int 5))

let session_rounds_expires_at_to_the_nearest_second () =
  let s = session ~expires_at:t0 () in
  let at_fraction f =
    match Ptime.add_span t0 (Ptime.Span.of_float_s f |> Option.get) with
    | Some t -> t
    | None -> Alcotest.fail "t0 + fraction overflowed"
  in
  let round_trip at =
    match Session.of_string (Session.to_string (Session.with_expiry at s)) with
    | Ok s -> s.expires_at
    | Error e -> Alcotest.failf "of_string (to_string _) gave Error %S" e
  in
  Alcotest.(check bool)
    "t0 + 0.6 s is stored as t0 + 1 s" true
    (Ptime.equal (shift 1 t0) (round_trip (at_fraction 0.6)));
  Alcotest.(check bool)
    "t0 + 0.4 s is stored as t0" true
    (Ptime.equal t0 (round_trip (at_fraction 0.4)))

let of_string_reads_an_empty_or_absent_email_as_none () =
  let email input =
    match Session.of_string input with
    | Ok s -> s.email
    | Error e -> Alcotest.failf "expected Ok, got Error %S" e
  in
  Alcotest.(check (option string))
    "email \"\"" None
    (email
       {|{"v":1,"access_token":"a","refresh_token":"r","expires_at":1,"user_id":"u","email":""}|});
  Alcotest.(check (option string))
    "email absent" None
    (email
       {|{"v":1,"access_token":"a","refresh_token":"r","expires_at":1,"user_id":"u"}|})

let of_string_rejects_bad_input () =
  let bad name ~reason input =
    match Session.of_string input with
    | Error e -> Alcotest.(check string) (name ^ ": reason") reason e
    | Ok _ -> Alcotest.failf "%s: expected Error, got Ok" name
  in
  bad "not json" ~reason:"not JSON" "not json";
  bad "a JSON array" ~reason:"not an object" "[]";
  bad "no \"v\"" ~reason:"no version"
    {|{"access_token":"a","refresh_token":"r","expires_at":1,"user_id":"u","email":null}|};
  bad "\"v\":2" ~reason:"unknown version"
    {|{"v":2,"access_token":"a","refresh_token":"r","expires_at":1,"user_id":"u","email":null}|};
  bad "missing access_token" ~reason:"access_token missing or ill-typed"
    {|{"v":1,"refresh_token":"r","expires_at":1,"user_id":"u","email":null}|};
  bad "access_token as a number" ~reason:"access_token missing or ill-typed"
    {|{"v":1,"access_token":1,"refresh_token":"r","expires_at":1,"user_id":"u","email":null}|};
  bad "missing refresh_token" ~reason:"refresh_token missing or ill-typed"
    {|{"v":1,"access_token":"a","expires_at":1,"user_id":"u","email":null}|};
  bad "missing expires_at" ~reason:"expires_at missing or ill-typed"
    {|{"v":1,"access_token":"a","refresh_token":"r","user_id":"u","email":null}|};
  bad "expires_at as a string" ~reason:"expires_at is not an int"
    {|{"v":1,"access_token":"a","refresh_token":"r","expires_at":"soon","user_id":"u","email":null}|};
  bad "expires_at as a float" ~reason:"expires_at is not an int"
    {|{"v":1,"access_token":"a","refresh_token":"r","expires_at":1.5,"user_id":"u","email":null}|};
  bad "expires_at past Ptime's range (year 10000 and later)"
    ~reason:"expires_at out of range"
    {|{"v":1,"access_token":"a","refresh_token":"r","expires_at":253402300800,"user_id":"u","email":null}|};
  bad "expires_at too large for an int" ~reason:"expires_at out of range"
    {|{"v":1,"access_token":"a","refresh_token":"r","expires_at":99999999999999999999,"user_id":"u","email":null}|};
  bad "missing user_id" ~reason:"user_id missing or ill-typed"
    {|{"v":1,"access_token":"a","refresh_token":"r","expires_at":1,"email":null}|};
  bad "email as a number" ~reason:"email is not a string"
    {|{"v":1,"access_token":"a","refresh_token":"r","expires_at":1,"user_id":"u","email":3}|}

let of_string_ignores_an_unknown_extra_field () =
  let input =
    {|{"v":1,"access_token":"a","refresh_token":"r","expires_at":1000,"user_id":"u","email":null,"extra":"ignored"}|}
  in
  match Session.of_string input with
  | Error e -> Alcotest.failf "expected Ok, got Error %S" e
  | Ok s ->
      let expected =
        match Ptime.of_span (Ptime.Span.of_int_s 1000) with
        | Some expires_at -> session ~email:None ~expires_at ()
        | None -> Alcotest.fail "1000s is not a valid Ptime.span"
      in
      Alcotest.(check session_t)
        "extra field ignored"
        {expected with access_token = "a"; refresh_token = "r"; user_id = "u"}
        s

let of_string_error_never_contains_the_tokens () =
  let input =
    {|{"v":1,"access_token":"AT_SECRET_TOKEN_VALUE","refresh_token":"RT_SECRET_TOKEN_VALUE","expires_at":"broken","user_id":"u","email":null}|}
  in
  match Session.of_string input with
  | Ok _ -> Alcotest.fail "expected Error (expires_at is a string), got Ok"
  | Error msg ->
      Alcotest.(check bool)
        "no access token in the error" false
        (Text.contains ~sub:"AT_SECRET_TOKEN_VALUE" msg);
      Alcotest.(check bool)
        "no refresh token in the error" false
        (Text.contains ~sub:"RT_SECRET_TOKEN_VALUE" msg)

let due_near_the_90s_margin () =
  let s = session ~expires_at:t0 () in
  Alcotest.(check bool)
    "T - 91s: not due" false
    (Session.due ~now:(shift (-91) t0) s);
  Alcotest.(check bool)
    "T - 90s: due" true
    (Session.due ~now:(shift (-90) t0) s);
  Alcotest.(check bool) "T + 1s: due" true (Session.due ~now:(shift 1 t0) s)

let refresh_in_counts_down_to_the_margin () =
  let s = session ~expires_at:t0 () in
  let span_s span = Ptime.Span.to_int_s span in
  Alcotest.(check (option int))
    "600s before expiry: 510s left" (Some 510)
    (span_s (Session.refresh_in ~now:(shift (-600) t0) s));
  Alcotest.(check (option int))
    "exactly at the margin: 0s left" (Some 0)
    (span_s (Session.refresh_in ~now:(shift (-90) t0) s));
  Alcotest.(check (option int))
    "past due: never negative" (Some 0)
    (span_s (Session.refresh_in ~now:(shift 10 t0) s))

let expired_at_the_5s_cutoff () =
  let s = session ~expires_at:t0 () in
  Alcotest.(check bool)
    "T - 6s: not expired" false
    (Session.expired ~now:(shift (-6) t0) s);
  Alcotest.(check bool)
    "T - 5s: expired" true
    (Session.expired ~now:(shift (-5) t0) s)

let retry_delay_backs_off_and_caps_at_300s () =
  let secs attempt = Ptime.Span.to_int_s (Backoff.delay ~attempt) in
  Alcotest.(check (option int)) "attempt -5" (Some 10) (secs (-5));
  Alcotest.(check (option int)) "attempt 0" (Some 10) (secs 0);
  Alcotest.(check (option int)) "attempt 1" (Some 10) (secs 1);
  Alcotest.(check (option int)) "attempt 2" (Some 20) (secs 2);
  Alcotest.(check (option int)) "attempt 3" (Some 40) (secs 3);
  Alcotest.(check (option int)) "attempt 4" (Some 80) (secs 4);
  Alcotest.(check (option int)) "attempt 5" (Some 160) (secs 5);
  Alcotest.(check (option int)) "attempt 6" (Some 300) (secs 6);
  Alcotest.(check (option int)) "attempt 1000" (Some 300) (secs 1000);
  Alcotest.(check (option int)) "attempt max_int" (Some 300) (secs max_int);
  Alcotest.(check (option int)) "attempt min_int" (Some 10) (secs min_int)

(* The two copies Backoff.delay replaced, verbatim: Session.retry_delay
   (refreshes) and Schedule.retry_delay (cycles). They agree on every attempt
   but min_int, where Schedule's [attempt - 1] wrapped round to 300 s against
   its own contract ([attempt <= 1] → 10 s); both count attempts up from 0. *)
let session_retry_delay ~attempt =
  let retry_cap_s = 300 in
  match attempt with
  | n when n <= 1 -> Ptime.Span.of_int_s 10
  | n when n >= 6 -> Ptime.Span.of_int_s retry_cap_s
  | n -> Ptime.Span.of_int_s (min retry_cap_s (10 lsl (n - 1)))

let schedule_retry_delay ~attempt =
  let exponent = min 5 (max 0 (attempt - 1)) in
  Ptime.Span.of_int_s (min 300 (10 * (1 lsl exponent)))

let backoff_is_both_former_copies () =
  let attempts =
    List.init 80 (fun i -> i - 10)
    @ [max_int; max_int - 1; min_int + 1; 1 lsl 40]
  in
  List.iter
    (fun attempt ->
      let got = Backoff.delay ~attempt in
      let name = string_of_int attempt in
      Alcotest.(check bool)
        ("session's, attempt " ^ name)
        true
        (Ptime.Span.equal got (session_retry_delay ~attempt));
      Alcotest.(check bool)
        ("schedule's, attempt " ^ name)
        true
        (Ptime.Span.equal got (schedule_retry_delay ~attempt)))
    attempts

let with_expiry_changes_only_expires_at () =
  let s = session ~expires_at:t0 () in
  let new_expiry = shift 500 t0 in
  let s' = Session.with_expiry new_expiry s in
  Alcotest.(check bool)
    "expires_at replaced" true
    (Ptime.equal new_expiry s'.expires_at);
  Alcotest.(check string)
    "access_token unchanged" s.access_token s'.access_token;
  Alcotest.(check string)
    "refresh_token unchanged" s.refresh_token s'.refresh_token;
  Alcotest.(check string) "user_id unchanged" s.user_id s'.user_id;
  Alcotest.(check (option string)) "email unchanged" s.email s'.email

let session_tests =
  [
    ( "to_string then of_string gives back an equal session",
      `Quick,
      session_round_trips_through_its_string_form );
    ( "of_json reads to_json back; anything but an object is an error",
      `Quick,
      session_of_json );
    ( "expires_at is stored rounded to the nearest second",
      `Quick,
      session_rounds_expires_at_to_the_nearest_second );
    ( "of_string reads an empty or absent email as None",
      `Quick,
      of_string_reads_an_empty_or_absent_email_as_none );
    ( "of_string rejects malformed input without raising",
      `Quick,
      of_string_rejects_bad_input );
    ( "of_string ignores an unknown extra field",
      `Quick,
      of_string_ignores_an_unknown_extra_field );
    ( "of_string's error message never contains a token value",
      `Quick,
      of_string_error_never_contains_the_tokens );
    ( "due is true exactly at and after the 90s margin",
      `Quick,
      due_near_the_90s_margin );
    ( "refresh_in counts down to the margin, never negative",
      `Quick,
      refresh_in_counts_down_to_the_margin );
    ( "expired is true at and after the 5s cutoff",
      `Quick,
      expired_at_the_5s_cutoff );
    ( "retry_delay doubles from 10s and caps at 300s",
      `Quick,
      retry_delay_backs_off_and_caps_at_300s );
    ( "Backoff.delay is both copies it replaced",
      `Quick,
      backoff_is_both_former_copies );
    ( "with_expiry changes only expires_at",
      `Quick,
      with_expiry_changes_only_expires_at );
  ]

(* ---------- Session: stored format (v1) ---------- *)

let at_s secs =
  match Ptime.of_float_s secs with
  | Some t -> t
  | None -> Alcotest.failf "%.0f s is not a Ptime" secs

let to_string_writes_the_recorded_v1_bytes () =
  Alcotest.(check string)
    "email Some" Stored_v1.with_email
    (Session.to_string (session ~expires_at:t0 ()));
  Alcotest.(check string)
    "email None" Stored_v1.without_email
    (Session.to_string (session ~email:None ~expires_at:t0 ()));
  Alcotest.(check string)
    "expiry in 2100: digits, no exponent or .0" Stored_v1.in_2100
    (Session.to_string (session ~expires_at:(at_s 4_102_444_800.) ()));
  Alcotest.(check string)
    "t0 + 0.6 s written as t0 + 1 s"
    {|{"v":1,"access_token":"AT-token","refresh_token":"RT-token","expires_at":1800000001,"user_id":"user-1","email":"person@example.com"}|}
    (Session.to_string (session ~expires_at:(at_s 1_800_000_000.6) ()))

let of_string_reads_recorded_v1_values () =
  let read name input expected =
    match Session.of_string input with
    | Ok s -> Alcotest.(check session_t) name expected s
    | Error e -> Alcotest.failf "%s: expected Ok, got Error %S" name e
  in
  read "email string" Stored_v1.with_email (session ~expires_at:t0 ());
  read "email null" Stored_v1.without_email
    (session ~email:None ~expires_at:t0 ());
  read "expiry in 2100" Stored_v1.in_2100
    (session ~expires_at:(at_s 4_102_444_800.) ());
  read "email \"\""
    {|{"v":1,"access_token":"AT-token","refresh_token":"RT-token","expires_at":1800000000,"user_id":"user-1","email":""}|}
    (session ~email:None ~expires_at:t0 ());
  read "email absent"
    {|{"v":1,"access_token":"AT-token","refresh_token":"RT-token","expires_at":1800000000,"user_id":"user-1"}|}
    (session ~email:None ~expires_at:t0 ());
  read "small expires_at"
    {|{"v":1,"access_token":"AT-token","refresh_token":"RT-token","expires_at":1000,"user_id":"user-1","email":null}|}
    (session ~email:None ~expires_at:(at_s 1000.) ());
  read "unknown field"
    {|{"v":1,"access_token":"AT-token","refresh_token":"RT-token","expires_at":1800000000,"user_id":"user-1","email":null,"later":{"x":[1]}}|}
    (session ~email:None ~expires_at:t0 ());
  read "keys in another order"
    {|{"email":"person@example.com","user_id":"user-1","expires_at":1800000000,"refresh_token":"RT-token","access_token":"AT-token","v":1}|}
    (session ~expires_at:t0 ())

let session_stored_format_tests =
  [
    ( "to_string writes the recorded v1 bytes",
      `Quick,
      to_string_writes_the_recorded_v1_bytes );
    ( "of_string reads recorded v1 values (email null/\"\"/absent, any key \
       order, extra fields)",
      `Quick,
      of_string_reads_recorded_v1_values );
  ]

(* ---------- Nonce ---------- *)

let hex_of_the_empty_string_is_empty () =
  Alcotest.(check string) "hex \"\"" "" (Nonce.hex "")

let hex_is_lowercase_two_digits_per_byte () =
  Alcotest.(check string)
    "hex \"\\x00\\x0f\\xffA\"" "000fff41"
    (Nonce.hex "\x00\x0f\xffA")

let hex_length_is_twice_the_input_s () =
  let low = String.init 32 Char.chr in
  let high = String.init 32 (fun i -> Char.chr (224 + i)) in
  Alcotest.(check int) "32 low bytes (0-31)" 64 (String.length (Nonce.hex low));
  Alcotest.(check int)
    "32 high bytes (224-255)" 64
    (String.length (Nonce.hex high))

let nonce_tests =
  [
    ( "hex of the empty string is empty",
      `Quick,
      hex_of_the_empty_string_is_empty );
    ( "hex is lowercase, two digits per byte",
      `Quick,
      hex_is_lowercase_two_digits_per_byte );
    ( "hex's length is twice the input's",
      `Quick,
      hex_length_is_twice_the_input_s );
  ]

(* ---------- Gotrue requests ---------- *)

let has_header pair (req : Gotrue.request) = List.mem pair req.headers

let no_authorization_header (req : Gotrue.request) =
  List.for_all
    (fun (k, _) ->
      not (String.equal (String.lowercase_ascii k) "authorization"))
    req.headers

let json_t = Alcotest.testable Yojson.Safe.pretty_print Yojson.Safe.equal

let body_json (req : Gotrue.request) : Yojson.Safe.t =
  match req.body with
  | Some b -> Yojson.Safe.from_string b
  | None -> Alcotest.fail "expected a body, the request had none"

let id_token_grant_shape () =
  let req =
    Gotrue.id_token_grant ~base_url:"http://127.0.0.1:54321" ~apikey:"k"
      ~id_token:"t" ~nonce:"n"
  in
  Alcotest.(check string)
    "url" "http://127.0.0.1:54321/auth/v1/token?grant_type=id_token" req.url;
  Alcotest.(check bool)
    "has apikey header" true
    (has_header ("apikey", "k") req);
  Alcotest.(check bool)
    "has Content-Type header" true
    (has_header ("Content-Type", "application/json") req);
  Alcotest.(check bool)
    "no Authorization header" true
    (no_authorization_header req);
  Alcotest.check json_t "body is exactly {provider,id_token,nonce}"
    (`Assoc
       [
         ("provider", `String "google");
         ("id_token", `String "t");
         ("nonce", `String "n");
       ])
    (body_json req)

let id_token_grant_joins_a_trailing_slash_base_url_without_doubling_it () =
  let req =
    Gotrue.id_token_grant ~base_url:"https://x.supabase.co/" ~apikey:"k"
      ~id_token:"t" ~nonce:"n"
  in
  Alcotest.(check string)
    "no double slash" "https://x.supabase.co/auth/v1/token?grant_type=id_token"
    req.url

let id_token_grant_round_trips_quotes_and_backslashes () =
  let id_token = {|x."y\z|} in
  let nonce = {|a\b"c|} in
  let req =
    Gotrue.id_token_grant ~base_url:"http://127.0.0.1:54321" ~apikey:"k"
      ~id_token ~nonce
  in
  match body_json req with
  | `Assoc fields ->
      Alcotest.(check (option string))
        "id_token round-trips" (Some id_token)
        (match List.assoc_opt "id_token" fields with
        | Some (`String s) -> Some s
        | _ -> None);
      Alcotest.(check (option string))
        "nonce round-trips" (Some nonce)
        (match List.assoc_opt "nonce" fields with
        | Some (`String s) -> Some s
        | _ -> None)
  | _ -> Alcotest.fail "body is not a JSON object"

let refresh_grant_shape () =
  let req =
    Gotrue.refresh_grant ~base_url:"http://127.0.0.1:54321" ~apikey:"k"
      ~refresh_token:"r"
  in
  Alcotest.(check string)
    "url" "http://127.0.0.1:54321/auth/v1/token?grant_type=refresh_token"
    req.url;
  Alcotest.check json_t "body is exactly {refresh_token}"
    (`Assoc [("refresh_token", `String "r")])
    (body_json req);
  Alcotest.(check bool)
    "has apikey header" true
    (has_header ("apikey", "k") req);
  Alcotest.(check bool)
    "has Content-Type header" true
    (has_header ("Content-Type", "application/json") req);
  Alcotest.(check bool)
    "no Authorization header" true
    (no_authorization_header req)

let logout_shape () =
  let req =
    Gotrue.logout ~base_url:"http://127.0.0.1:54321" ~apikey:"k"
      ~access_token:"a"
  in
  Alcotest.(check string)
    "url" "http://127.0.0.1:54321/auth/v1/logout?scope=local" req.url;
  Alcotest.(check bool)
    "has apikey header" true
    (has_header ("apikey", "k") req);
  Alcotest.(check bool)
    "has Authorization: Bearer a" true
    (has_header ("Authorization", "Bearer a") req);
  Alcotest.(check (option string)) "no body" None req.body

let gotrue_request_tests =
  [
    ("id_token_grant: url, headers and body", `Quick, id_token_grant_shape);
    ( "id_token_grant: a trailing slash in base_url is not doubled",
      `Quick,
      id_token_grant_joins_a_trailing_slash_base_url_without_doubling_it );
    ( "id_token_grant: a quote and a backslash round-trip through the body",
      `Quick,
      id_token_grant_round_trips_quotes_and_backslashes );
    ("refresh_grant: url, headers and body", `Quick, refresh_grant_shape);
    ("logout: url, headers and no body", `Quick, logout_shape);
  ]

(* ---------- Gotrue responses ---------- *)

let gotrue_error_to_json : Gotrue.error -> Yojson.Safe.t = function
  | Gotrue.Rejected {status; code; message} ->
      `Assoc
        [
          ("kind", `String "Rejected");
          ("status", `Int status);
          ("code", match code with None -> `Null | Some c -> `String c);
          ("message", `String message);
        ]
  | Gotrue.Malformed message ->
      `Assoc [("kind", `String "Malformed"); ("message", `String message)]

let gotrue_error_t =
  Alcotest.testable
    (fun f e ->
      Format.pp_print_string f
        (Yojson.Safe.pretty_to_string (gotrue_error_to_json e)))
    (fun a b ->
      Yojson.Safe.equal (gotrue_error_to_json a) (gotrue_error_to_json b))

(* When the request was sent: the decoded expiry is this plus expires_in. *)
let sent = t0

let check_decode_session ?(now = sent) name ~status body expected =
  let actual = Gotrue.decode_session ~now ~status body in
  Alcotest.(check (result session_t gotrue_error_t)) name expected actual

(* The fixture's own fields, read with Yojson (never via Session/Gotrue). *)
let expected_session_of_fixture_json ?(now = sent) (json : Yojson.Safe.t) :
    Session.t =
  match json with
  | `Assoc fields -> (
      match
        ( List.assoc_opt "access_token" fields,
          List.assoc_opt "refresh_token" fields,
          List.assoc_opt "expires_in" fields,
          List.assoc_opt "user" fields )
      with
      | ( Some (`String access_token),
          Some (`String refresh_token),
          Some (`Int expires_in_s),
          Some (`Assoc user_fields) ) -> (
          match List.assoc_opt "id" user_fields with
          | Some (`String user_id) ->
              let email =
                match List.assoc_opt "email" user_fields with
                | Some (`String "") -> None
                | Some (`String e) -> Some e
                | _ -> None
              in
              let expires_at = shift expires_in_s now in
              {Session.access_token; refresh_token; expires_at; user_id; email}
          | _ -> Alcotest.fail "fixture's user has no string id")
      | _ -> Alcotest.fail "fixture is missing a field decode_session needs")
  | _ -> Alcotest.fail "fixture is not a JSON object"

let fixture_200_text = Fixture.read "gotrue_token_refresh_200.json"
let fixture_200_json = Yojson.Safe.from_string fixture_200_text

let fixture_not_found_text =
  Fixture.read "gotrue_token_refresh_not_found_400.json"

let fixture_invalid_text = Fixture.read "gotrue_token_refresh_invalid_400.json"

let fixture_signup_disabled_text =
  Fixture.read "gotrue_signup_disabled_422.json"

let fixture_id_token_invalid_text =
  Fixture.read "gotrue_token_id_token_invalid_request_400.json"

(* Derives a variant of the 200 fixture's top-level JSON, never a file. *)
let remove_top_field key json =
  match json with
  | `Assoc fields ->
      `Assoc (List.filter (fun (k, _) -> not (String.equal k key)) fields)
  | j -> j

let set_top_field key value json =
  match json with
  | `Assoc fields ->
      `Assoc
        (List.map
           (fun (k, v) ->
             match String.equal k key with true -> (k, value) | false -> (k, v))
           fields)
  | j -> j

let set_user_email value json =
  match json with
  | `Assoc fields ->
      `Assoc
        (List.map
           (fun (k, v) ->
             match (k, v) with
             | "user", `Assoc user_fields ->
                 ( k,
                   `Assoc
                     (List.map
                        (fun (uk, uv) ->
                          match String.equal uk "email" with
                          | true -> (uk, value)
                          | false -> (uk, uv))
                        user_fields) )
             | _ -> (k, v))
           fields)
  | j -> j

let remove_user_email json =
  match json with
  | `Assoc fields ->
      `Assoc
        (List.map
           (fun (k, v) ->
             match (k, v) with
             | "user", `Assoc user_fields ->
                 ( k,
                   `Assoc
                     (List.filter
                        (fun (uk, _) -> not (String.equal uk "email"))
                        user_fields) )
             | _ -> (k, v))
           fields)
  | j -> j

let decode_session_200_matches_the_fixture_s_own_fields () =
  check_decode_session "decode_session of gotrue_token_refresh_200.json"
    ~status:200 fixture_200_text
    (Ok (expected_session_of_fixture_json fixture_200_json))

let decode_session_200_ignores_the_answer_s_expires_at () =
  let skewed = shift 7200 sent in
  check_decode_session ~now:skewed
    "a device clock 2 h ahead: expires_in after the device's now" ~status:200
    fixture_200_text
    (Ok (expected_session_of_fixture_json ~now:skewed fixture_200_json))

let decode_session_200_truncates_now_to_the_second () =
  let now =
    match Ptime.add_span sent (Option.get (Ptime.Span.of_float_s 0.7)) with
    | Some t -> t
    | None -> Alcotest.fail "sent + 0.7 s overflowed"
  in
  check_decode_session ~now "now = t0 + 0.7 s" ~status:200 fixture_200_text
    (Ok (expected_session_of_fixture_json ~now:sent fixture_200_json))

(* [reason]: the Malformed payload expected; [None] checks the constructor
   only. *)
let check_malformed ?reason name body =
  match Gotrue.decode_session ~now:sent ~status:200 body with
  | Error (Gotrue.Malformed m) ->
      Option.iter
        (fun r -> Alcotest.(check string) (name ^ ": reason") r m)
        reason
  | Error (Gotrue.Rejected _) ->
      Alcotest.failf "%s: expected Malformed, got Rejected" name
  | Ok _ -> Alcotest.failf "%s: expected Error (Malformed _), got Ok" name

let decode_session_200_without_refresh_token_is_malformed () =
  check_malformed ~reason:"refresh_token" "refresh_token removed"
    (Yojson.Safe.to_string (remove_top_field "refresh_token" fixture_200_json))

let decode_session_200_with_a_string_expires_in_is_malformed () =
  check_malformed ~reason:"expires_in" "expires_in made a string"
    (Yojson.Safe.to_string
       (set_top_field "expires_in" (`String "soon") fixture_200_json));
  check_malformed ~reason:"expires_in" "expires_in 0"
    (Yojson.Safe.to_string
       (set_top_field "expires_in" (`Int 0) fixture_200_json))

let decode_session_200_without_user_is_malformed () =
  check_malformed ~reason:"user" "user removed"
    (Yojson.Safe.to_string (remove_top_field "user" fixture_200_json))

let decode_session_200_with_an_empty_user_email_is_none () =
  let body =
    Yojson.Safe.to_string (set_user_email (`String "") fixture_200_json)
  in
  let expected =
    {
      (expected_session_of_fixture_json fixture_200_json) with
      Session.email = None;
    }
  in
  check_decode_session "user.email = \"\"" ~status:200 body (Ok expected)

let decode_session_200_without_a_user_email_is_none () =
  let body = Yojson.Safe.to_string (remove_user_email fixture_200_json) in
  let expected =
    {
      (expected_session_of_fixture_json fixture_200_json) with
      Session.email = None;
    }
  in
  check_decode_session "user.email removed" ~status:200 body (Ok expected)

let decode_session_200_rejects_html () =
  check_malformed ~reason:"not JSON" "<html> body with status 200" "<html>"

let decode_session_malformed_never_quotes_the_body () =
  let body = {|{"access_token":SECRET_TOKEN_TEXT}|} in
  match Gotrue.decode_session ~now:sent ~status:200 body with
  | Error e ->
      Alcotest.(check bool)
        "no body text in error_to_string" false
        (Text.contains ~sub:"SECRET" (Gotrue.error_to_string e))
  | Ok _ -> Alcotest.fail "expected Error, got Ok"

let decode_session_200_with_a_null_user_is_malformed () =
  check_malformed ~reason:"user" "user null"
    (Yojson.Safe.to_string (set_top_field "user" `Null fixture_200_json))

let decode_session_200_with_a_number_email_is_malformed () =
  check_malformed ~reason:"user.email" "user.email a number"
    (Yojson.Safe.to_string (set_user_email (`Int 3) fixture_200_json))

let decode_session_200_without_user_id_is_malformed () =
  check_malformed ~reason:"user.id" "user.id removed"
    (Yojson.Safe.to_string
       (match fixture_200_json with
       | `Assoc fields ->
           `Assoc
             (List.map
                (fun (k, v) ->
                  match (k, v) with
                  | "user", `Assoc user_fields ->
                      ( k,
                        `Assoc
                          (List.filter
                             (fun (uk, _) -> not (String.equal uk "id"))
                             user_fields) )
                  | _ -> (k, v))
                fields)
       | j -> j))

let decode_session_200_json_array_is_malformed () =
  check_malformed ~reason:"not an object" "a JSON array with status 200" "[]"

let decode_session_200_names_each_bad_field () =
  let with_top name key value =
    check_malformed ~reason:key name
      (Yojson.Safe.to_string (set_top_field key value fixture_200_json))
  in
  check_malformed ~reason:"access_token" "access_token removed"
    (Yojson.Safe.to_string (remove_top_field "access_token" fixture_200_json));
  with_top "access_token a number" "access_token" (`Int 1);
  with_top "refresh_token null" "refresh_token" `Null;
  with_top "expires_in a float" "expires_in" (`Float 3600.5);
  with_top "expires_in negative" "expires_in" (`Int (-1));
  with_top "user a string" "user" (`String "u");
  check_malformed ~reason:"user.id" "user.id a number"
    (Yojson.Safe.to_string
       (set_top_field "user" (`Assoc [("id", `Int 7)]) fixture_200_json))

(* The .mli's constructor is public: pattern-matched directly, no wildcard
   on our own [Gotrue.error]. [Rejected]'s payload is an inline record, which
   cannot escape a match as a value, hence the tuple. *)
let expect_rejected name (e : Gotrue.error) : int * string option * string =
  match e with
  | Gotrue.Rejected {status; code; message} -> (status, code, message)
  | Gotrue.Malformed m ->
      Alcotest.failf "%s: expected Rejected, got Malformed %S" name m

let decode_error name ~status body =
  match Gotrue.decode_session ~now:sent ~status body with
  | Error e -> e
  | Ok _ -> Alcotest.failf "%s: expected Error, got Ok" name

let error_not_found =
  decode_error "refresh_token_not_found fixture" ~status:400
    fixture_not_found_text

let error_invalid =
  decode_error "validation_failed fixture" ~status:400 fixture_invalid_text

let error_signup_disabled =
  decode_error "signup_disabled fixture" ~status:422
    fixture_signup_disabled_text

let error_id_token_invalid =
  decode_error "id-token invalid_request fixture" ~status:400
    fixture_id_token_invalid_text

let decode_session_refresh_token_not_found () =
  let status, code, message = expect_rejected "not_found" error_not_found in
  Alcotest.(check int) "status" 400 status;
  Alcotest.(check (option string)) "code" (Some "refresh_token_not_found") code;
  Alcotest.(check string)
    "message" "Invalid Refresh Token: Refresh Token Not Found" message

let decode_session_refresh_token_invalid () =
  let status, code, _ = expect_rejected "invalid" error_invalid in
  Alcotest.(check int) "status" 400 status;
  Alcotest.(check (option string)) "code" (Some "validation_failed") code

let decode_session_signup_disabled () =
  let status, code, _ =
    expect_rejected "signup_disabled" error_signup_disabled
  in
  Alcotest.(check int) "status" 422 status;
  Alcotest.(check (option string)) "code" (Some "signup_disabled") code;
  Alcotest.(check bool)
    "signup_disabled true on this error" true
    (Gotrue.signup_disabled error_signup_disabled);
  Alcotest.(check bool)
    "signup_disabled false on refresh_token_not_found" false
    (Gotrue.signup_disabled error_not_found);
  Alcotest.(check bool)
    "signup_disabled false on Malformed" false
    (Gotrue.signup_disabled (Gotrue.Malformed "signup_disabled"))

(* GoTrue's OAuth-style envelope, its answer when the id token itself is
   refused: [error] is the code, [error_description] the message. *)
let decode_session_id_token_oauth_envelope () =
  let status, code, message =
    expect_rejected "id-token invalid_request" error_id_token_invalid
  in
  Alcotest.(check int) "status" 400 status;
  Alcotest.(check (option string)) "code" (Some "invalid request") code;
  Alcotest.(check string) "message" "Bad ID token" message

let decode_session_502_html_is_rejected_with_the_body_as_message () =
  let status, code, message =
    expect_rejected "502 html"
      (decode_error "502 html" ~status:502 "<html>bad gateway</html>")
  in
  Alcotest.(check int) "status" 502 status;
  Alcotest.(check (option string)) "code" None code;
  Alcotest.(check string)
    "message is the raw body" "<html>bad gateway</html>" message

let decode_session_other_rejections () =
  let rejected name ~status body =
    expect_rejected name (decode_error name ~status body)
  in
  let status, code, message =
    rejected "msg without error_code" ~status:400 {|{"code":400,"msg":"x"}|}
  in
  Alcotest.(check int) "msg only: status" 400 status;
  Alcotest.(check (option string)) "msg only: code" None code;
  Alcotest.(check string) "msg only: message" "x" message;
  let _, code, message = rejected "a JSON array" ~status:400 "[]" in
  Alcotest.(check (option string)) "[]: code" None code;
  Alcotest.(check string) "[]: message is the body" "[]" message;
  let _, code, message =
    rejected "error without error_description" ~status:400 {|{"error":"x"}|}
  in
  Alcotest.(check (option string)) "error only: code" None code;
  Alcotest.(check string)
    "error only: message is the body" {|{"error":"x"}|} message

let decode_session_2xx_bounds () =
  let is_rejected status =
    match Gotrue.decode_session ~now:sent ~status fixture_200_text with
    | Error (Gotrue.Rejected _) -> true
    | Ok _ | Error (Gotrue.Malformed _) -> false
  in
  Alcotest.(check bool) "199 is rejected" true (is_rejected 199);
  Alcotest.(check bool) "299 is a session" false (is_rejected 299);
  Alcotest.(check bool) "300 is rejected" true (is_rejected 300)

let decode_empty_cases () =
  Alcotest.(check (result unit gotrue_error_t))
    "204 empty body" (Ok ())
    (Gotrue.decode_empty ~status:204 "");
  Alcotest.(check (result unit gotrue_error_t))
    "200 {}" (Ok ())
    (Gotrue.decode_empty ~status:200 "{}");
  Alcotest.(check (result unit gotrue_error_t))
    "200 non-JSON body" (Ok ())
    (Gotrue.decode_empty ~status:200 "<html>ok</html>");
  match Gotrue.decode_empty ~status:401 fixture_not_found_text with
  | Error (Gotrue.Rejected _) -> ()
  | Error (Gotrue.Malformed _) ->
      Alcotest.fail "401: expected Rejected, got Malformed"
  | Ok () -> Alcotest.fail "401: expected Error, got Ok"

let revokes_session_cases () =
  let rejected status code = Gotrue.Rejected {status; code; message = "x"} in
  Alcotest.(check bool)
    "refresh_token_not_found revokes" true
    (Gotrue.revokes_session error_not_found);
  Alcotest.(check bool)
    "validation_failed revokes" true
    (Gotrue.revokes_session error_invalid);
  Alcotest.(check bool)
    "signup_disabled revokes" true
    (Gotrue.revokes_session error_signup_disabled);
  Alcotest.(check bool)
    "the id-token OAuth envelope revokes" true
    (Gotrue.revokes_session error_id_token_invalid);
  List.iter
    (fun status ->
      Alcotest.(check bool)
        (Printf.sprintf "%d with a code revokes" status)
        true
        (Gotrue.revokes_session (rejected status (Some "c"))))
    [400; 401; 403; 404; 499];
  List.iter
    (fun status ->
      Alcotest.(check bool)
        (Printf.sprintf "%d without a code does not revoke" status)
        false
        (Gotrue.revokes_session (rejected status None)))
    [400; 401; 403; 404; 499];
  Alcotest.(check bool)
    "an HTML 403 does not revoke" false
    (Gotrue.revokes_session
       (decode_error "html 403" ~status:403 "<html>Forbidden</html>"));
  List.iter
    (fun status ->
      Alcotest.(check bool)
        (Printf.sprintf "%d does not revoke" status)
        false
        (Gotrue.revokes_session (rejected status (Some "c"))))
    [408; 429; 500; 502; 503];
  Alcotest.(check bool)
    "Malformed does not revoke" false
    (Gotrue.revokes_session (Gotrue.Malformed "x"))

let error_to_string_names_the_status_and_code () =
  let s = Gotrue.error_to_string error_not_found in
  Alcotest.(check bool) "mentions the status" true (Text.contains ~sub:"400" s);
  Alcotest.(check bool)
    "mentions the error code" true
    (Text.contains ~sub:"refresh_token_not_found" s)

let error_to_string_cases () =
  let rejected message = Gotrue.Rejected {status = 400; code = None; message} in
  Alcotest.(check string)
    "code None" "HTTP 400: x"
    (Gotrue.error_to_string (rejected "x"));
  Alcotest.(check string)
    "Malformed" "malformed session: user"
    (Gotrue.error_to_string (Gotrue.Malformed "user"));
  Alcotest.(check string)
    "newlines become spaces" "HTTP 400: a b c"
    (Gotrue.error_to_string (rejected "a\nb\rc"));
  let prefix = "HTTP 400: " in
  Alcotest.(check string)
    "200 bytes are kept whole"
    (prefix ^ String.make 200 'a')
    (Gotrue.error_to_string (rejected (String.make 200 'a')));
  Alcotest.(check string)
    "201 bytes are cut at 200"
    (prefix ^ String.make 200 'a' ^ "…")
    (Gotrue.error_to_string (rejected (String.make 201 'a')));
  let straddling = String.make 199 'a' ^ "é" ^ "zz" in
  let cut = Gotrue.error_to_string (rejected straddling) in
  Alcotest.(check bool)
    "an é at byte 200 is not split" true
    (String.is_valid_utf_8 cut);
  Alcotest.(check string)
    "the é is left out whole"
    (prefix ^ String.make 199 'a' ^ "…")
    cut

let gotrue_response_tests =
  [
    ( "decode_session of the 200 fixture matches its own fields",
      `Quick,
      decode_session_200_matches_the_fixture_s_own_fields );
    ( "decode_session: a 200 body without refresh_token is Malformed",
      `Quick,
      decode_session_200_without_refresh_token_is_malformed );
    ( "decode_session: expires_at is the device's now plus expires_in",
      `Quick,
      decode_session_200_ignores_the_answer_s_expires_at );
    ( "decode_session: now is truncated to the second",
      `Quick,
      decode_session_200_truncates_now_to_the_second );
    ( "decode_session: a 200 body with expires_in a string or 0 is Malformed",
      `Quick,
      decode_session_200_with_a_string_expires_in_is_malformed );
    ( "decode_session: a 200 body with user null is Malformed",
      `Quick,
      decode_session_200_with_a_null_user_is_malformed );
    ( "decode_session: a 200 body with user.email a number is Malformed",
      `Quick,
      decode_session_200_with_a_number_email_is_malformed );
    ( "decode_session: a Malformed error never quotes the body",
      `Quick,
      decode_session_malformed_never_quotes_the_body );
    ( "decode_session: a 200 body without user is Malformed",
      `Quick,
      decode_session_200_without_user_is_malformed );
    ( "decode_session: user.email = \"\" decodes to email None",
      `Quick,
      decode_session_200_with_an_empty_user_email_is_none );
    ( "decode_session: a missing user.email decodes to email None",
      `Quick,
      decode_session_200_without_a_user_email_is_none );
    ( "decode_session: a 200 status with an HTML body is Malformed",
      `Quick,
      decode_session_200_rejects_html );
    ( "decode_session: a 200 body without user.id is Malformed",
      `Quick,
      decode_session_200_without_user_id_is_malformed );
    ( "decode_session: a 200 JSON array is Malformed",
      `Quick,
      decode_session_200_json_array_is_malformed );
    ( "decode_session: a Malformed 200 names the bad field",
      `Quick,
      decode_session_200_names_each_bad_field );
    ( "decode_session: refresh_token_not_found is Rejected with its recorded \
       fields",
      `Quick,
      decode_session_refresh_token_not_found );
    ( "decode_session: validation_failed is Rejected with code validation_failed",
      `Quick,
      decode_session_refresh_token_invalid );
    ( "decode_session: signup_disabled is Rejected and recognised by \
       signup_disabled",
      `Quick,
      decode_session_signup_disabled );
    ( "decode_session: the id-token grant's OAuth envelope is Rejected with \
       error and error_description",
      `Quick,
      decode_session_id_token_oauth_envelope );
    ( "decode_session: a 502 HTML body is Rejected with code None and the body \
       as message",
      `Quick,
      decode_session_502_html_is_rejected_with_the_body_as_message );
    ( "decode_session: msg alone, an array, error alone",
      `Quick,
      decode_session_other_rejections );
    ("decode_session: 2xx is 200 to 299", `Quick, decode_session_2xx_bounds);
    ( "decode_empty: 204 empty, 200 {}, and a non-2xx status",
      `Quick,
      decode_empty_cases );
    ( "revokes_session: GoTrue's 4xx except 408/429 revoke, nothing else",
      `Quick,
      revokes_session_cases );
    ( "error_to_string names the status and the error code",
      `Quick,
      error_to_string_names_the_status_and_code );
    ( "error_to_string: no code, Malformed, one line, cut at 200 bytes",
      `Quick,
      error_to_string_cases );
  ]

(* ---------- Grant ---------- *)

let refreshed_to_string : Grant.refreshed -> string = function
  | Fresh s -> "Fresh " ^ s.access_token
  | Revoked e -> "Revoked " ^ Gotrue.error_to_string e
  | Failed e -> "Failed " ^ Grant.error_to_string e

let refreshed_t =
  Alcotest.testable
    (fun ppf r -> Format.pp_print_string ppf (refreshed_to_string r))
    (fun a b -> String.equal (refreshed_to_string a) (refreshed_to_string b))

let grant_refreshed_cases () =
  let check name expected answer =
    Alcotest.check refreshed_t name expected (Grant.refreshed answer)
  in
  let s = session ~expires_at:t0 () in
  check "a session is Fresh" (Fresh s) (Ok s);
  check "a revoking answer is Revoked" (Revoked error_not_found)
    (Error (Rejected error_not_found));
  check "signup_disabled is Revoked" (Revoked error_signup_disabled)
    (Error (Rejected error_signup_disabled));
  let busy = Gotrue.Rejected {status = 429; code = Some "c"; message = "x"} in
  check "a 429 is Failed, kept for a retry" (Failed (Rejected busy))
    (Error (Rejected busy));
  check "Malformed is Failed" (Failed (Rejected (Gotrue.Malformed "x")))
    (Error (Rejected (Gotrue.Malformed "x")));
  check "a network failure is Failed" (Failed (Network "down"))
    (Error (Network "down"))

let grant_error_to_string_cases () =
  Alcotest.(check string)
    "network" "network: down"
    (Grant.error_to_string (Network "down"));
  Alcotest.(check string)
    "rejected"
    (Gotrue.error_to_string error_not_found)
    (Grant.error_to_string (Rejected error_not_found))

let grant_tests =
  [
    ( "refreshed: a session, revoked by revokes_session, else Failed",
      `Quick,
      grant_refreshed_cases );
    ( "error_to_string: network prefixed, GoTrue's own",
      `Quick,
      grant_error_to_string_cases );
  ]

let () =
  Alcotest.run "sync"
    [
      ("Session", session_tests);
      ("Session: stored format (v1)", session_stored_format_tests);
      ("Nonce", nonce_tests);
      ("Gotrue requests", gotrue_request_tests);
      ("Gotrue responses", gotrue_response_tests);
      ("Grant", grant_tests);
    ]
