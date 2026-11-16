(* Herbier_photos.Drive (app/photos/drive.mli): names, request builders,
   error classification (over recorded fixtures and hand-written bodies for
   the branches that need no token), decoders, and the [folder] /
   [put_original] / [presence] programs run over a fake network. *)

module Drive = Herbier_photos.Drive
module Ids = Herbier_domain.Ids
module Plant = Herbier_domain.Plant
module Url = Herbier_net.Url
module Fixture = Herbier_test_support.Fixture
module Value = Herbier_test_support.Value
module Text = Herbier_test_support.Text

let fixture name = Fixture.read ("drive_" ^ name ^ ".json")

(* ---------- testables ---------- *)

let error_t = Alcotest.testable Drive.pp_error Drive.equal_error
let meth_to_string = function `GET -> "GET" | `POST -> "POST"

let pp_request ppf (r : Drive.request) =
  Format.fprintf ppf "%s %s %s" (meth_to_string r.meth) r.url
    (match r.body with
    | Drive.Empty -> "(empty)"
    | Drive.Json j -> j
    | Drive.Multipart {boundary; prefix; suffix} ->
        Printf.sprintf "multipart %s %S %S" boundary prefix suffix)

let request_t = Alcotest.testable pp_request Drive.equal_request

let pp_file ppf (f : Drive.file) =
  Format.fprintf ppf "{id = %s; web_view_link = %s}" f.id
    (match f.web_view_link with
    | None -> "None"
    | Some s -> Printf.sprintf "Some %s" s)

let file_t = Alcotest.testable pp_file Drive.equal_file

let pp_put ppf = function
  | Drive.Created f -> Format.fprintf ppf "Created %a" pp_file f
  | Drive.Already_there f -> Format.fprintf ppf "Already_there %a" pp_file f

let put_t = Alcotest.testable pp_put Drive.equal_put

let pp_presence ppf = function
  | Drive.Present -> Format.pp_print_string ppf "Present"
  | Drive.Trashed -> Format.pp_print_string ppf "Trashed"
  | Drive.Missing -> Format.pp_print_string ppf "Missing"

let presence_t = Alcotest.testable pp_presence Drive.equal_presence
let string_result = Alcotest.(result string error_t)
let put_result = Alcotest.(result put_t error_t)
let presence_result = Alcotest.(result presence_t error_t)
let file_list_result = Alcotest.(result (list file_t) error_t)
let file_result = Alcotest.(result file_t error_t)

(* ---------- id and time helpers ---------- *)

let plant_id = Value.id "plant id" Ids.Plant_id.of_string (Value.uuid7 1)
let photo_id n = Value.id "photo id" Ids.Photo_id.of_string (Value.uuid7 n)
let t0 = Value.time "2026-01-01T00:00:00Z"
let sha256_hex = String.concat "" (List.init 4 (fun _ -> "0123456789abcdef"))

(* ---------- species_folder ---------- *)

let free_plant name = Plant.v ~id:plant_id ~at:t0 name

let species_folder_tests =
  [
    ( "no plant falls back to the unidentified folder",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "species_folder None" Drive.unidentified_folder
          (Drive.species_folder None) );
    ( "scientific name, trimmed, authorship dropped",
      `Quick,
      fun () ->
        let p =
          {
            (free_plant "Digitale") with
            scientific_name = Some "  Digitalis purpurea ";
            authorship = Some "L.";
          }
        in
        Alcotest.(check string)
          "species_folder" "Digitalis purpurea"
          (Drive.species_folder (Some p)) );
    ( "no scientific name falls back to the display name",
      `Quick,
      fun () ->
        let p = free_plant "Digitale" in
        Alcotest.(check string)
          "species_folder" "Digitale"
          (Drive.species_folder (Some p)) );
    ( "a blank scientific name falls back to the display name",
      `Quick,
      fun () ->
        let p = {(free_plant "Digitale") with scientific_name = Some "   "} in
        Alcotest.(check string)
          "species_folder" "Digitale"
          (Drive.species_folder (Some p)) );
    ( "both blank fall back to the unidentified folder",
      `Quick,
      fun () ->
        let p = {(free_plant "   ") with scientific_name = Some "  "} in
        Alcotest.(check string)
          "species_folder" Drive.unidentified_folder
          (Drive.species_folder (Some p)) );
  ]

(* ---------- file_name ---------- *)

let id8 =
  Value.id "photo id" Ids.Photo_id.of_string
    "0193a4b2-aaaa-7aaa-8aaa-aaaa5f3c91d2"

let file_name_tests =
  [
    ( "the device offset shifts the UTC instant, same day",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "file_name" "2026-06-14 10.32.05 5f3c91d2.jpg"
          (Drive.file_name
             ~taken_at:(Value.time "2026-06-14T08:32:05Z")
             ~offset_s:7200 ~id:id8 ~mime:"image/jpeg") );
    ( "a negative offset crosses midnight to the previous day",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "file_name" "2025-12-31 23.30.00 5f3c91d2.jpg"
          (Drive.file_name
             ~taken_at:(Value.time "2026-01-01T00:30:00Z")
             ~offset_s:(-3600) ~id:id8 ~mime:"image/jpeg") );
    ( "image/png gives .png",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "file_name" "2026-06-14 10.32.05 5f3c91d2.png"
          (Drive.file_name
             ~taken_at:(Value.time "2026-06-14T08:32:05Z")
             ~offset_s:7200 ~id:id8 ~mime:"image/png") );
    ( "image/heic gives .heic",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "file_name" "2026-06-14 10.32.05 5f3c91d2.heic"
          (Drive.file_name
             ~taken_at:(Value.time "2026-06-14T08:32:05Z")
             ~offset_s:7200 ~id:id8 ~mime:"image/heic") );
    ( "image/webp gives .webp",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "file_name" "2026-06-14 10.32.05 5f3c91d2.webp"
          (Drive.file_name
             ~taken_at:(Value.time "2026-06-14T08:32:05Z")
             ~offset_s:7200 ~id:id8 ~mime:"image/webp") );
    ( "an unknown mime gives no extension",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "file_name" "2026-06-14 10.32.05 5f3c91d2"
          (Drive.file_name
             ~taken_at:(Value.time "2026-06-14T08:32:05Z")
             ~offset_s:7200 ~id:id8 ~mime:"application/octet-stream") );
    ( "the suffix is the id's last 8 digits, not its timestamp",
      `Quick,
      fun () ->
        let other =
          Value.id "photo id" Ids.Photo_id.of_string
            "0193a4b2-aaaa-7aaa-8aaa-aaaa0e8d7c6b"
        in
        let name id =
          Drive.file_name
            ~taken_at:(Value.time "2026-06-14T08:32:05Z")
            ~offset_s:7200 ~id ~mime:"image/jpeg"
        in
        Alcotest.(check string)
          "other" "2026-06-14 10.32.05 0e8d7c6b.jpg" (name other) );
    ( "past Ptime.max the offset is dropped: the time is UTC",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "file_name" "9999-12-31 23.59.59 5f3c91d2.jpg"
          (Drive.file_name ~taken_at:Ptime.max ~offset_s:3600 ~id:id8
             ~mime:"image/jpeg") );
  ]

(* ---------- quote ---------- *)

let quote_tests =
  [
    ( "an apostrophe is escaped",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "quote" "'Herbe d\\'or'" (Drive.quote "Herbe d'or") );
    ( "a backslash is escaped",
      `Quick,
      fun () -> Alcotest.(check string) "quote" "'a\\\\b'" (Drive.quote "a\\b")
    );
    ( "plain text is just quoted",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "quote" "'Digitalis purpurea'"
          (Drive.quote "Digitalis purpurea") );
  ]

