(* Herbier_identify.Make over Fake_transport: the request
   sent, the result, the error classes and the console line of identify and
   projects, and that no line ever holds the key. Fake_transport's ['a io] is
   ['a], so each call gives its ['a logged] directly. *)

module Identify = Herbier_identify
module Plantnet = Herbier_identify.Plantnet
module Organ = Herbier_identify.Organ
module Transport = Herbier_identify.Transport
module Text = Herbier_test_support.Text
module Url = Herbier_net.Url
module Fake = Fake_transport

(* The test key: it contains a space and an '&' to exercise encoding. *)
let key = "TEST-key-7f3a&9 z"
let encoded_key = Url.encode key
let error = Alcotest.testable Plantnet.pp_error Plantnet.equal_error

let expect_error msg expected result =
  match result with
  | Error e -> Alcotest.(check error) msg expected e
  | Ok _ -> Alcotest.failf "%s: got Ok" msg

let file_json (f : string Transport.file) =
  `Assoc
    [
      ("field", `String f.field);
      ("filename", `String f.filename);
      ("image", `String f.image);
    ]

let files_equal (a : string Transport.file list)
    (b : string Transport.file list) =
  let eq (x : string Transport.file) (y : string Transport.file) =
    String.equal x.field y.field
    && String.equal x.filename y.filename
    && String.equal x.image y.image
  in
  List.length a = List.length b && List.for_all2 eq a b

