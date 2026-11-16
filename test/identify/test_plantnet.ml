(* Herbier_identify.Plantnet: the identify and projects URLs, the request as
   a value, the recorded answers decoded, Yojson-built variants of
   two_flower_leaf_200 (never written to disk), the image host rule, and the
   error classes.

   The records have [equal_*] but no printer; the testables print them
   through a Yojson rendering built here. *)

module Plantnet = Herbier_identify.Plantnet
module Organ = Herbier_identify.Organ
module Transport = Herbier_identify.Transport
module Fixture = Herbier_test_support.Fixture
module Text = Herbier_test_support.Text
module Url = Herbier_net.Url

let organ = Alcotest.testable Organ.pp Organ.equal
let error = Alcotest.testable Plantnet.pp_error Plantnet.equal_error
let str s = `String s
let opt f = function None -> `Null | Some v -> f v
let int n = `Int n

let image_json (i : Plantnet.image) =
  `Assoc
    [
      ("organ", opt (fun o -> str (Organ.to_string o)) i.organ);
      ("author", str i.author);
      ("licence", str i.licence);
      ("citation", opt str i.citation);
      ("small", str i.small);
      ("medium", str i.medium);
    ]

let image =
  Alcotest.testable
    (fun ppf i ->
      Format.pp_print_string ppf (Yojson.Safe.pretty_to_string (image_json i)))
    Plantnet.equal_image