(* ---------- request builders ---------- *)

let find_folder_q =
  "name = 'Digitalis purpurea' and mimeType = \
   'application/vnd.google-apps.folder' and 'root' in parents and trashed = \
   false"

let find_original_q id =
  Printf.sprintf
    "appProperties has { key='herbier_photo_id' and value='%s' } and trashed = \
     false"
    (Ids.Photo_id.to_string id)

let list_url q fields =
  Drive.api
  ^ "?q="
  ^ Url.encode q
  ^ "&fields="
  ^ Url.encode fields
  ^ "&orderBy=createdTime&pageSize=10&spaces=drive"

(* Copied verbatim from scripts/record-drive-fixtures.sh. *)
let script_find_fixture_folder_url =
  "https://www.googleapis.com/drive/v3/files?q=name%20%3D%20%27Herbier-fixtures%27%20and%20mimeType%20%3D%20%27application%2Fvnd.google-apps.folder%27%20and%20%27root%27%20in%20parents%20and%20trashed%20%3D%20false&fields=files%28id%29&orderBy=createdTime&pageSize=10&spaces=drive"

let script_find_nil_original_url =
  "https://www.googleapis.com/drive/v3/files?q=appProperties%20has%20%7B%20key%3D%27herbier_photo_id%27%20and%20value%3D%2700000000-0000-0000-0000-000000000000%27%20%7D%20and%20trashed%20%3D%20false&fields=files%28id%2CwebViewLink%29&orderBy=createdTime&pageSize=10&spaces=drive"