let files =
  Alcotest.testable
    (fun ppf fs ->
      Format.pp_print_string ppf
        (Yojson.Safe.pretty_to_string (`List (List.map file_json fs))))
    files_equal

let fields = Alcotest.(list (pair string string))

let occurrences ~sub s =
  let sub_len = String.length sub and s_len = String.length s in
  let rec go i acc =
    match i + sub_len > s_len with
    | true -> acc
    | false ->
        let found = String.equal (String.sub s i sub_len) sub in
        go (i + 1) (match found with true -> acc + 1 | false -> acc)
  in
  go 0 0

(* Runs Make over a fresh Fake_transport answering with [respond]; returns
   the result and the calls made. *)
let run_identify respond ~key ~flora ?no_reject photos =
  let module F = Fake.Make (struct
    let respond = respond
  end) in
  let module Id = Identify.Make (F) in
  (* [F.calls ()] must be read only after [identify] has run: a tuple's
     components are not evaluated left to right. *)
  let result = Id.identify ~key ~flora ?no_reject photos in
  let calls = F.calls () in
  (result, calls)

let run_projects respond ~key =
  let module F = Fake.Make (struct
    let respond = respond
  end) in
  let module Id = Identify.Make (F) in
  let result = Id.projects ~key in
  let calls = F.calls () in
  (result, calls)

let no_call_expected (_ : Fake.call) = Alcotest.fail "no call expected"

(* Inline records can't be bound whole ([Fake.Post p]): destructure into a
   plain tuple instead. *)
let one_post calls =
  match calls with
  | [Fake.Post {url; fields; files}] -> (url, fields, files)
  | _ ->
      Alcotest.failf "expected exactly one Post call, got %d"
        (List.length calls)

let one_get calls =
  match calls with
  | [Fake.Get {url}] -> url
  | _ ->
      Alcotest.failf "expected exactly one Get call, got %d" (List.length calls)

(* ---------- success ---------- *)

let one_photo_auto () =
  let url = Plantnet.identify_url ~key ~flora:"all" ~no_reject:false in
  let logged, calls =
    run_identify
      (Fake.expect_url url (Fake.fixture "plantnet_identify_one_auto_200.json"))
      ~key ~flora:"all"
      [("img-a", Organ.Auto)]
  in
  let post_url, post_fields, post_files = one_post calls in
  Alcotest.(check string) "url" url post_url;
  Alcotest.(check fields) "fields" [("organs", "auto")] post_fields;
  Alcotest.(check files)
    "files"
    [{Transport.field = "images"; filename = "photo-1.jpg"; image = "img-a"}]
    post_files;
  (match logged.result with
  | Ok identified ->
      Alcotest.(check int)
        "5 proposals" 5
        (List.length identified.answer.proposals);
      Alcotest.(check bool) "uncertain" true identified.uncertain
  | Error e -> Alcotest.failf "identify: %s" (Plantnet.error_to_string e));
  Alcotest.(check string)
    "line" "identify: POST all 1 photo(s) → 200, 499 left today" logged.line

let two_photos_given () =
  let url = Plantnet.identify_url ~key ~flora:"all" ~no_reject:false in
  let logged, calls =
    run_identify
      (Fake.expect_url url
         (Fake.fixture "plantnet_identify_two_flower_leaf_200.json"))
      ~key ~flora:"all"
      [("a", Organ.Given Organ.Flower); ("b", Organ.Given Organ.Leaf)]
  in
  let _, post_fields, post_files = one_post calls in
  Alcotest.(check fields)
    "fields"
    [("organs", "flower"); ("organs", "leaf")]
    post_fields;
  Alcotest.(check files)
    "files"
    [
      {Transport.field = "images"; filename = "photo-1.jpg"; image = "a"};
      {Transport.field = "images"; filename = "photo-2.jpg"; image = "b"};
    ]
    post_files;
  (match logged.result with
  | Ok identified ->
      Alcotest.(check bool) "uncertain" false identified.uncertain;
      Alcotest.(check (option int))
        "genus-level gbif null" None
        (List.nth identified.answer.proposals 3).gbif
  | Error e -> Alcotest.failf "identify: %s" (Plantnet.error_to_string e));
  Alcotest.(check string)
    "line" "identify: POST all 2 photo(s) → 200, 498 left today" logged.line

let success_tests =
  [
    ("one photo, auto organ: request, result, line", `Quick, one_photo_auto);
    ( "two photos, given organs: fields, files, uncertain, line",
      `Quick,
      two_photos_given );
  ]

(* ---------- URL query ---------- *)

let url_query_tests =
  [
    ( "lang=fr, include-related-images=true, nb-results=5, no no-reject by \
       default",
      `Quick,
      fun () ->
        let url = Plantnet.identify_url ~key ~flora:"all" ~no_reject:false in
        Alcotest.(check bool) "lang=fr" true (Text.contains ~sub:"lang=fr" url);
        Alcotest.(check bool)
          "include-related-images=true" true
          (Text.contains ~sub:"include-related-images=true" url);
        Alcotest.(check bool)
          "nb-results=5" true
          (Text.contains ~sub:"nb-results=5" url);
        Alcotest.(check bool)
          "no no-reject by default" false
          (Text.contains ~sub:"no-reject" url) );
    ( "no_reject:true adds no-reject=true and the request still reaches the \
       server (404, not a plant)",
      `Quick,
      fun () ->
        let url = Plantnet.identify_url ~key ~flora:"all" ~no_reject:true in
        Alcotest.(check bool)
          "no-reject=true" true
          (Text.contains ~sub:"no-reject=true" url);
        let logged, calls =
          run_identify
            (Fake.expect_url url
               (Fake.fixture "plantnet_identify_not_plant_no_reject_404.json"))
            ~key ~flora:"all" ~no_reject:true
            [("img-a", Organ.Auto)]
        in
        ignore (one_post calls);
        expect_error "no_reject 404" Plantnet.No_plant logged.result );
  ]

(* ---------- key placement ---------- *)

let key_not_leaked_tests =
  [
    ( "the key occurs only in the URL, once, encoded after api-key=",
      `Quick,
      fun () ->
        let url = Plantnet.identify_url ~key ~flora:"all" ~no_reject:false in
        let _, calls =
          run_identify
            (Fake.expect_url url
               (Fake.fixture "plantnet_identify_two_flower_leaf_200.json"))
            ~key ~flora:"all"
            [("a", Organ.Given Organ.Flower); ("b", Organ.Given Organ.Leaf)]
        in
        let post_url, post_fields, post_files = one_post calls in
        Alcotest.(check int)
          "api-key=<key> once in the url" 1
          (occurrences ~sub:("api-key=" ^ encoded_key) post_url);
        List.iter
          (fun (_, v) ->
            List.iter
              (fun k ->
                Alcotest.(check bool)
                  "key not in a field value" false (Text.contains ~sub:k v))
              [key; encoded_key])
          post_fields;
        List.iter
          (fun (f : string Transport.file) ->
            List.iter
              (fun k ->
                Alcotest.(check bool)
                  "key not in a filename" false
                  (Text.contains ~sub:k f.filename))
              [key; encoded_key])
          post_files );
  ]

(* ---------- more than five photos ---------- *)

let six_photos_test =
  [
    ( "six photos: one call with five fields and five files",
      `Quick,
      fun () ->
        let url = Plantnet.identify_url ~key ~flora:"all" ~no_reject:false in
        let photos =
          List.init 6 (fun i -> (Printf.sprintf "img-%d" i, Organ.Auto))
        in
        let logged, calls =
          run_identify
            (Fake.expect_url url
               (Fake.fixture "plantnet_identify_one_auto_200.json"))
            ~key ~flora:"all" photos
        in
        let _, post_fields, post_files = one_post calls in
        Alcotest.(check int) "five fields" 5 (List.length post_fields);
        Alcotest.(check (list string))
          "the first five files"
          (List.init 5 (Printf.sprintf "img-%d"))
          (List.map (fun (f : string Transport.file) -> f.image) post_files);
        Alcotest.(check string)
          "line" "identify: POST all 5 photo(s) → 200, 499 left today"
          logged.line );
  ]

(* ---------- error classes ---------- *)

let identify_url = Plantnet.identify_url ~key ~flora:"all" ~no_reject:false

let status_class_tests =
  let case name answer expected =
    ( name,
      `Quick,
      fun () ->
        let logged, calls =
          run_identify
            (Fake.expect_url identify_url answer)
            ~key ~flora:"all"
            [("img-a", Organ.Auto)]
        in
        ignore (one_post calls);
        expect_error name expected logged.result )
  in
  [
    case "404: not a plant"
      (Fake.fixture "plantnet_identify_not_plant_404.json")
      Plantnet.No_plant;
    case "401: key refused"
      (Fake.fixture "plantnet_identify_invalid_key_401.json")
      Plantnet.Key_refused;
    (* The CORS refusal was recorded on /projects: it checks the key and the
       Origin, not the route (architecture §12, « CORS »). *)
    case "403 (origin refused body) on identify: key not exposed"
      (Fake.fixture "plantnet_projects_origin_refused_403.json")
      Plantnet.Key_not_exposed;
    case "429: quota used up" (Fake.status 429) Plantnet.Quota_used_up;
    case "413: refused request" (Fake.status 413) (Plantnet.Refused_request 413);
    case "503: unreachable, server error" (Fake.status 503)
      (Plantnet.Unreachable (Plantnet.Server 503));
    case "300: not a success, refused request" (Fake.status 300)
      (Plantnet.Refused_request 300);
  ]

let other_2xx_test =
  [
    ( "a 204 is a success: decoded, its status in the line",
      `Quick,
      fun () ->
        let logged, calls =
          run_identify
            (Fake.expect_url identify_url
               (Ok
                  {
                    Transport.status = 204;
                    body =
                      Herbier_test_support.Fixture.read
                        "plantnet_identify_one_auto_200.json";
                  }))
            ~key ~flora:"all"
            [("img-a", Organ.Auto)]
        in
        ignore (one_post calls);
        (match logged.result with
        | Ok identified ->
            Alcotest.(check int)
              "5 proposals" 5
              (List.length identified.answer.proposals)
        | Error e -> Alcotest.failf "identify: %s" (Plantnet.error_to_string e));
        Alcotest.(check string)
          "line" "identify: POST all 1 photo(s) → 204, 499 left today"
          logged.line );
  ]

let transport_failure_tests =
  [
    ( "transport Timeout -> Unreachable Timeout",
      `Quick,
      fun () ->
        let logged, calls =
          run_identify
            (Fake.expect_url identify_url (Error Transport.Timeout))
            ~key ~flora:"all"
            [("img-a", Organ.Auto)]
        in
        ignore (one_post calls);
        expect_error "Timeout" (Plantnet.Unreachable Plantnet.Timeout)
          logged.result );
    ( "transport Network m -> Unreachable (Network m)",
      `Quick,
      fun () ->
        let logged, calls =
          run_identify
            (Fake.expect_url identify_url
               (Error (Transport.Network "TypeError: Failed to fetch")))
            ~key ~flora:"all"
            [("img-a", Organ.Auto)]
        in
        ignore (one_post calls);
        expect_error "Network" (Plantnet.Unreachable Plantnet.Network)
          logged.result );
    ( "a network failure text holding the URL: no key in the error text",
      `Quick,
      fun () ->
        let logged, _ =
          run_identify
            (Fake.expect_url identify_url
               (Error
                  (Transport.Network
                     ("TypeError: Failed to parse URL from " ^ identify_url))))
            ~key ~flora:"all"
            [("img-a", Organ.Auto)]
        in
        match logged.result with
        | Error e ->
            let text = Plantnet.error_to_string e in
            Alcotest.(check string)
              "error text" "unreachable: network failure" text;
            List.iter
              (fun k ->
                Alcotest.(check bool)
                  ("no key in: " ^ text) false
                  (Text.contains ~sub:k text))
              [key; encoded_key; "api-key"; "https://"]
        | Ok _ -> Alcotest.fail "expected an error" );
  ]

let malformed_200_test =
  [
    ( "a 2xx with a non-JSON body is Malformed \"not JSON\"",
      `Quick,
      fun () ->
        let logged, calls =
          run_identify
            (Fake.expect_url identify_url
               (Ok {Transport.status = 200; body = "oops"}))
            ~key ~flora:"all"
            [("img-a", Organ.Auto)]
        in
        ignore (one_post calls);
        expect_error "malformed" (Plantnet.Malformed "not JSON") logged.result
    );
  ]

(* ---------- console line suffixes ---------- *)

let line_of answer =
  let logged, calls =
    run_identify
      (Fake.expect_url identify_url answer)
      ~key ~flora:"all"
      [("img-a", Organ.Auto)]
  in
  ignore (one_post calls);
  logged.line

let line_tests =
  let case answer expected =
    ( Printf.sprintf "line %S" expected,
      `Quick,
      fun () -> Alcotest.(check string) "line" expected (line_of answer) )
  in
  [
    case
      (Fake.fixture "plantnet_identify_not_plant_404.json")
      "identify: POST all 1 photo(s) → 404, no plant";
    case
      (Fake.fixture "plantnet_identify_invalid_key_401.json")
      "identify: POST all 1 photo(s) → 401, key refused";
    case
      (Fake.fixture "plantnet_projects_origin_refused_403.json")
      "identify: POST all 1 photo(s) → 403, key not exposed for the app";
    case (Fake.status 429) "identify: POST all 1 photo(s) → 429, quota used up";
    case (Fake.status 413)
      "identify: POST all 1 photo(s) → 413, refused request (HTTP 413)";
    case (Fake.status 503)
      "identify: POST all 1 photo(s) → 503, unreachable: HTTP 503";
    case
      (Ok {Transport.status = 200; body = "oops"})
      "identify: POST all 1 photo(s) → 200, malformed answer: not JSON";
    case (Error Transport.Timeout) "identify: POST all 1 photo(s) → timeout";
    (* The transport's own text (TypeError ...) is not in the line. *)
    case (Error (Transport.Network "TypeError: Failed to fetch"))
      "identify: POST all 1 photo(s) → network failure";
  ]

(* one_auto_200 without remainingIdentificationRequests (Yojson, not on
   disk): the line has no ", ... left today". *)
let no_remaining_test =
  [
    ( "a 200 without remainingIdentificationRequests: no \"left today\"",
      `Quick,
      fun () ->
        let body =
          match
            Yojson.Safe.from_string
              (Herbier_test_support.Fixture.read
                 "plantnet_identify_one_auto_200.json")
          with
          | `Assoc fields ->
              Yojson.Safe.to_string
                (`Assoc
                   (List.filter
                      (fun (k, _) ->
                        not (String.equal k "remainingIdentificationRequests"))
                      fields))
          | _ -> Alcotest.fail "one_auto_200 is not a JSON object"
        in
        let line = line_of (Ok {Transport.status = 200; body}) in
        Alcotest.(check string)
          "line" "identify: POST all 1 photo(s) → 200" line );
  ]

(* ---------- not sent ---------- *)

let not_sent_tests =
  [
    ( "blank key: no call, Error No_key, line says why",
      `Quick,
      fun () ->
        let logged, calls =
          run_identify no_call_expected ~key:"" ~flora:"all"
            [("img-a", Organ.Auto)]
        in
        Alcotest.(check int) "no call" 0 (List.length calls);
        expect_error "No_key" Plantnet.No_key logged.result;
        Alcotest.(check string)
          "line" "identify: POST all 1 photo(s) not sent: no key" logged.line );
    ( "no photo: no call, Error No_photo, line says why",
      `Quick,
      fun () ->
        let logged, calls =
          run_identify no_call_expected ~key ~flora:"all" []
        in
        Alcotest.(check int) "no call" 0 (List.length calls);
        expect_error "No_photo" Plantnet.No_photo logged.result;
        Alcotest.(check string)
          "line" "identify: POST all 0 photo(s) not sent: no photo" logged.line
    );
    ( "not sent: the line names the trimmed flora and at most five photos",
      `Quick,
      fun () ->
        let logged, calls =
          run_identify no_call_expected ~key:"  "
            ~flora:" k-southwestern-europe "
            (List.init 6 (fun i -> (Printf.sprintf "img-%d" i, Organ.Auto)))
        in
        Alcotest.(check int) "no call" 0 (List.length calls);
        Alcotest.(check string)
          "line"
          "identify: POST k-southwestern-europe 5 photo(s) not sent: no key"
          logged.line );
    ( "not sent: a blank flora is named all in the line",
      `Quick,
      fun () ->
        let logged, _ =
          run_identify no_call_expected ~key:"" ~flora:"  "
            [("img-a", Organ.Auto)]
        in
        Alcotest.(check string)
          "line" "identify: POST all 1 photo(s) not sent: no key" logged.line );
    ( "a caller's own gate: the same line with its reason",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "identify" "identify: POST k-world-flora 5 photo(s) not sent: offline"
          (Identify.identify_not_sent ~flora:" k-world-flora "
             (List.init 6 Fun.id) "offline");
        Alcotest.(check string)
          "blank flora"
          "identify: POST all 1 photo(s) not sent: preview unreadable"
          (Identify.identify_not_sent ~flora:"" [()] "preview unreadable");
        Alcotest.(check string)
          "projects" "identify: GET projects not sent: offline"
          (Identify.projects_not_sent "offline") );
  ]

(* ---------- projects ---------- *)

let projects_url = Plantnet.projects_url ~key

let projects_tests =
  [
    ( "projects_fr_200: one Get on projects_url, 75 floras, line",
      `Quick,
      fun () ->
        let logged, calls =
          run_projects
            (Fake.expect_url projects_url
               (Fake.fixture "plantnet_projects_fr_200.json"))
            ~key
        in
        let get_url = one_get calls in
        Alcotest.(check string) "url" projects_url get_url;
        (match logged.result with
        | Ok projects ->
            Alcotest.(check int) "75 projects" 75 (List.length projects)
        | Error e -> Alcotest.failf "projects: %s" (Plantnet.error_to_string e));
        Alcotest.(check string)
          "line" "identify: GET projects → 200" logged.line );
    ( "403 origin refused: key not exposed",
      `Quick,
      fun () ->
        let logged, calls =
          run_projects
            (Fake.expect_url projects_url
               (Fake.fixture "plantnet_projects_origin_refused_403.json"))
            ~key
        in
        ignore (one_get calls);
        expect_error "Key_not_exposed" Plantnet.Key_not_exposed logged.result;
        Alcotest.(check string)
          "line" "identify: GET projects → 403, key not exposed for the app"
          logged.line;
        (* The class only: never the body's own text. *)
        Alcotest.(check bool)
          "no body text" false
          (Text.contains ~sub:"CORS" logged.line) );
    ( "transport failures: Unreachable, line without the failure text",
      `Quick,
      fun () ->
        let timeout, _ =
          run_projects
            (Fake.expect_url projects_url (Error Transport.Timeout))
            ~key
        in
        expect_error "Timeout" (Plantnet.Unreachable Plantnet.Timeout)
          timeout.result;
        Alcotest.(check string)
          "timeout line" "identify: GET projects → timeout" timeout.line;
        let network, _ =
          run_projects
            (Fake.expect_url projects_url
               (Error (Transport.Network "TypeError: Failed to fetch")))
            ~key
        in
        expect_error "Network" (Plantnet.Unreachable Plantnet.Network)
          network.result;
        Alcotest.(check string)
          "network line" "identify: GET projects → network failure" network.line
    );
    ( "a 200 that does not decode: Malformed, the reason in the line",
      `Quick,
      fun () ->
        let logged, _ =
          run_projects
            (Fake.expect_url projects_url
               (Ok {Transport.status = 200; body = "oops"}))
            ~key
        in
        expect_error "Malformed" (Plantnet.Malformed "not JSON") logged.result;
        Alcotest.(check string)
          "line" "identify: GET projects → 200, malformed answer: not JSON"
          logged.line );
    ( "a key with spaces around is trimmed in the URL",
      `Quick,
      fun () ->
        let logged, calls =
          run_projects
            (Fake.expect_url projects_url
               (Fake.fixture "plantnet_projects_fr_200.json"))
            ~key:(" " ^ key ^ " ")
        in
        ignore (one_get calls);
        Alcotest.(check string)
          "line" "identify: GET projects → 200" logged.line );
    ( "blank key: no call, Error No_key, line says why",
      `Quick,
      fun () ->
        let logged, calls = run_projects no_call_expected ~key:"" in
        Alcotest.(check int) "no call" 0 (List.length calls);
        expect_error "No_key" Plantnet.No_key logged.result;
        Alcotest.(check string)
          "line" "identify: GET projects not sent: no key" logged.line );
  ]

(* ---------- no console line ever holds the key ---------- *)

let no_key_in_any_line_test =
  [
    ( "over every case above: no raw key, encoded key, api-key or https://",
      `Quick,
      fun () ->
        let identify_lines =
          List.map line_of
            [
              Fake.fixture "plantnet_identify_one_auto_200.json";
              Fake.fixture "plantnet_identify_not_plant_404.json";
              Fake.fixture "plantnet_identify_invalid_key_401.json";
              Fake.fixture "plantnet_projects_origin_refused_403.json";
              Fake.status 429;
              Fake.status 413;
              Fake.status 503;
              Error Transport.Timeout;
              Error (Transport.Network "TypeError: Failed to fetch");
            ]
        in
        let not_sent_lines =
          [
            (let logged, _ =
               run_identify no_call_expected ~key:"" ~flora:"all"
                 [("img-a", Organ.Auto)]
             in
             logged.line);
            (let logged, _ =
               run_identify no_call_expected ~key ~flora:"all" []
             in
             logged.line);
          ]
        in
        let projects_lines =
          [
            (let logged, _ =
               run_projects
                 (Fake.expect_url projects_url
                    (Fake.fixture "plantnet_projects_fr_200.json"))
                 ~key
             in
             logged.line);
            (let logged, _ = run_projects no_call_expected ~key:"" in
             logged.line);
          ]
        in
        List.iter
          (fun line ->
            Alcotest.(check bool)
              ("no raw key in: " ^ line) false
              (Text.contains ~sub:key line);
            Alcotest.(check bool)
              ("no encoded key in: " ^ line)
              false
              (Text.contains ~sub:encoded_key line);
            Alcotest.(check bool)
              ("no api-key in: " ^ line) false
              (Text.contains ~sub:"api-key" line);
            Alcotest.(check bool)
              ("no https:// in: " ^ line)
              false
              (Text.contains ~sub:"https://" line))
          (identify_lines @ not_sent_lines @ projects_lines) );
  ]

let suites =
  [
    ("make identify: success", success_tests);
    ("make identify: URL query", url_query_tests);
    ("make identify: key placement", key_not_leaked_tests);
    ("make identify: more than five photos", six_photos_test);
    ("make identify: error classes (statuses)", status_class_tests);
    ("make identify: another 2xx", other_2xx_test);
    ("make identify: transport failures", transport_failure_tests);
    ("make identify: malformed 2xx body", malformed_200_test);
    ("make identify: console lines", line_tests @ no_remaining_test);
    ("make identify: not sent", not_sent_tests);
    ("make projects", projects_tests);
    ("make: no console line ever holds the key", no_key_in_any_line_test);
  ]