let answer_json (a : Plantnet.answer) =
  `Assoc
    [
      ( "proposals",
        `List
          (List.map
             (fun (p : Plantnet.proposal) ->
               `Assoc
                 [
                   ("score", `Float p.score);
                   ("name", str p.name);
                   ("author", str p.author);
                   ("scientific_name", str p.scientific_name);
                   ("family", opt str p.family);
                   ("common_names", `List (List.map str p.common_names));
                   ("gbif", opt int p.gbif);
                   ("images", `List (List.map image_json p.images));
                 ])
             a.proposals) );
      ( "detected",
        `List (List.map (opt (fun o -> str (Organ.to_string o))) a.detected) );
      ("flora", opt str a.flora);
      ("remaining", opt int a.remaining);
    ]

let answer =
  Alcotest.testable
    (fun ppf a ->
      Format.pp_print_string ppf (Yojson.Safe.pretty_to_string (answer_json a)))
    Plantnet.equal_answer

let answer_result = Alcotest.(result answer error)

let project_json (p : Plantnet.project) =
  `Assoc [("id", str p.id); ("title", str p.title)]

let projects =
  Alcotest.testable
    (fun ppf ps ->
      Format.pp_print_string ppf
        (Yojson.Safe.pretty_to_string (`List (List.map project_json ps))))
    (fun a b ->
      List.length a = List.length b
      && List.for_all2 (fun x y -> Plantnet.equal_project x y) a b)

let projects_result = Alcotest.(result projects error)

let file_json (f : string Transport.file) =
  `Assoc
    [
      ("field", str f.field);
      ("filename", str f.filename);
      ("image", str f.image);
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

(* The test key: it contains a space and an '&' to exercise encoding. *)
let key = "TEST-key-7f3a&9 z"
let encoded_key = Url.encode key

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

let expect_ok msg result f =
  match result with
  | Ok value -> f value
  | Error e ->
      Alcotest.failf "%s: got Error %s" msg (Plantnet.error_to_string e)

let expect_error msg expected result =
  match result with
  | Error e -> Alcotest.(check error) msg expected e
  | Ok _ -> Alcotest.failf "%s: got Ok" msg

(* ---------- identify_url ---------- *)

let identify_url_tests =
  [
    ( "exact URL for key K, flora all, no no-reject",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "identify_url"
          "https://my-api.plantnet.org/v2/identify/all?include-related-images=true&lang=fr&nb-results=5&api-key=K"
          (Plantnet.identify_url ~key:"K" ~flora:"all" ~no_reject:false) );
    ( "no_reject:true adds no-reject=true before api-key",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "identify_url ~no_reject:true"
          "https://my-api.plantnet.org/v2/identify/all?include-related-images=true&lang=fr&nb-results=5&no-reject=true&api-key=K"
          (Plantnet.identify_url ~key:"K" ~flora:"all" ~no_reject:true) );
    ( "a flora with a slash is percent-encoded in the path",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "a%2Fb in the path" true
          (Text.contains ~sub:"/identify/a%2Fb?"
             (Plantnet.identify_url ~key:"K" ~flora:"a/b" ~no_reject:false)) );
    ( "a key with a space and an '&' is percent-encoded after api-key=",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "api-key=a%20b%26c" true
          (Text.contains ~sub:"api-key=a%20b%26c"
             (Plantnet.identify_url ~key:"a b&c" ~flora:"all" ~no_reject:false))
    );
  ]

(* ---------- projects_url ---------- *)

let projects_url_tests =
  [
    ( "exact URL for key K",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "projects_url"
          "https://my-api.plantnet.org/v2/projects?lang=fr&api-key=K"
          (Plantnet.projects_url ~key:"K") );
    ( "never carries lat nor lon",
      `Quick,
      fun () ->
        let url = Plantnet.projects_url ~key:"K" in
        Alcotest.(check bool) "no \"lat\"" false (Text.contains ~sub:"lat" url);
        Alcotest.(check bool) "no \"lon\"" false (Text.contains ~sub:"lon" url)
    );
  ]

(* ---------- identify_request ---------- *)

let identify_request_tests =
  [
    ( "a blank key is No_key, checked before an empty photo list",
      `Quick,
      fun () ->
        expect_error "blank key, no photo" Plantnet.No_key
          (Plantnet.identify_request ~key:"" ~flora:"all" ~no_reject:false [])
    );
    ( "a key of only spaces is No_key, even with a photo",
      `Quick,
      fun () ->
        expect_error "spaces key" Plantnet.No_key
          (Plantnet.identify_request ~key:"   " ~flora:"all" ~no_reject:false
             [("img", Organ.Auto)]) );
    ( "a key with surrounding spaces is trimmed in the URL",
      `Quick,
      fun () ->
        expect_ok "trimmed key"
          (Plantnet.identify_request
             ~key:(" " ^ key ^ " ")
             ~flora:"all" ~no_reject:false
             [("img", Organ.Auto)])
          (fun r ->
            Alcotest.(check bool)
              "api-key=<trimmed key> in the url" true
              (Text.contains ~sub:("api-key=" ^ encoded_key) r.Plantnet.url)) );
    ( "no photo is No_photo",
      `Quick,
      fun () ->
        expect_error "no photo" Plantnet.No_photo
          (Plantnet.identify_request ~key ~flora:"all" ~no_reject:false []) );
    ( "a blank flora falls back to automatic",
      `Quick,
      fun () ->
        List.iter
          (fun flora ->
            expect_ok
              (Printf.sprintf "blank flora %S" flora)
              (Plantnet.identify_request ~key ~flora ~no_reject:false
                 [("img", Organ.Auto)])
              (fun r ->
                Alcotest.(check string) "flora" Plantnet.automatic r.flora;
                Alcotest.(check bool)
                  "path /identify/all" true
                  (Text.contains ~sub:"/identify/all?" r.url)))
          [""; "  "] );
    ( "a flora with surrounding spaces is trimmed",
      `Quick,
      fun () ->
        expect_ok "trimmed flora"
          (Plantnet.identify_request ~key ~flora:" k-southwestern-europe "
             ~no_reject:false
             [("img", Organ.Auto)])
          (fun r ->
            Alcotest.(check string) "flora" "k-southwestern-europe" r.flora;
            Alcotest.(check bool)
              "path /identify/k-southwestern-europe" true
              (Text.contains ~sub:"/identify/k-southwestern-europe?" r.url)) );
    ( "two photos: fields and files, in photo order",
      `Quick,
      fun () ->
        expect_ok "two photos"
          (Plantnet.identify_request ~key ~flora:"all" ~no_reject:false
             [("a", Organ.Given Organ.Flower); ("b", Organ.Auto)])
          (fun r ->
            Alcotest.(check (list (pair string string)))
              "fields"
              [("organs", "flower"); ("organs", "auto")]
              r.fields;
            Alcotest.(check files)
              "files"
              [
                {
                  Transport.field = "images";
                  filename = "photo-1.jpg";
                  image = "a";
                };
                {
                  Transport.field = "images";
                  filename = "photo-2.jpg";
                  image = "b";
                };
              ]
              r.files) );
    ( "seven photos: only the first five are sent, never an error",
      `Quick,
      fun () ->
        let photos =
          List.init 7 (fun i -> (Printf.sprintf "img-%d" i, Organ.Auto))
        in
        expect_ok "seven photos"
          (Plantnet.identify_request ~key ~flora:"all" ~no_reject:false photos)
          (fun r ->
            Alcotest.(check int) "fields count" 5 (List.length r.fields);
            Alcotest.(check int) "files count" 5 (List.length r.files);
            Alcotest.(check files)
              "first five, in order"
              (List.init 5 (fun i ->
                   {
                     Transport.field = "images";
                     filename = Printf.sprintf "photo-%d.jpg" (i + 1);
                     image = Printf.sprintf "img-%d" i;
                   }))
              r.files) );
    ( "the key appears exactly once in the URL, and nowhere else",
      `Quick,
      fun () ->
        expect_ok "key placement"
          (Plantnet.identify_request ~key ~flora:"all" ~no_reject:false
             [("a", Organ.Given Organ.Flower); ("b", Organ.Auto)])
          (fun r ->
            Alcotest.(check int)
              "api-key=<key> once in the url" 1
              (occurrences ~sub:("api-key=" ^ encoded_key) r.url);
            List.iter
              (fun (_, v) ->
                Alcotest.(check bool)
                  "key not in a field value" false
                  (Text.contains ~sub:encoded_key v))
              r.fields;
            List.iter
              (fun (f : string Transport.file) ->
                Alcotest.(check bool)
                  "key not in a filename" false
                  (Text.contains ~sub:encoded_key f.filename))
              r.files) );
  ]

(* ---------- projects_request ---------- *)

let projects_request_tests =
  [
    ( "a blank key is No_key",
      `Quick,
      fun () ->
        List.iter
          (fun key ->
            match Plantnet.projects_request ~key with
            | Error e -> Alcotest.(check error) "No_key" Plantnet.No_key e
            | Ok _ -> Alcotest.failf "projects_request %S: got Ok" key)
          [""; "   "] );
    ( "a key with surrounding spaces is trimmed: projects_url of the key",
      `Quick,
      fun () ->
        match Plantnet.projects_request ~key:(" " ^ key ^ " ") with
        | Ok url ->
            Alcotest.(check string) "url" (Plantnet.projects_url ~key) url
        | Error e -> Alcotest.failf "got Error %s" (Plantnet.error_to_string e)
    );
  ]

(* ---------- decode_answer (fixtures) ---------- *)

let two_flower_leaf = "plantnet_identify_two_flower_leaf_200.json"
let one_auto = "plantnet_identify_one_auto_200.json"
let projects_fr = "plantnet_projects_fr_200.json"

let decode name =
  match Plantnet.decode_answer (Fixture.read name) with
  | Ok a -> a
  | Error e ->
      Alcotest.failf "decode_answer %s: %s" name (Plantnet.error_to_string e)

let decode_two_flower_leaf () =
  let a = decode two_flower_leaf in
  Alcotest.(check (list string))
    "names, in order"
    [
      "Hibiscus rosa-sinensis";
      "Hibiscus schizopetalus";
      "Hibiscus moscheutos";
      "Hibiscus spp.";
      "Hibiscus acetosella";
    ]
    (List.map (fun (p : Plantnet.proposal) -> p.name) a.proposals);
  Alcotest.(check (list (float 1e-9)))
    "scores, order kept"
    [0.52853; 0.01927; 0.01006; 0.00996; 0.00355]
    (List.map (fun (p : Plantnet.proposal) -> p.score) a.proposals);
  (match a.proposals with
  | [first; _; _; _; fifth] -> (
      Alcotest.(check string) "first author" "L." first.author;
      Alcotest.(check string)
        "first scientific_name" "Hibiscus rosa-sinensis L."
        first.scientific_name;
      Alcotest.(check (option string))
        "first family" (Some "Malvaceae") first.family;
      Alcotest.(check (list string))
        "first common names"
        ["Rose de Chine"; "Hibiscus"; "Hibiscus rose de Chine"]
        first.common_names;
      Alcotest.(check (option int)) "first gbif" (Some 3152559) first.gbif;
      Alcotest.(check int) "first images count" 6 (List.length first.images);
      Alcotest.(check (list (option organ)))
        "first images' organs"
        [
          Some Organ.Flower;
          Some Organ.Flower;
          Some Organ.Flower;
          Some Organ.Leaf;
          Some Organ.Leaf;
          Some Organ.Leaf;
        ]
        (List.map (fun (i : Plantnet.image) -> i.organ) first.images);
      (match first.images with
      | first_image :: _ ->
          Alcotest.(check string)
            "first image author" "Daniel Mardare" first_image.author;
          Alcotest.(check string)
            "first image licence" "cc-by-sa" first_image.licence;
          Alcotest.(check (option string))
            "first image citation" (Some "Daniel Mardare / Pl@ntNet, cc-by-sa")
            first_image.citation;
          Alcotest.(check bool)
            "first image small url" true
            (String.starts_with ~prefix:"https://bs.plantnet.org/image/s/"
               first_image.small);
          Alcotest.(check bool)
            "first image medium url" true
            (String.starts_with ~prefix:"https://bs.plantnet.org/image/m/"
               first_image.medium)
      | [] -> Alcotest.fail "first proposal has no images");
      Alcotest.(check int)
        "fifth proposal has 1 image" 1 (List.length fifth.images);
      match fifth.images with
      | [img] ->
          Alcotest.(check (option organ))
            "fifth image organ" (Some Organ.Leaf) img.organ
      | _ -> Alcotest.fail "fifth proposal: expected exactly one image")
  | _ -> Alcotest.fail "expected exactly 5 proposals");
  Alcotest.(check (list (option organ)))
    "detected"
    [Some Organ.Flower; Some Organ.Leaf]
    a.detected;
  Alcotest.(check (option string)) "flora" (Some "useful") a.flora;
  Alcotest.(check (option int)) "remaining" (Some 498) a.remaining

let decode_one_auto () =
  let a = decode one_auto in
  Alcotest.(check int) "5 proposals" 5 (List.length a.proposals);
  (match a.proposals with
  | first :: _ -> (
      Alcotest.(check (float 1e-9)) "first score" 0.44239 first.score;
      match first.images with
      | [_; _; _; fourth; _; _] ->
          Alcotest.(check (option organ))
            "fourth image organ (\"other\")" None fourth.organ
      | _ -> Alcotest.fail "expected 6 images")
  | [] -> Alcotest.fail "no proposals");
  (match a.proposals with
  | [_; second; _; fourth; _] ->
      Alcotest.(check (option int)) "fourth proposal gbif" None fourth.gbif;
      Alcotest.(check string) "fourth proposal author" "" fourth.author;
      Alcotest.(check string)
        "fourth proposal scientific_name" "Hibiscus spp." fourth.scientific_name;
      Alcotest.(check string)
        "second proposal scientific_name"
        "Hibiscus schizopetalus (Dyer) Hook.f." second.scientific_name
  | _ -> Alcotest.fail "expected exactly 5 proposals");
  Alcotest.(check (list (option organ)))
    "detected" [Some Organ.Flower] a.detected;
  Alcotest.(check (option int)) "remaining" (Some 499) a.remaining

let decode_projects_fr () =
  match Plantnet.decode_projects (Fixture.read projects_fr) with
  | Error e -> Alcotest.failf "decode_projects: %s" (Plantnet.error_to_string e)
  | Ok ps ->
      Alcotest.(check int) "75 projects" 75 (List.length ps);
      (match ps with
      | first :: _ ->
          Alcotest.(check string) "first id" "k-world-flora" first.id;
          Alcotest.(check string) "first title" "Flore mondiale" first.title
      | [] -> Alcotest.fail "no projects");
      Alcotest.(check bool)
        "contains k-southwestern-europe" true
        (List.exists
           (fun (p : Plantnet.project) ->
             String.equal p.id "k-southwestern-europe"
             && String.equal p.title "Europe du Sud-Ouest")
           ps);
      Alcotest.(check bool)
        "no project has id = all" true
        (not
           (List.exists
              (fun (p : Plantnet.project) -> String.equal p.id "all")
              ps))

let malformed_tests =
  [
    ( "decode_answer of non-JSON text",
      `Quick,
      fun () ->
        Alcotest.(check answer_result)
          "not JSON" (Error (Plantnet.Malformed "not JSON"))
          (Plantnet.decode_answer "not json") );
    ( "decode_answer of {} (no results)",
      `Quick,
      fun () ->
        Alcotest.(check answer_result)
          "results" (Error (Plantnet.Malformed "results"))
          (Plantnet.decode_answer "{}") );
    ( "decode_answer with results not a list",
      `Quick,
      fun () ->
        Alcotest.(check answer_result)
          "results" (Error (Plantnet.Malformed "results"))
          (Plantnet.decode_answer {|{"results": 3}|}) );
    ( "decode_answer with results = [] is Ok, no proposal, nothing detected",
      `Quick,
      fun () ->
        Alcotest.(check answer_result)
          "empty results"
          (Ok
             {
               Plantnet.proposals = [];
               detected = [];
               flora = None;
               remaining = None;
             })
          (Plantnet.decode_answer {|{"results": []}|}) );
    ( "decode_projects of {} (not a list)",
      `Quick,
      fun () ->
        Alcotest.(check projects_result)
          "projects" (Error (Plantnet.Malformed "projects"))
          (Plantnet.decode_projects "{}") );
    ( "decode_projects of non-JSON text",
      `Quick,
      fun () ->
        Alcotest.(check projects_result)
          "not JSON" (Error (Plantnet.Malformed "not JSON"))
          (Plantnet.decode_projects "not json") );
  ]

(* ---------- variants built with Yojson from two_flower_leaf_200 ---------- *)

let base_json () = Yojson.Safe.from_string (Fixture.read two_flower_leaf)

let with_first_result transform json =
  match json with
  | `Assoc fields ->
      let results =
        match List.assoc "results" fields with
        | `List (`Assoc rfields :: rest) ->
            `List (`Assoc (transform rfields) :: rest)
        | other -> other
      in
      `Assoc
        (List.map
           (fun (k, v) ->
             match String.equal k "results" with
             | true -> (k, results)
             | false -> (k, v))
           fields)
  | json -> json

let map_first_image f =
  with_first_result (fun fields ->
      List.map
        (fun (k, v) ->
          match (k, v) with
          | "images", `List (`Assoc ifields :: irest) ->
              (k, `List (`Assoc (f ifields) :: irest))
          | _ -> (k, v))
        fields)

let set_field k v fields =
  List.map
    (fun (key, value) ->
      match String.equal key k with true -> (key, v) | false -> (key, value))
    fields

let set_url_field key value =
  map_first_image
    (List.map (fun (k, v) ->
         match (k, v) with
         | "url", `Assoc ufields -> (k, `Assoc (set_field key value ufields))
         | _ -> (k, v)))

let decode_variant json = Plantnet.decode_answer (Yojson.Safe.to_string json)

let first_proposal_of json =
  match decode_variant json with
  | Ok a -> (
      match a.proposals with
      | first :: _ -> first
      | [] -> Alcotest.fail "no proposals")
  | Error e -> Alcotest.failf "decode_answer: %s" (Plantnet.error_to_string e)

let with_gbif value = with_first_result (set_field "gbif" value)

let gbif_variant_tests =
  let gbif_of json = (first_proposal_of json).gbif in
  [
    ( "gbif.id as a JSON integer decodes like a digit string, equal_answer holds",
      `Quick,
      fun () ->
        let as_int = with_gbif (`Assoc [("id", `Int 2927079)]) (base_json ()) in
        let as_string =
          with_gbif (`Assoc [("id", `String "2927079")]) (base_json ())
        in
        Alcotest.(check (option int)) "int form" (Some 2927079) (gbif_of as_int);
        Alcotest.(check (option int))
          "string form" (Some 2927079) (gbif_of as_string);
        match (decode_variant as_int, decode_variant as_string) with
        | Ok a, Ok b ->
            Alcotest.(check bool)
              "equal_answer" true
              (Plantnet.equal_answer a b)
        | _ -> Alcotest.fail "both should decode" );
    ( "a non-digit string gbif.id is None",
      `Quick,
      fun () ->
        Alcotest.(check (option int))
          "abc" None
          (gbif_of (with_gbif (`Assoc [("id", `String "abc")]) (base_json ())))
    );
    ( "a negative integer gbif.id is None",
      `Quick,
      fun () ->
        Alcotest.(check (option int))
          "-3" None
          (gbif_of (with_gbif (`Assoc [("id", `Int (-3))]) (base_json ()))) );
    ( "a zero gbif.id, as a string or an integer, is None",
      `Quick,
      fun () ->
        Alcotest.(check (option int))
          "\"0\"" None
          (gbif_of (with_gbif (`Assoc [("id", `String "0")]) (base_json ())));
        Alcotest.(check (option int))
          "0" None
          (gbif_of (with_gbif (`Assoc [("id", `Int 0)]) (base_json ()))) );
    ( "a float gbif.id is None",
      `Quick,
      fun () ->
        Alcotest.(check (option int))
          "2.5" None
          (gbif_of (with_gbif (`Assoc [("id", `Float 2.5)]) (base_json ()))) );
    ( "an overflowing digit string gbif.id is None",
      `Quick,
      fun () ->
        Alcotest.(check (option int))
          "overflow" None
          (gbif_of
             (with_gbif
                (`Assoc [("id", `String "99999999999999999999")])
                (base_json ()))) );
    ( "gbif removed is None",
      `Quick,
      fun () ->
        let json =
          with_first_result
            (fun fields ->
              List.filter (fun (k, _) -> not (String.equal k "gbif")) fields)
            (base_json ())
        in
        Alcotest.(check (option int)) "removed" None (gbif_of json) );
    ( "gbif = null is None",
      `Quick,
      fun () ->
        Alcotest.(check (option int))
          "null" None
          (gbif_of (with_gbif `Null (base_json ()))) );
  ]

let images_of json = (first_proposal_of json).images

(* The variants below spoil the first image of the first proposal: it alone
   is dropped, the other five are kept in Pl@ntNet's order. *)
let check_first_image_dropped json =
  match images_of (base_json ()) with
  | _ :: rest ->
      Alcotest.(check (list image))
        "the first image dropped, the other five kept in order" rest
        (images_of json)
  | [] -> Alcotest.fail "the recorded first proposal has no image"

let image_host_variant_tests =
  [
    ( "an image whose url.s is off bs.plantnet.org is dropped, the rest kept",
      `Quick,
      fun () ->
        let json =
          set_url_field "s" (`String "https://example.org/x.jpg") (base_json ())
        in
        check_first_image_dropped json );
    ( "an image whose url.m is plain http is dropped",
      `Quick,
      fun () ->
        let json =
          set_url_field "m" (`String "http://bs.plantnet.org/image/m/x")
            (base_json ())
        in
        check_first_image_dropped json );
    ( "a host-suffix lookalike (bs.plantnet.org.evil.com) is dropped",
      `Quick,
      fun () ->
        let json =
          set_url_field "m" (`String "https://bs.plantnet.org.evil.com/x")
            (base_json ())
        in
        check_first_image_dropped json );
    ( "an image with a blank author is dropped",
      `Quick,
      fun () ->
        let json =
          map_first_image (set_field "author" (`String "")) (base_json ())
        in
        check_first_image_dropped json );
    ( "an image without an author field at all is dropped",
      `Quick,
      fun () ->
        let json =
          map_first_image
            (fun fields ->
              List.filter (fun (k, _) -> not (String.equal k "author")) fields)
            (base_json ())
        in
        check_first_image_dropped json );
    ( "an image with a blank license is dropped",
      `Quick,
      fun () ->
        let json =
          map_first_image (set_field "license" (`String " ")) (base_json ())
        in
        check_first_image_dropped json );
    ( "an image without a license field at all is dropped",
      `Quick,
      fun () ->
        let json =
          map_first_image
            (fun fields ->
              List.filter (fun (k, _) -> not (String.equal k "license")) fields)
            (base_json ())
        in
        check_first_image_dropped json );
    ( "an image without url is dropped",
      `Quick,
      fun () ->
        let json =
          map_first_image
            (fun fields ->
              List.filter (fun (k, _) -> not (String.equal k "url")) fields)
            (base_json ())
        in
        check_first_image_dropped json );
  ]

let score_removed_test =
  ( "a result without a numeric score is dropped, the others kept in order",
    `Quick,
    fun () ->
      let json =
        with_first_result
          (fun fields ->
            List.filter (fun (k, _) -> not (String.equal k "score")) fields)
          (base_json ())
      in
      match decode_variant json with
      | Ok a ->
          Alcotest.(check int) "4 proposals left" 4 (List.length a.proposals);
          Alcotest.(check (list string))
            "remaining names, in order"
            [
              "Hibiscus schizopetalus";
              "Hibiscus moscheutos";
              "Hibiscus spp.";
              "Hibiscus acetosella";
            ]
            (List.map (fun (p : Plantnet.proposal) -> p.name) a.proposals)
      | Error e ->
          Alcotest.failf "decode_answer: %s" (Plantnet.error_to_string e) )

let map_species f =
  with_first_result
    (List.map (fun (k, v) ->
         match (k, v) with
         | "species", `Assoc sfields -> (k, `Assoc (f sfields))
         | _ -> (k, v)))

let without names fields =
  List.filter (fun (k, _) -> not (List.mem k names)) fields

let species_variant_tests =
  let first json = first_proposal_of (map_species json (base_json ())) in
  [
    ( "no scientificName: the name and the author joined",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "scientific_name" "Hibiscus rosa-sinensis L."
          (first (without ["scientificName"])).scientific_name );
    ( "a blank scientificName: the name and the author joined",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "scientific_name" "Hibiscus rosa-sinensis L."
          (first (set_field "scientificName" (`String " "))).scientific_name );
    ( "no scientificName nor authorship: the name alone, no author",
      `Quick,
      fun () ->
        let p =
          first (without ["scientificName"; "scientificNameAuthorship"])
        in
        Alcotest.(check string)
          "scientific_name" "Hibiscus rosa-sinensis" p.scientific_name;
        Alcotest.(check string) "author" "" p.author );
    ( "no family: None",
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "family" None (first (without ["family"])).family );
    ( "a family with a blank name: None",
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "family" None
          (first
             (set_field "family"
                (`Assoc [("scientificNameWithoutAuthor", `String " ")])))
            .family );
    ( "commonNames: blanks and non-strings dropped, order kept",
      `Quick,
      fun () ->
        Alcotest.(check (list string))
          "common_names"
          ["Rose de Chine"; "Hibiscus"]
          (first
             (set_field "commonNames"
                (`List
                   [
                     `String " ";
                     `Int 3;
                     `String " Rose de Chine ";
                     `Null;
                     `String "Hibiscus";
                   ])))
            .common_names );
    ( "a blank scientificNameWithoutAuthor drops that result, the others kept",
      `Quick,
      fun () ->
        match
          decode_variant
            (map_species
               (set_field "scientificNameWithoutAuthor" (`String " "))
               (base_json ()))
        with
        | Ok a ->
            Alcotest.(check (list string))
              "remaining names, in order"
              [
                "Hibiscus schizopetalus";
                "Hibiscus moscheutos";
                "Hibiscus spp.";
                "Hibiscus acetosella";
              ]
              (List.map (fun (p : Plantnet.proposal) -> p.name) a.proposals)
        | Error e ->
            Alcotest.failf "decode_answer: %s" (Plantnet.error_to_string e) );
  ]

let all_dropped_test =
  ( "a 200 whose every result has a string score is Malformed \"results\"",
    `Quick,
    fun () ->
      let json =
        match base_json () with
        | `Assoc fields ->
            `Assoc
              (List.map
                 (fun (k, v) ->
                   match (k, v) with
                   | "results", `List results ->
                       ( k,
                         `List
                           (List.map
                              (function
                                | `Assoc r ->
                                    `Assoc (set_field "score" (`String "0.5") r)
                                | r -> r)
                              results) )
                   | _ -> (k, v))
                 fields)
        | json -> json
      in
      Alcotest.(check answer_result)
        "all dropped" (Error (Plantnet.Malformed "results"))
        (decode_variant json) )

