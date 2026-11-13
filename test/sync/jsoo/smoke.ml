(* Session's stored form under js_of_ocaml: the same recorded v1 bytes as
   test/sync/test_sync.ml, and an expiry past 2038 read back; and GoTrue's
   token answer decoded. Silent on success; the first mismatch goes to stderr
   and exits 1. *)

let fail fmt =
  Printf.ksprintf
    (fun m ->
      prerr_endline m;
      exit 1)
    fmt

let at_s secs =
  match Ptime.of_float_s secs with
  | Some t -> t
  | None -> fail "%.0f s is not a Ptime" secs

let session ?(email = Some "person@example.com") secs : Session.t =
  {
    Session.access_token = "AT-token";
    refresh_token = "RT-token";
    expires_at = at_s secs;
    user_id = "user-1";
    email;
  }

let written name expected s =
  let got = Session.to_string s in
  match String.equal got expected with
  | true -> ()
  | false -> fail "%s: wrote %s, expected %s" name got expected

let read name text expected =
  match Session.of_string text with
  | Ok s when Session.equal s expected -> ()
  | Ok s -> fail "%s: read back %s" name (Session.to_string s)
  | Error e -> fail "%s: Error %s" name e

let decoded name body expected =
  match Gotrue.decode_session ~now:(at_s 1_800_000_000.) ~status:200 body with
  | Ok s when Session.equal s expected -> ()
  | Ok s -> fail "%s: decoded %s" name (Session.to_string s)
  | Error e -> fail "%s: Error %s" name (Gotrue.error_to_string e)

let () =
  let in_2040 =
    {|{"v":1,"access_token":"AT-token","refresh_token":"RT-token","expires_at":2208988800,"user_id":"user-1","email":null}|}
  in
  written "email Some" Stored_v1.with_email (session 1_800_000_000.);
  written "email None" Stored_v1.without_email
    (session ~email:None 1_800_000_000.);
  written "2100" Stored_v1.in_2100 (session 4_102_444_800.);
  written "2040" in_2040 (session ~email:None 2_208_988_800.);
  read "email Some" Stored_v1.with_email (session 1_800_000_000.);
  read "email None" Stored_v1.without_email (session ~email:None 1_800_000_000.);
  read "2100" Stored_v1.in_2100 (session 4_102_444_800.);
  read "2040" in_2040 (session ~email:None 2_208_988_800.);
  read "keys in another order"
    {|{"email":"person@example.com","user_id":"user-1","expires_at":1800000000,"refresh_token":"RT-token","access_token":"AT-token","v":1}|}
    (session 1_800_000_000.);
  (* The answer's own expires_at, past 2038, is an `Intlit here and ignored. *)
  decoded "token answer"
    {|{"access_token":"AT-token","token_type":"bearer","expires_in":3600,"expires_at":4102444800,"refresh_token":"RT-token","user":{"id":"user-1","email":"person@example.com"}}|}
    (session 1_800_003_600.)