let request_builder_tests =
  [
    ( "find_folder renders the exact URL record-drive-fixtures.sh curls",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url" script_find_fixture_folder_url
          (Drive.find_folder ~name:"Herbier-fixtures" ~parent:Drive.Root).url );
    ( "find_original renders the exact URL record-drive-fixtures.sh curls",
      `Quick,
      fun () ->
        let nil =
          Value.id "nil id" Ids.Photo_id.of_string
            "00000000-0000-0000-0000-000000000000"
        in
        Alcotest.(check string)
          "url" script_find_nil_original_url (Drive.find_original ~id:nil).url
    );
    ( "find_folder: GET, q and fields percent-encoded, no body",
      `Quick,
      fun () ->
        let r =
          Drive.find_folder ~name:"Digitalis purpurea" ~parent:Drive.Root
        in
        Alcotest.(check string)
          "meth" "GET"
          (match r.meth with `GET -> "GET" | `POST -> "POST");
        (match r.body with
        | Drive.Empty -> ()
        | _ -> Alcotest.fail "find_folder body is not Empty");
        Alcotest.(check string) "url" (list_url find_folder_q "files(id)") r.url;
        Alcotest.(check (option string))
          "content_type" None
          (Drive.content_type r.body) );
    ( "find_folder under a folder names that folder's id",
      `Quick,
      fun () ->
        let r = Drive.find_folder ~name:"x" ~parent:(Drive.Folder "P1") in
        match Text.contains ~sub:"%27P1%27%20in%20parents" r.url with
        | true -> ()
        | false -> Alcotest.failf "parent id not found in %s" r.url );
    ( "an apostrophe in the name is escaped then percent-encoded",
      `Quick,
      fun () ->
        let r = Drive.find_folder ~name:"Herbe d'or" ~parent:Drive.Root in
        match Text.contains ~sub:"%27Herbe%20d%5C%27or%27" r.url with
        | true -> ()
        | false -> Alcotest.failf "escaped apostrophe not found in %s" r.url );
    ( "create_folder posts the folder's JSON body",
      `Quick,
      fun () ->
        let r =
          Drive.create_folder ~name:"Digitalis purpurea" ~parent:Drive.Root
        in
        Alcotest.(check string)
          "meth" "POST"
          (match r.meth with `GET -> "GET" | `POST -> "POST");
        Alcotest.(check string) "url" (Drive.api ^ "?fields=id") r.url;
        (match r.body with
        | Drive.Json s ->
            Alcotest.(check Herbier_test_support.Testable.yojson)
              "body"
              (`Assoc
                 [
                   ("name", `String "Digitalis purpurea");
                   ("mimeType", `String "application/vnd.google-apps.folder");
                   ("parents", `List [`String "root"]);
                 ])
              (Yojson.Safe.from_string s)
        | _ -> Alcotest.fail "create_folder body is not Json");
        Alcotest.(check (option string))
          "content_type" (Some "application/json; charset=UTF-8")
          (Drive.content_type r.body) );
    ( "find_original's q names the appProperties pair",
      `Quick,
      fun () ->
        let id = photo_id 2 in
        let r = Drive.find_original ~id in
        Alcotest.(check string)
          "meth" "GET"
          (match r.meth with `GET -> "GET" | `POST -> "POST");
        Alcotest.(check string)
          "url"
          (list_url (find_original_q id) "files(id,webViewLink)")
          r.url );
    ( "get_trashed renders the file id in the path",
      `Quick,
      fun () ->
        let r = Drive.get_trashed ~file_id:"abc" in
        Alcotest.(check string)
          "url"
          (Drive.api ^ "/abc?fields=id,trashed")
          r.url );
    ( "a file id with a slash is percent-encoded in the path",
      `Quick,
      fun () ->
        let r = Drive.get_trashed ~file_id:"a/b" in
        Alcotest.(check string)
          "url"
          (Drive.api ^ "/a%2Fb?fields=id,trashed")
          r.url );
  ]

(* ---------- metadata_json and boundary ---------- *)

let metadata : Drive.metadata =
  {
    name = "2026-06-14 10.32.05 5f3c91d2.jpg";
    mime = "image/jpeg";
    folder_id = "FOLDER1";
    photo_id = photo_id 3;
    sha256 = sha256_hex;
  }

let metadata_tests =
  [
    ( "metadata_json is the exact object Drive sends",
      `Quick,
      fun () ->
        Alcotest.(check Herbier_test_support.Testable.yojson)
          "metadata_json"
          (`Assoc
             [
               ("name", `String metadata.name);
               ("mimeType", `String metadata.mime);
               ("parents", `List [`String metadata.folder_id]);
               ( "appProperties",
                 `Assoc
                   [
                     ( "herbier_photo_id",
                       `String (Ids.Photo_id.to_string metadata.photo_id) );
                     ("sha256", `String metadata.sha256);
                   ] );
             ])
          (Drive.metadata_json metadata) );
    ( "every appProperties pair stays under Drive's 124-byte limit",
      `Quick,
      fun () ->
        match Drive.metadata_json metadata with
        | `Assoc fields -> (
            match List.assoc_opt "appProperties" fields with
            | Some (`Assoc pairs) ->
                List.iter
                  (fun (k, v) ->
                    match v with
                    | `String s ->
                        Alcotest.(check bool)
                          (k ^ " fits in 124 bytes") true
                          (String.length k + String.length s <= 124)
                    | _ -> Alcotest.fail "appProperties value not a string")
                  pairs
            | _ -> Alcotest.fail "no appProperties object")
        | _ -> Alcotest.fail "metadata_json not an object" );
    ( "boundary is herbier- followed by the random bytes' lowercase hex",
      `Quick,
      fun () ->
        let random = String.init 16 (fun i -> Char.chr i) in
        let b = Drive.boundary ~random in
        Alcotest.(check string)
          "boundary" "herbier-000102030405060708090a0b0c0d0e0f" b;
        Alcotest.(check int) "length" 40 (String.length b) );
  ]

(* ---------- create_original ---------- *)

let create_original_tests =
  [
    ( "create_original: URL, Multipart body, content_type, prefix and suffix",
      `Quick,
      fun () ->
        let boundary = "herbier-000102030405060708090a0b0c0d0e0f" in
        let r = Drive.create_original metadata ~boundary in
        Alcotest.(check string)
          "meth" "POST"
          (match r.meth with `GET -> "GET" | `POST -> "POST");
        Alcotest.(check string)
          "url"
          (Drive.upload_api ^ "?uploadType=multipart&fields=id,webViewLink")
          r.url;
        (match r.body with
        | Drive.Multipart {boundary = b; prefix; suffix} -> (
            Alcotest.(check string) "boundary" boundary b;
            Alcotest.(check string)
              "prefix"
              ("--"
              ^ boundary
              ^ "\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"
              ^ Yojson.Safe.to_string (Drive.metadata_json metadata)
              ^ "\r\n--"
              ^ boundary
              ^ "\r\nContent-Type: image/jpeg\r\n\r\n")
              prefix;
            Alcotest.(check string)
              "suffix"
              ("\r\n--" ^ boundary ^ "--\r\n")
              suffix;
            match
              Text.contains ~sub:boundary
                (Yojson.Safe.to_string (Drive.metadata_json metadata))
            with
            | false -> ()
            | true -> Alcotest.fail "boundary occurs in the metadata JSON")
        | _ -> Alcotest.fail "create_original body is not Multipart");
        Alcotest.(check (option string))
          "content_type"
          (Some ("multipart/related; boundary=" ^ boundary))
          (Drive.content_type r.body) );
    ( "a mime with a CRLF becomes application/octet-stream in the prefix",
      `Quick,
      fun () ->
        let m = {metadata with mime = "image/jpeg\r\nX-Injected: 1"} in
        let r = Drive.create_original m ~boundary:"herbier-abc" in
        match r.body with
        | Drive.Multipart {prefix; _} ->
            Alcotest.(check bool)
              "media part header" true
              (String.ends_with
                 ~suffix:
                   "\r\n\
                    --herbier-abc\r\n\
                    Content-Type: application/octet-stream\r\n\
                    \r\n"
                 prefix)
        | _ -> Alcotest.fail "create_original body is not Multipart" );
    ( "media_type keeps type/subtype, replaces anything else",
      `Quick,
      fun () ->
        List.iter
          (fun (mime, expected) ->
            Alcotest.(check string) mime expected (Drive.media_type mime))
          [
            ("image/jpeg", "image/jpeg");
            ("image/vnd.ms-photo", "image/vnd.ms-photo");
            ("", "application/octet-stream");
            ("image", "application/octet-stream");
            ("image/", "application/octet-stream");
            ("image/jpeg; q=1", "application/octet-stream");
            ("image/jpeg\r\nX: 1", "application/octet-stream");
            ("a/b/c", "application/octet-stream");
          ] );
    ( "an accented name stays UTF-8 bytes in the prefix",
      `Quick,
      fun () ->
        let m = {metadata with name = Drive.unidentified_folder} in
        let r = Drive.create_original m ~boundary:"herbier-abc" in
        match r.body with
        | Drive.Multipart {prefix; _} -> (
            match Text.contains ~sub:"À identifier" prefix with
            | true -> ()
            | false -> Alcotest.fail "accented name not verbatim in prefix")
        | _ -> Alcotest.fail "create_original body is not Multipart" );
  ]

(* ---------- error_of_answer ---------- *)

let error_of_answer_fixture_tests =
  [
    ( "a 401 on files.get (invalid token) is Unauthorized",
      `Quick,
      fun () ->
        Alcotest.check error_t "error" Drive.Unauthorized
          (Drive.error_of_answer ~status:401
             ~body:(fixture "files_get_invalid_token_401")) );
    ( "a 401 on files.create (invalid token) is Unauthorized",
      `Quick,
      fun () ->
        Alcotest.check error_t "error" Drive.Unauthorized
          (Drive.error_of_answer ~status:401
             ~body:(fixture "files_create_invalid_token_401")) );
    ( "a 403 with no Authorization header is Http forbidden",
      `Quick,
      fun () ->
        Alcotest.check error_t "error"
          (Drive.Http
             {
               status = 403;
               reason = Some "forbidden";
               message = Some "Permission denied on the service.";
             })
          (Drive.error_of_answer ~status:403
             ~body:(fixture "files_get_no_token_403")) );
  ]