let map_top f = function `Assoc fields -> `Assoc (f fields) | json -> json

let map_predicted f =
  map_top
    (List.map (fun (k, v) ->
         match (k, v) with
         | "predictedOrgans", `List l -> (k, `List (f l))
         | _ -> (k, v)))

let detected_of json =
  match decode_variant json with
  | Ok a -> a.detected
  | Error e -> Alcotest.failf "decode_answer: %s" (Plantnet.error_to_string e)

let detected_variant_tests =
  [
    ( "predictedOrgans reordered: matched to the photos by image id",
      `Quick,
      fun () ->
        Alcotest.(check (list (option organ)))
          "detected"
          [Some Organ.Flower; Some Organ.Leaf]
          (detected_of (map_predicted List.rev (base_json ()))) );
    ( "a photo without its predictedOrgans element: None at its place",
      `Quick,
      fun () ->
        Alcotest.(check (list (option organ)))
          "detected" [None; Some Organ.Leaf]
          (detected_of
             (map_predicted
                (function _ :: rest -> rest | [] -> [])
                (base_json ()))) );
    ( "no query.images: predictedOrgans taken in its own order",
      `Quick,
      fun () ->
        Alcotest.(check (list (option organ)))
          "detected"
          [Some Organ.Leaf; Some Organ.Flower]
          (detected_of
             (map_predicted List.rev
                (map_top (without ["query"]) (base_json ())))) );
  ]

let predicted_organs_variant_test =
  ( "a predictedOrgans element with organ \"other\" decodes to None, alignment \
     kept",
    `Quick,
    fun () ->
      let json =
        match base_json () with
        | `Assoc fields ->
            `Assoc
              (List.map
                 (fun (k, v) ->
                   match (k, v) with
                   | "predictedOrgans", `List (`Assoc pfields :: rest) ->
                       ( k,
                         `List
                           (`Assoc (set_field "organ" (`String "other") pfields)
                           :: rest) )
                   | _ -> (k, v))
                 fields)
        | json -> json
      in
      match decode_variant json with
      | Ok a ->
          Alcotest.(check (list (option organ)))
            "detected" [None; Some Organ.Leaf] a.detected
      | Error e ->
          Alcotest.failf "decode_answer: %s" (Plantnet.error_to_string e) )

(* ---------- on_image_host ---------- *)

let on_image_host_tests =
  let true_cases =
    ["https://bs.plantnet.org/image/s/abc"; "https://bs.plantnet.org/\xc3\xa9"]
  in
  let false_cases =
    [
      "https://bs.plantnet.org/";
      "http://bs.plantnet.org/a";
      "https://bs.plantnet.org.evil.com/a";
      "https://x@bs.plantnet.org/a";
      "https://bs.plantnet.org:443/a";
      "https://bs.plantnet.org/a b";
      "https://bs.plantnet.org/a\"b";
      "https://bs.plantnet.org/a<b";
      "https://bs.plantnet.org/a>b";
      "https://bs.plantnet.org/a\\b";
      "https://bs.plantnet.org/a\tb";
      "https://bs.plantnet.org/a\nb";
      "https://bs.plantnet.org/a\x00b";
      "https://bs.plantnet.org/a\x7fb";
    ]
  in
  List.map
    (fun url ->
      ( Printf.sprintf "on_image_host %S is true" url,
        `Quick,
        fun () -> Alcotest.(check bool) url true (Plantnet.on_image_host url) ))
    true_cases
  @ List.map
      (fun url ->
        ( Printf.sprintf "on_image_host %S is false" url,
          `Quick,
          fun () -> Alcotest.(check bool) url false (Plantnet.on_image_host url)
        ))
      false_cases

(* ---------- error_of_answer ---------- *)

let error_of_answer_tests =
  [
    ( "404 on identify: not a plant",
      `Quick,
      fun () ->
        Alcotest.(check error)
          "No_plant" Plantnet.No_plant
          (Plantnet.error_of_answer ~route:Plantnet.Identify ~status:404
             ~body:(Fixture.read "plantnet_identify_not_plant_404.json")) );
    ( "404 on identify with no-reject: still not a plant",
      `Quick,
      fun () ->
        Alcotest.(check error)
          "No_plant" Plantnet.No_plant
          (Plantnet.error_of_answer ~route:Plantnet.Identify ~status:404
             ~body:
               (Fixture.read "plantnet_identify_not_plant_no_reject_404.json"))
    );
    ( "401: key refused",
      `Quick,
      fun () ->
        Alcotest.(check error)
          "Key_refused" Plantnet.Key_refused
          (Plantnet.error_of_answer ~route:Plantnet.Identify ~status:401
             ~body:(Fixture.read "plantnet_identify_invalid_key_401.json")) );
    ( "403 origin refused on Projects: key not exposed",
      `Quick,
      fun () ->
        Alcotest.(check error)
          "Key_not_exposed" Plantnet.Key_not_exposed
          (Plantnet.error_of_answer ~route:Plantnet.Projects ~status:403
             ~body:(Fixture.read "plantnet_projects_origin_refused_403.json"))
    );
    ( "403 origin refused on Identify: key not exposed too",
      `Quick,
      fun () ->
        Alcotest.(check error)
          "Key_not_exposed" Plantnet.Key_not_exposed
          (Plantnet.error_of_answer ~route:Plantnet.Identify ~status:403
             ~body:(Fixture.read "plantnet_projects_origin_refused_403.json"))
    );
    ( "403 no origin: Refused_request 403",
      `Quick,
      fun () ->
        Alcotest.(check error)
          "Refused_request 403" (Plantnet.Refused_request 403)
          (Plantnet.error_of_answer ~route:Plantnet.Projects ~status:403
             ~body:(Fixture.read "plantnet_projects_no_origin_403.json")) );
    ( "403 empty body: Refused_request 403",
      `Quick,
      fun () ->
        Alcotest.(check error)
          "Refused_request 403" (Plantnet.Refused_request 403)
          (Plantnet.error_of_answer ~route:Plantnet.Identify ~status:403
             ~body:"") );
    ( "429 empty body: quota used up",
      `Quick,
      fun () ->
        Alcotest.(check error)
          "Quota_used_up" Plantnet.Quota_used_up
          (Plantnet.error_of_answer ~route:Plantnet.Identify ~status:429
             ~body:"") );
    ( "400, 413, 414, 415: Refused_request <status>",
      `Quick,
      fun () ->
        List.iter
          (fun status ->
            Alcotest.(check error)
              (Printf.sprintf "Refused_request %d" status)
              (Plantnet.Refused_request status)
              (Plantnet.error_of_answer ~route:Plantnet.Identify ~status
                 ~body:""))
          [400; 413; 414; 415; 600] );
    ( "500 and 503: Unreachable (Server <status>)",
      `Quick,
      fun () ->
        List.iter
          (fun status ->
            Alcotest.(check error)
              (Printf.sprintf "Unreachable (Server %d)" status)
              (Plantnet.Unreachable (Plantnet.Server status))
              (Plantnet.error_of_answer ~route:Plantnet.Identify ~status
                 ~body:""))
          [500; 503; 599] );
    ( "404 on Projects: Refused_request 404",
      `Quick,
      fun () ->
        Alcotest.(check error)
          "Refused_request 404" (Plantnet.Refused_request 404)
          (Plantnet.error_of_answer ~route:Plantnet.Projects ~status:404
             ~body:"") );
    ( "302, 100 and 204: Refused_request <status>",
      `Quick,
      fun () ->
        List.iter
          (fun status ->
            Alcotest.(check error)
              (Printf.sprintf "Refused_request %d" status)
              (Plantnet.Refused_request status)
              (Plantnet.error_of_answer ~route:Plantnet.Identify ~status
                 ~body:""))
          [302; 100; 204] );
  ]

let error_of_failure_tests =
  [
    ( "Timeout -> Unreachable Timeout",
      `Quick,
      fun () ->
        Alcotest.(check error)
          "Unreachable Timeout" (Plantnet.Unreachable Plantnet.Timeout)
          (Plantnet.error_of_failure Transport.Timeout) );
    ( "Network m -> Unreachable Network, the text dropped",
      `Quick,
      fun () ->
        Alcotest.(check error)
          "Unreachable Network" (Plantnet.Unreachable Plantnet.Network)
          (Plantnet.error_of_failure
             (Transport.Network "TypeError: Failed to fetch")) );
  ]

let error_to_string_tests =
  let texts =
    [
      (Plantnet.No_key, "no key");
      (Plantnet.No_photo, "no photo");
      (Plantnet.No_plant, "no plant");
      (Plantnet.Key_refused, "key refused");
      (Plantnet.Key_not_exposed, "key not exposed for the app");
      (Plantnet.Quota_used_up, "quota used up");
      (Plantnet.Refused_request 413, "refused request (HTTP 413)");
      (Plantnet.Unreachable Plantnet.Timeout, "unreachable: timeout");
      (Plantnet.Unreachable Plantnet.Network, "unreachable: network failure");
      (Plantnet.Unreachable (Plantnet.Server 503), "unreachable: HTTP 503");
      (Plantnet.Malformed "results", "malformed answer: results");
    ]
  in
  List.map
    (fun (e, expected) ->
      ( Printf.sprintf "error_to_string is %S, without api-key nor https://"
          expected,
        `Quick,
        fun () ->
          let s = Plantnet.error_to_string e in
          Alcotest.(check string) "error_to_string" expected s;
          Alcotest.(check bool)
            "no api-key" false
            (Text.contains ~sub:"api-key" s);
          Alcotest.(check bool)
            "no https://" false
            (Text.contains ~sub:"https://" s) ))
    texts

(* projects_fr_200 with its first entry's id blanked, and its second's title
   removed: both are dropped, the rest kept in order. *)
let projects_entry_dropped_test =
  ( "a flora without a non-blank id or title is dropped, the rest kept",
    `Quick,
    fun () ->
      let spoil = function
        | `List (`Assoc first :: `Assoc second :: rest) ->
            `List
              (`Assoc (set_field "id" (`String "  ") first)
              :: `Assoc
                   (List.filter
                      (fun (k, _) -> not (String.equal k "title"))
                      second)
              :: rest)
        | json -> json
      in
      let recorded = Fixture.read projects_fr in
      let spoilt =
        Yojson.Safe.to_string (spoil (Yojson.Safe.from_string recorded))
      in
      match
        (Plantnet.decode_projects recorded, Plantnet.decode_projects spoilt)
      with
      | Ok (_ :: _ :: rest), Ok kept ->
          Alcotest.(check int) "73 projects" 73 (List.length kept);
          Alcotest.(check projects) "the first two dropped" rest kept
      | _ -> Alcotest.fail "both bodies should decode, the recorded one to 75"
  )

let suites =
  [
    ("plantnet identify_url", identify_url_tests);
    ("plantnet projects_url", projects_url_tests);
    ("plantnet identify_request", identify_request_tests);
    ("plantnet projects_request", projects_request_tests);
    ( "plantnet decode_answer (fixtures)",
      [
        ( "two_flower_leaf_200: proposals, images, detected, flora, remaining",
          `Quick,
          decode_two_flower_leaf );
        ( "one_auto_200: proposals, images, detected, remaining",
          `Quick,
          decode_one_auto );
      ] );
    ( "plantnet decode_projects",
      [
        ("projects_fr_200: 75 floras", `Quick, decode_projects_fr);
        projects_entry_dropped_test;
      ] );
    ("plantnet decode, malformed bodies", malformed_tests);
    ("plantnet gbif.id variants", gbif_variant_tests);
    ("plantnet related image host variants", image_host_variant_tests);
    ( "plantnet proposal/predictedOrgans variants",
      [score_removed_test; all_dropped_test; predicted_organs_variant_test] );
    ("plantnet species variants", species_variant_tests);
    ("plantnet detected variants", detected_variant_tests);
    ("plantnet on_image_host", on_image_host_tests);
    ("plantnet error_of_answer", error_of_answer_tests);
    ("plantnet error_of_failure", error_of_failure_tests);
    ("plantnet error_to_string", error_to_string_tests);
  ]