let error_of_answer_handwritten_tests =
  let reason_body reason =
    Printf.sprintf {|{"error":{"code":403,"errors":[{"reason":"%s"}]}}|} reason
  in
  let case name status body expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check error_t "error" expected
          (Drive.error_of_answer ~status ~body) )
  in
  [
    case "429 is Rate_limited" 429 "{}" Drive.Rate_limited;
    case "403 userRateLimitExceeded is Rate_limited" 403
      (reason_body "userRateLimitExceeded")
      Drive.Rate_limited;
    case "403 rateLimitExceeded is Rate_limited" 403
      (reason_body "rateLimitExceeded")
      Drive.Rate_limited;
    case "403 storageQuotaExceeded is Quota_full" 403
      (reason_body "storageQuotaExceeded")
      Drive.Quota_full;
    case "403 insufficientPermissions is Scope_missing" 403
      (reason_body "insufficientPermissions")
      Drive.Scope_missing;
    (* errors[0].reason matches no named reason: only the details fallback
       can classify it. *)
    case "403 with an ErrorInfo SERVICE_DISABLED detail is Api_disabled" 403
      {|{"error":{"code":403,"errors":[{"reason":"forbidden"}],"details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"SERVICE_DISABLED"}]}}|}
      Drive.Api_disabled;
    case
      "403 with an ErrorInfo ACCESS_TOKEN_SCOPE_INSUFFICIENT detail is \
       Scope_missing"
      403
      {|{"error":{"code":403,"errors":[{"reason":"forbidden"}],"details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"ACCESS_TOKEN_SCOPE_INSUFFICIENT"}]}}|}
      Drive.Scope_missing;
    case "403 accessNotConfigured is Api_disabled" 403
      (reason_body "accessNotConfigured")
      Drive.Api_disabled;
    case "404 is Not_found" 404 "{}" Drive.Not_found;
    case "500, the lowest server status, is Server 500" 500 "{}"
      (Drive.Server 500);
    case "599, the highest server status, is Server 599" 599 "{}"
      (Drive.Server 599);
    case "600 is past the server range: Http" 600 "{}"
      (Drive.Http {status = 600; reason = None; message = None});
    case "503 with an HTML body is Server 503" 503
      "<html><body>Service Unavailable</body></html>" (Drive.Server 503);
    case "418 with a non-JSON body is Http with no reason or message" 418
      "not json"
      (Drive.Http {status = 418; reason = None; message = None});
    case "a non-string reason and a null message are None" 403
      {|{"error":{"code":403,"errors":[{"reason":5}],"message":null}}|}
      (Drive.Http {status = 403; reason = None; message = None});
    case "a numeric message is None" 418 {|{"error":{"message":7}}|}
      (Drive.Http {status = 418; reason = None; message = None});
  ]

let error_to_string_tests =
  let case expected e =
    ( expected,
      `Quick,
      fun () ->
        Alcotest.(check string)
          "error_to_string" expected (Drive.error_to_string e) )
  in
  [
    case "HTTP 418 r: m"
      (Drive.Http {status = 418; reason = Some "r"; message = Some "m"});
    case "HTTP 418 r"
      (Drive.Http {status = 418; reason = Some "r"; message = None});
    case "HTTP 418: m"
      (Drive.Http {status = 418; reason = None; message = Some "m"});
    case "HTTP 418" (Drive.Http {status = 418; reason = None; message = None});
    case "server error HTTP 503" (Drive.Server 503);
    case "network: timeout" (Drive.Network "timeout");
    case "malformed answer: id" (Drive.Malformed "id");
  ]

(* ---------- error_scope ---------- *)

let pp_scope ppf = function
  | Drive.Account -> Format.pp_print_string ppf "Account"
  | Drive.This_file -> Format.pp_print_string ppf "This_file"

let scope_t = Alcotest.testable pp_scope Drive.equal_scope

(* see test_drive_root.ml for resolve_root *)
let root_change_t =
  Alcotest.testable Drive.pp_root_change Drive.equal_root_change

let error_scope_tests =
  let case name e expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check scope_t "error_scope" expected (Drive.error_scope e) )
  in
  [
    case "Unauthorized: Account" Drive.Unauthorized Drive.Account;
    case "Api_disabled: Account" Drive.Api_disabled Drive.Account;
    case "Scope_missing: Account" Drive.Scope_missing Drive.Account;
    case "Quota_full: Account" Drive.Quota_full Drive.Account;
    case "Rate_limited: Account" Drive.Rate_limited Drive.Account;
    case "Server _: Account" (Drive.Server 503) Drive.Account;
    case "Network _: Account" (Drive.Network "timeout") Drive.Account;
    case "Not_found: This_file" Drive.Not_found Drive.This_file;
    case "Http _: This_file"
      (Drive.Http {status = 418; reason = None; message = None})
      Drive.This_file;
    case "Malformed _: This_file" (Drive.Malformed "x") Drive.This_file;
    case "Root_folder _: Account" (Drive.Root_folder (Drive.Malformed "x"))
      Drive.Account;
  ]

(* ---------- decoders ---------- *)

let decode_files_tests =
  [
    ( "an empty files array decodes to the empty list",
      `Quick,
      fun () ->
        Alcotest.check file_list_result "decode_files" (Ok [])
          (Drive.decode_files {|{"files":[]}|}) );
    ( "two entries decode in order, webViewLink optional",
      `Quick,
      fun () ->
        Alcotest.check file_list_result "decode_files"
          (Ok
             [
               {Drive.id = "A"; web_view_link = Some "https://x.test/a"};
               {Drive.id = "B"; web_view_link = None};
             ])
          (Drive.decode_files
             {|{"files":[{"id":"A","webViewLink":"https://x.test/a"},{"id":"B"}]}|})
    );
    ( "an entry without an id is Malformed",
      `Quick,
      fun () ->
        Alcotest.check file_list_result "decode_files"
          (Error (Drive.Malformed "files[].id"))
          (Drive.decode_files {|{"files":[{"foo":1}]}|}) );
    ( "a missing files key is Malformed \"files\"",
      `Quick,
      fun () ->
        Alcotest.check file_list_result "decode_files"
          (Error (Drive.Malformed "files")) (Drive.decode_files "{}") );
    ( "unparsable JSON is Malformed \"not JSON\"",
      `Quick,
      fun () ->
        Alcotest.check file_list_result "decode_files"
          (Error (Drive.Malformed "not JSON")) (Drive.decode_files "{") );
    ( "a files value that is not a list is Malformed \"files\"",
      `Quick,
      fun () ->
        Alcotest.check file_list_result "decode_files"
          (Error (Drive.Malformed "files"))
          (Drive.decode_files {|{"files":{}}|}) );
  ]

let decode_file_tests =
  [
    ( "id and webViewLink both decode",
      `Quick,
      fun () ->
        Alcotest.check file_result "decode_file"
          (Ok {Drive.id = "x"; web_view_link = Some "https://x.test/f"})
          (Drive.decode_file {|{"id":"x","webViewLink":"https://x.test/f"}|}) );
    ( "a missing webViewLink is None",
      `Quick,
      fun () ->
        Alcotest.check file_result "decode_file"
          (Ok {Drive.id = "x"; web_view_link = None})
          (Drive.decode_file {|{"id":"x"}|}) );
    ( "a non-string id is Malformed \"id\"",
      `Quick,
      fun () ->
        Alcotest.check file_result "decode_file" (Error (Drive.Malformed "id"))
          (Drive.decode_file {|{"id":3}|}) );
    ( "a missing id is Malformed \"id\"",
      `Quick,
      fun () ->
        Alcotest.check file_result "decode_file" (Error (Drive.Malformed "id"))
          (Drive.decode_file "{}") );
    ( "unparsable JSON is Malformed \"not JSON\"",
      `Quick,
      fun () ->
        Alcotest.check file_result "decode_file"
          (Error (Drive.Malformed "not JSON")) (Drive.decode_file "{") );
  ]

(* ---------- programs, over a fake sequential network ---------- *)

(* Each program sends its requests one after another, deterministically: a
   plain queue of canned answers, consumed in order, pins that order without
   needing to key answers by URL (two create_folder calls share the same
   URL: the folder name is in the JSON body, not the query). *)
let seq_net (responses : Drive.response list) : Drive.request -> Drive.response
    =
  let remaining = ref responses in
  fun (_ : Drive.request) ->
    match !remaining with
    | [] -> Alcotest.fail "seq_net: no more responses recorded"
    | r :: rest ->
        remaining := rest;
        r

let answer ?(status = 200) ?(headers = []) body : Drive.response =
  Drive.Answer {status; headers; body}

let check_requests msg expected reqs =
  Alcotest.(check (list request_t)) msg expected reqs

let parent9 = Drive.Folder "PARENT9"

let folder_tests =
  [
    ( "found: one request, the oldest (first) entry wins",
      `Quick,
      fun () ->
        let prog = Drive.folder ~name:"Digitalis purpurea" ~parent:parent9 in
        let resp = answer {|{"files":[{"id":"F1"},{"id":"F2"}]}|} in
        check_requests "find"
          [Drive.find_folder ~name:"Digitalis purpurea" ~parent:parent9]
          (Drive.requests (seq_net [resp]) prog);
        Alcotest.check string_result "folder" (Ok "F1")
          (Drive.run (seq_net [resp]) prog) );
    ( "absent: find then create under the same parent, the created id wins",
      `Quick,
      fun () ->
        let prog = Drive.folder ~name:"Digitalis purpurea" ~parent:parent9 in
        let responses = [answer {|{"files":[]}|}; answer {|{"id":"NEW"}|}] in
        check_requests "find, create"
          [
            Drive.find_folder ~name:"Digitalis purpurea" ~parent:parent9;
            Drive.create_folder ~name:"Digitalis purpurea" ~parent:parent9;
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check string_result "folder" (Ok "NEW")
          (Drive.run (seq_net responses) prog) );
  ]

let original : Drive.original =
  {
    target =
      {
        species = "Digitalis purpurea";
        name = "2026-06-14 10.32.05 5f3c91d2.jpg";
        mime = "image/jpeg";
        photo_id = photo_id 4;
        sha256 = sha256_hex;
      };
    boundary = "herbier-000102030405060708090a0b0c0d0e0f";
  }

let created id link = Drive.Created {Drive.id; web_view_link = Some link}

let upload_into folder_id =
  Drive.create_original
    {
      name = original.target.name;
      mime = original.target.mime;
      folder_id;
      photo_id = original.target.photo_id;
      sha256 = original.target.sha256;
    }
    ~boundary:original.boundary

let put_original_tests =
  [
    ( "nothing in Drive: find_original, find+create root, find+create species, \
       create_original; parents is the species folder",
      `Quick,
      fun () ->
        let prog = Drive.put_original ~root:None original in
        let responses =
          [
            answer {|{"files":[]}|};
            answer {|{"files":[]}|};
            answer {|{"id":"ROOT1"}|};
            answer {|{"files":[]}|};
            answer {|{"id":"SPEC1"}|};
            answer {|{"id":"FILE1","webViewLink":"https://drive.test/FILE1"}|};
          ]
        in
        check_requests "the six requests"
          [
            Drive.find_original ~id:original.target.photo_id;
            Drive.find_folder ~name:Drive.root_folder ~parent:Drive.Root;
            Drive.create_folder ~name:Drive.root_folder ~parent:Drive.Root;
            Drive.find_folder ~name:original.target.species
              ~parent:(Drive.Folder "ROOT1");
            Drive.create_folder ~name:original.target.species
              ~parent:(Drive.Folder "ROOT1");
            upload_into "SPEC1";
          ]
          (Drive.requests (seq_net responses) prog);
        let r = Drive.run (seq_net responses) prog in
        Alcotest.check put_result "put_original"
          (Ok (created "FILE1" "https://drive.test/FILE1"))
          r.result;
        Alcotest.check root_change_t "put_original root" (Drive.Store "ROOT1")
          r.root );
    ( "root and species already exist: find_original, find root, find species, \
       create_original",
      `Quick,
      fun () ->
        let prog = Drive.put_original ~root:None original in
        let responses =
          [
            answer {|{"files":[]}|};
            answer {|{"files":[{"id":"ROOT1"}]}|};
            answer {|{"files":[{"id":"SPEC1"}]}|};
            answer {|{"id":"FILE2","webViewLink":"https://drive.test/FILE2"}|};
          ]
        in
        check_requests "the four requests"
          [
            Drive.find_original ~id:original.target.photo_id;
            Drive.find_folder ~name:Drive.root_folder ~parent:Drive.Root;
            Drive.find_folder ~name:original.target.species
              ~parent:(Drive.Folder "ROOT1");
            upload_into "SPEC1";
          ]
          (Drive.requests (seq_net responses) prog);
        let r = Drive.run (seq_net responses) prog in
        Alcotest.check put_result "put_original"
          (Ok (created "FILE2" "https://drive.test/FILE2"))
          r.result;
        Alcotest.check root_change_t "put_original root" (Drive.Store "ROOT1")
          r.root );
    ( "already there: a single find_original, the oldest entry, nothing uploaded",
      `Quick,
      fun () ->
        let prog = Drive.put_original ~root:None original in
        let responses =
          [
            answer
              {|{"files":[{"id":"FILE0","webViewLink":"https://drive.test/FILE0"},{"id":"FILE9","webViewLink":"https://drive.test/FILE9"}]}|};
          ]
        in
        let reqs = Drive.requests (seq_net responses) prog in
        Alcotest.(check int) "one request" 1 (List.length reqs);
        let r = Drive.run (seq_net responses) prog in
        Alcotest.check put_result "put_original"
          (Ok
             (Drive.Already_there
                {id = "FILE0"; web_view_link = Some "https://drive.test/FILE0"}))
          r.result;
        Alcotest.check root_change_t "put_original root" Drive.Keep r.root );
    ( "a 401 finding root stops the program at once",
      `Quick,
      fun () ->
        let prog = Drive.put_original ~root:None original in
        let responses =
          [
            answer {|{"files":[]}|};
            answer ~status:401 (fixture "files_get_invalid_token_401");
          ]
        in
        let reqs = Drive.requests (seq_net responses) prog in
        Alcotest.(check int) "stops after two requests" 2 (List.length reqs);
        let r = Drive.run (seq_net responses) prog in
        Alcotest.check put_result "put_original" (Error Drive.Unauthorized)
          r.result;
        Alcotest.check root_change_t "put_original root" Drive.Keep r.root );
    ( "an unreachable create_original surfaces as Network",
      `Quick,
      fun () ->
        let prog = Drive.put_original ~root:None original in
        let responses =
          [
            answer {|{"files":[]}|};
            answer {|{"files":[]}|};
            answer {|{"id":"ROOT1"}|};
            answer {|{"files":[]}|};
            answer {|{"id":"SPEC1"}|};
            Drive.Unreachable "timeout";
          ]
        in
        let reqs = Drive.requests (seq_net responses) prog in
        Alcotest.(check int) "six requests" 6 (List.length reqs);
        let r = Drive.run (seq_net responses) prog in
        Alcotest.check put_result "put_original"
          (Error (Drive.Network "timeout")) r.result;
        Alcotest.check root_change_t
          "put_original root: the root created before the failure is still \
           stored"
          (Drive.Store "ROOT1") r.root );
    ( "a malformed create_folder answer stops before the upload",
      `Quick,
      fun () ->
        let prog = Drive.put_original ~root:None original in
        let responses =
          [answer {|{"files":[]}|}; answer {|{"files":[]}|}; answer "{}"]
        in
        let reqs = Drive.requests (seq_net responses) prog in
        Alcotest.(check int) "stops after three requests" 3 (List.length reqs);
        let r = Drive.run (seq_net responses) prog in
        Alcotest.check put_result "put_original"
          (Error (Drive.Root_folder (Drive.Malformed "id"))) r.result;
        Alcotest.check root_change_t "put_original root" Drive.Keep r.root );
  ]

let presence_tests =
  let case name resp expected =
    ( name,
      `Quick,
      fun () ->
        let prog = Drive.presence ~file_id:"abc" in
        Alcotest.check presence_result "presence" expected
          (Drive.run (seq_net [resp]) prog) )
  in
  [
    case "trashed = false is Present"
      (answer {|{"id":"x","trashed":false}|})
      (Ok Drive.Present);
    case "trashed = true is Trashed"
      (answer {|{"id":"x","trashed":true}|})
      (Ok Drive.Trashed);
    case "a 404 is Missing" (answer ~status:404 "{}") (Ok Drive.Missing);
    case "a 401 is Unauthorized"
      (answer ~status:401 (fixture "files_get_invalid_token_401"))
      (Error Drive.Unauthorized);
    case "an unreachable network is Network" (Drive.Unreachable "timeout")
      (Error (Drive.Network "timeout"));
    case "a 403 is classified, not Missing"
      (answer ~status:403 (fixture "files_get_no_token_403"))
      (Error
         (Drive.Http
            {
              status = 403;
              reason = Some "forbidden";
              message = Some "Permission denied on the service.";
            }));
    case "a missing trashed field is Malformed \"trashed\""
      (answer {|{"id":"x"}|}) (Error (Drive.Malformed "trashed"));
    case "a non-bool trashed is Malformed \"trashed\""
      (answer {|{"id":"x","trashed":"no"}|})
      (Error (Drive.Malformed "trashed"));
    case "a non-JSON 2xx is Malformed \"not JSON\"" (answer "<html>")
      (Error (Drive.Malformed "not JSON"));
  ]

(* ---------- get_folder, decode_folder, folder_info ---------- *)

let get_folder_tests =
  [
    ( "get_folder renders the exact files.get URL",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url"
          (Drive.api ^ "/F1?fields=id,name,mimeType,trashed")
          (Drive.get_folder ~file_id:"F1").url );
    ( "a file id with a space and a slash is percent-encoded",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url"
          (Drive.api ^ "/a%20b%2Fc?fields=id,name,mimeType,trashed")
          (Drive.get_folder ~file_id:"a b/c").url );
    ( "get_folder: GET, no body",
      `Quick,
      fun () ->
        let r = Drive.get_folder ~file_id:"F1" in
        Alcotest.(check string)
          "meth" "GET"
          (match r.meth with `GET -> "GET" | `POST -> "POST");
        match r.body with
        | Drive.Empty -> ()
        | _ -> Alcotest.fail "get_folder body is not Empty" );
  ]

let pp_folder_info ppf = function
  | Drive.Usable {id; name} ->
      Format.fprintf ppf "Usable {id = %S; name = %S}" id name
  | Drive.Not_a_folder -> Format.pp_print_string ppf "Not_a_folder"
  | Drive.Folder_trashed -> Format.pp_print_string ppf "Folder_trashed"
  | Drive.No_access -> Format.pp_print_string ppf "No_access"

let folder_info_t = Alcotest.testable pp_folder_info Drive.equal_folder_info
let folder_info_result = Alcotest.(result folder_info_t error_t)

let folder_meta ?(trashed = false) ~id ~name ~mime () =
  Printf.sprintf {|{"id":"%s","name":"%s","mimeType":"%s","trashed":%b}|} id
    name mime trashed

let decode_folder_tests =
  [
    ( "a folder, not trashed: Usable {id; name}",
      `Quick,
      fun () ->
        Alcotest.check folder_info_result "decode_folder"
          (Ok (Drive.Usable {id = "F1"; name = "Mes plantes"}))
          (Drive.decode_folder
             (folder_meta ~id:"F1" ~name:"Mes plantes" ~mime:Drive.folder_mime
                ())) );
    ( "a non-folder mime: Not_a_folder",
      `Quick,
      fun () ->
        Alcotest.check folder_info_result "decode_folder"
          (Ok Drive.Not_a_folder)
          (Drive.decode_folder
             (folder_meta ~id:"F1" ~name:"x.jpg" ~mime:"image/jpeg" ())) );
    ( "a non-folder mime that is also trashed: Not_a_folder, checked first",
      `Quick,
      fun () ->
        Alcotest.check folder_info_result "decode_folder"
          (Ok Drive.Not_a_folder)
          (Drive.decode_folder
             (folder_meta ~trashed:true ~id:"F1" ~name:"x.jpg"
                ~mime:"image/jpeg" ())) );
    ( "a folder, trashed: Folder_trashed",
      `Quick,
      fun () ->
        Alcotest.check folder_info_result "decode_folder"
          (Ok Drive.Folder_trashed)
          (Drive.decode_folder
             (folder_meta ~trashed:true ~id:"F1" ~name:"Mes plantes"
                ~mime:Drive.folder_mime ())) );
    ( "a missing name is Malformed \"name\"",
      `Quick,
      fun () ->
        Alcotest.check folder_info_result "decode_folder"
          (Error (Drive.Malformed "name"))
          (Drive.decode_folder
             (Printf.sprintf {|{"id":"F1","mimeType":"%s","trashed":false}|}
                Drive.folder_mime)) );
    ( "a missing id is Malformed \"id\"",
      `Quick,
      fun () ->
        Alcotest.check folder_info_result "decode_folder"
          (Error (Drive.Malformed "id"))
          (Drive.decode_folder
             (Printf.sprintf
                {|{"name":"Mes plantes","mimeType":"%s","trashed":false}|}
                Drive.folder_mime)) );
    ( "a missing mimeType is Malformed \"mimeType\"",
      `Quick,
      fun () ->
        Alcotest.check folder_info_result "decode_folder"
          (Error (Drive.Malformed "mimeType"))
          (Drive.decode_folder
             {|{"id":"F1","name":"Mes plantes","trashed":false}|}) );
    ( "a non-bool trashed is Malformed \"trashed\"",
      `Quick,
      fun () ->
        Alcotest.check folder_info_result "decode_folder"
          (Error (Drive.Malformed "trashed"))
          (Drive.decode_folder
             (Printf.sprintf
                {|{"id":"F1","name":"Mes plantes","mimeType":"%s","trashed":"no"}|}
                Drive.folder_mime)) );
    ( "\"<html>\" is Malformed \"not JSON\"",
      `Quick,
      fun () ->
        Alcotest.check folder_info_result "decode_folder"
          (Error (Drive.Malformed "not JSON"))
          (Drive.decode_folder "<html>") );
  ]

let folder_info_program_tests =
  [
    ( "404 is Ok No_access, exactly one request (get_folder)",
      `Quick,
      fun () ->
        let prog = Drive.folder_info ~file_id:"F1" in
        let resp = answer ~status:404 "{}" in
        Alcotest.(check (list request_t))
          "get_folder alone"
          [Drive.get_folder ~file_id:"F1"]
          (Drive.requests (seq_net [resp]) prog);
        Alcotest.check folder_info_result "folder_info" (Ok Drive.No_access)
          (Drive.run (seq_net [resp]) prog) );
    ( "403 appNotAuthorizedToFile is Ok No_access",
      `Quick,
      fun () ->
        let prog = Drive.folder_info ~file_id:"F1" in
        let body =
          {|{"error":{"code":403,"message":"m","errors":[{"reason":"appNotAuthorizedToFile"}]}}|}
        in
        Alcotest.check folder_info_result "folder_info" (Ok Drive.No_access)
          (Drive.run (seq_net [answer ~status:403 body]) prog) );
    ( "401 is Error Unauthorized (recorded fixture)",
      `Quick,
      fun () ->
        let prog = Drive.folder_info ~file_id:"F1" in
        Alcotest.check folder_info_result "folder_info"
          (Error Drive.Unauthorized)
          (Drive.run
             (seq_net
                [
                  answer ~status:401
                    (fixture "files_get_folder_meta_invalid_token_401");
                ])
             prog) );
    ( "403 accessNotConfigured is Error Api_disabled",
      `Quick,
      fun () ->
        let prog = Drive.folder_info ~file_id:"F1" in
        let body =
          {|{"error":{"code":403,"errors":[{"reason":"accessNotConfigured"}]}}|}
        in
        Alcotest.check folder_info_result "folder_info"
          (Error Drive.Api_disabled)
          (Drive.run (seq_net [answer ~status:403 body]) prog) );
    ( "an unreachable network is Error (Network m)",
      `Quick,
      fun () ->
        let prog = Drive.folder_info ~file_id:"F1" in
        Alcotest.check folder_info_result "folder_info"
          (Error (Drive.Network "x"))
          (Drive.run (seq_net [Drive.Unreachable "x"]) prog) );
    ( "403 insufficientFilePermissions stays Error (Http 403), not No_access",
      `Quick,
      fun () ->
        let prog = Drive.folder_info ~file_id:"F1" in
        let body =
          {|{"error":{"code":403,"message":"m","errors":[{"reason":"insufficientFilePermissions"}]}}|}
        in
        Alcotest.check folder_info_result "folder_info"
          (Error
             (Drive.Http
                {
                  status = 403;
                  reason = Some "insufficientFilePermissions";
                  message = Some "m";
                }))
          (Drive.run (seq_net [answer ~status:403 body]) prog) );
    ( "403 with no token (recorded fixture) stays Error (Http 403)",
      `Quick,
      fun () ->
        let prog = Drive.folder_info ~file_id:"F1" in
        match
          Drive.run
            (seq_net [answer ~status:403 (fixture "files_get_no_token_403")])
            prog
        with
        | Error (Drive.Http {status = 403; _}) -> ()
        | r ->
            Alcotest.failf "expected Error (Http 403), got %a"
              (Alcotest.pp folder_info_result)
              r );
  ]

(* ---------- create_session ---------- *)

(* The nil UUID and zero sha256, as scripts/record-drive-fixtures.sh's own
   [multipart] helper builds its metadata (the fixtures below were curled
   the same way). *)
let nil_photo_id =
  Value.id "nil id" Ids.Photo_id.of_string
    "00000000-0000-0000-0000-000000000000"

let nil_metadata : Drive.metadata =
  {
    name = "fixture.jpg";
    mime = "image/jpeg";
    folder_id = "root";
    photo_id = nil_photo_id;
    sha256 = String.make 64 '0';
  }

let create_session_tests =
  [
    ( "create_session: POST, the exact resumable URL, metadata_json compact as \
       the Json body, JSON content_type",
      `Quick,
      fun () ->
        let r = Drive.create_session nil_metadata in
        Alcotest.(check string)
          "meth" "POST"
          (match r.meth with `GET -> "GET" | `POST -> "POST");
        (* Copied verbatim from scripts/record-drive-fixtures.sh's
           create_session_url. *)
        Alcotest.(check string)
          "url"
          "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,webViewLink"
          r.url;
        (match r.body with
        | Drive.Json s ->
            Alcotest.(check string)
              "body is metadata_json, compact"
              (Yojson.Safe.to_string (Drive.metadata_json nil_metadata))
              s
        | _ -> Alcotest.fail "create_session body is not Json");
        Alcotest.(check (option string))
          "content_type" (Some "application/json; charset=UTF-8")
          (Drive.content_type r.body) );
  ]

(* ---------- decode_session ---------- *)

let session_url = Drive.upload_api ^ "?uploadType=resumable&upload_id=x"
let other_session_url = Drive.upload_api ^ "?uploadType=resumable&upload_id=y"
let session_result = Alcotest.(result string error_t)

let decode_session_tests =
  [
    ( "a lowercase location header decodes the session URL",
      `Quick,
      fun () ->
        Alcotest.check session_result "decode_session" (Ok session_url)
          (Drive.decode_session [("location", session_url)]) );
    ( "a Location header (capitalised) is accepted too",
      `Quick,
      fun () ->
        Alcotest.check session_result "decode_session" (Ok session_url)
          (Drive.decode_session [("Location", session_url)]) );
    ( "no location header is Malformed \"location\"",
      `Quick,
      fun () ->
        Alcotest.check session_result "decode_session"
          (Error (Drive.Malformed "location")) (Drive.decode_session []) );
    ( "a location outside upload_api is Malformed \"location\"",
      `Quick,
      fun () ->
        Alcotest.check session_result "decode_session"
          (Error (Drive.Malformed "location"))
          (Drive.decode_session [("location", "https://evil.example/x")]) );
    ( "two location headers: the first wins",
      `Quick,
      fun () ->
        Alcotest.check session_result "decode_session" (Ok session_url)
          (Drive.decode_session
             [("location", session_url); ("location", other_session_url)]) );
  ]

(* ---------- start_session, over the sequential fake network ---------- *)

let target : Drive.target =
  {
    species = "Digitalis purpurea";
    name = "2026-06-14 10.32.05 5f3c91d2.jpg";
    mime = "image/jpeg";
    photo_id = photo_id 5;
    sha256 = sha256_hex;
  }

let pp_start ppf = function
  | Drive.Already_there f -> Format.fprintf ppf "Already_there %a" pp_file f
  | Drive.Session url -> Format.fprintf ppf "Session %s" url

let start_t = Alcotest.testable pp_start Drive.equal_start
let start_result = Alcotest.(result start_t error_t)

let start_session_tests =
  [
    ( "a file already there: Already_there (the oldest), exactly 1 request",
      `Quick,
      fun () ->
        let prog = Drive.start_session ~root:None target in
        let resp =
          answer
            {|{"files":[{"id":"FILE0","webViewLink":"https://drive.test/FILE0"},{"id":"FILE9","webViewLink":"https://drive.test/FILE9"}]}|}
        in
        let reqs = Drive.requests (seq_net [resp]) prog in
        check_requests "find_original alone"
          [Drive.find_original ~id:target.photo_id]
          reqs;
        let r = Drive.run (seq_net [resp]) prog in
        Alcotest.check start_result "start_session"
          (Ok
             (Drive.Already_there
                {id = "FILE0"; web_view_link = Some "https://drive.test/FILE0"}))
          r.result;
        Alcotest.check root_change_t "start_session root" Drive.Keep r.root );
    ( "nothing there, root found, species absent: the five requests in order, \
       Session url",
      `Quick,
      fun () ->
        let prog = Drive.start_session ~root:None target in
        let responses =
          [
            answer {|{"files":[]}|};
            answer {|{"files":[{"id":"ROOT1"}]}|};
            answer {|{"files":[]}|};
            answer {|{"id":"SPEC1"}|};
            answer ~headers:[("location", session_url)] "{}";
          ]
        in
        check_requests "the five requests"
          [
            Drive.find_original ~id:target.photo_id;
            Drive.find_folder ~name:Drive.root_folder ~parent:Drive.Root;
            Drive.find_folder ~name:target.species
              ~parent:(Drive.Folder "ROOT1");
            Drive.create_folder ~name:target.species
              ~parent:(Drive.Folder "ROOT1");
            Drive.create_session
              {
                name = target.name;
                mime = target.mime;
                folder_id = "SPEC1";
                photo_id = target.photo_id;
                sha256 = target.sha256;
              };
          ]
          (Drive.requests (seq_net responses) prog);
        let r = Drive.run (seq_net responses) prog in
        Alcotest.check start_result "start_session"
          (Ok (Drive.Session session_url)) r.result;
        Alcotest.check root_change_t "start_session root" (Drive.Store "ROOT1")
          r.root );
    ( "nothing there, root and species absent: the six requests in order, \
       Session url",
      `Quick,
      fun () ->
        let prog = Drive.start_session ~root:None target in
        let responses =
          [
            answer {|{"files":[]}|};
            answer {|{"files":[]}|};
            answer {|{"id":"ROOT1"}|};
            answer {|{"files":[]}|};
            answer {|{"id":"SPEC1"}|};
            answer ~headers:[("location", session_url)] "{}";
          ]
        in
        check_requests "the six requests"
          [
            Drive.find_original ~id:target.photo_id;
            Drive.find_folder ~name:Drive.root_folder ~parent:Drive.Root;
            Drive.create_folder ~name:Drive.root_folder ~parent:Drive.Root;
            Drive.find_folder ~name:target.species
              ~parent:(Drive.Folder "ROOT1");
            Drive.create_folder ~name:target.species
              ~parent:(Drive.Folder "ROOT1");
            Drive.create_session
              {
                name = target.name;
                mime = target.mime;
                folder_id = "SPEC1";
                photo_id = target.photo_id;
                sha256 = target.sha256;
              };
          ]
          (Drive.requests (seq_net responses) prog);
        let r = Drive.run (seq_net responses) prog in
        Alcotest.check start_result "start_session"
          (Ok (Drive.Session session_url)) r.result;
        Alcotest.check root_change_t "start_session root" (Drive.Store "ROOT1")
          r.root );
    ( "a 503 on the species lookup is Server 503, the requests end there",
      `Quick,
      fun () ->
        let prog = Drive.start_session ~root:None target in
        let responses =
          [
            answer {|{"files":[]}|};
            answer {|{"files":[{"id":"ROOT1"}]}|};
            answer ~status:503 "";
          ]
        in
        check_requests "three requests"
          [
            Drive.find_original ~id:target.photo_id;
            Drive.find_folder ~name:Drive.root_folder ~parent:Drive.Root;
            Drive.find_folder ~name:target.species
              ~parent:(Drive.Folder "ROOT1");
          ]
          (Drive.requests (seq_net responses) prog);
        let r = Drive.run (seq_net responses) prog in
        Alcotest.check start_result "start_session" (Error (Drive.Server 503))
          r.result;
        Alcotest.check root_change_t
          "start_session root: resolved before the failure, still stored"
          (Drive.Store "ROOT1") r.root );
    ( "a session 200 without a location header is Malformed \"location\"",
      `Quick,
      fun () ->
        let prog = Drive.start_session ~root:None target in
        let responses =
          [
            answer {|{"files":[]}|};
            answer {|{"files":[{"id":"ROOT1"}]}|};
            answer {|{"files":[{"id":"SPEC1"}]}|};
            answer "{}";
          ]
        in
        let r = Drive.run (seq_net responses) prog in
        Alcotest.check start_result "start_session"
          (Error (Drive.Malformed "location")) r.result;
        Alcotest.check root_change_t
          "start_session root: resolved before the failure, still stored"
          (Drive.Store "ROOT1") r.root );
    ( "the session's 401 (invalid token), recorded, is Unauthorized",
      `Quick,
      fun () ->
        let prog = Drive.start_session ~root:None target in
        let responses =
          [
            answer {|{"files":[]}|};
            answer {|{"files":[{"id":"ROOT1"}]}|};
            answer {|{"files":[{"id":"SPEC1"}]}|};
            answer ~status:401
              (fixture "files_create_session_invalid_token_401");
          ]
        in
        let r = Drive.run (seq_net responses) prog in
        Alcotest.check start_result "start_session" (Error Drive.Unauthorized)
          r.result;
        Alcotest.check root_change_t
          "start_session root: resolved before the failure, still stored"
          (Drive.Store "ROOT1") r.root;
        Alcotest.check error_t "error_of_answer on the same fixture"
          Drive.Unauthorized
          (Drive.error_of_answer ~status:401
             ~body:(fixture "files_create_session_invalid_token_401")) );
    ( "an unreachable lookup is Network, exactly 1 request",
      `Quick,
      fun () ->
        let prog = Drive.start_session ~root:None target in
        let net = seq_net [Drive.Unreachable "timeout"] in
        let reqs = Drive.requests net prog in
        check_requests "find_original alone"
          [Drive.find_original ~id:target.photo_id]
          reqs;
        let r = Drive.run (seq_net [Drive.Unreachable "timeout"]) prog in
        Alcotest.check start_result "start_session"
          (Error (Drive.Network "timeout")) r.result;
        Alcotest.check root_change_t "start_session root" Drive.Keep r.root );
  ]

(* ---------- view_url ---------- *)

let view_url_tests =
  [
    ( "the exact Drive view URL, from drive_file_id",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "view_url" "https://drive.google.com/file/d/1AbC_d-9/view"
          (Drive.view_url ~file_id:"1AbC_d-9") );
    ( "a file id with a slash and a space is percent-encoded",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "view_url" "https://drive.google.com/file/d/a%2Fb%20c/view"
          (Drive.view_url ~file_id:"a/b c") );
    ( "when the recorded files.create answer of an original exists \
       (HERBIER_DRIVE_TOKEN), it has a webViewLink and view_url of its id is a \
       prefix of it",
      `Quick,
      fun () ->
        let file = "drive_files_create_original_200.json" in
        match Fixture.exists file with
        | false -> print_endline ("not recorded yet, skipped: " ^ file)
        | true -> (
            match Yojson.Safe.from_string (Fixture.read file) with
            | `Assoc fields -> (
                match
                  ( List.assoc_opt "id" fields,
                    List.assoc_opt "webViewLink" fields )
                with
                | Some (`String id), Some (`String link) ->
                    Alcotest.(check bool)
                      "view_url is a prefix of webViewLink" true
                      (String.starts_with
                         ~prefix:(Drive.view_url ~file_id:id)
                         link)
                | Some (`String _), _ -> Alcotest.fail "no webViewLink"
                | _, _ -> Alcotest.fail "no id")
            | _ -> Alcotest.failf "%s: not a JSON object" file) );
  ]
