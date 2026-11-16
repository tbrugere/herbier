(* Checks on test/fixtures/plantnet_*.json as recorded: the set, the JSON
   shape, the facts docs/notes/plantnet-webview.md reports, and that no
   api-key parameter or request URL leaked into them. *)

module Fixture = Herbier_test_support.Fixture
module Text = Herbier_test_support.Text

let fixed_names =
  [
    "plantnet_projects_fr_200.json";
    "plantnet_identify_invalid_key_401.json";
    "plantnet_identify_one_auto_200.json";
    "plantnet_identify_two_flower_leaf_200.json";
    "plantnet_identify_not_plant_404.json";
  ]

let variable_prefixes =
  [
    "plantnet_projects_origin_refused_";
    "plantnet_projects_no_origin_";
    "plantnet_identify_not_plant_no_reject_";
  ]

let is_digit c = c >= '0' && c <= '9'

(* The status embedded right before ".json" when [name] ends in
   "_DDD.json"; [None] when it does not have that shape. *)
let status_suffix name =
  let n = String.length name in
  if n >= 9 && String.ends_with ~suffix:".json" name && name.[n - 9] = '_' then
    let status = String.sub name (n - 8) 3 in
    if String.for_all is_digit status then Some status else None
  else None

let parse name =
  match Yojson.Safe.from_string (Fixture.read name) with
  | json -> json
  | exception Yojson.Json_error msg ->
      Alcotest.failf "%s: invalid JSON (%s)" name msg

(* The one file recorded under [prefix]. *)
let the_one prefix =
  match Fixture.names ~prefix with
  | [name] -> name
  | names ->
      Alcotest.failf "%s*: expected one file, got [%s]" prefix
        (String.concat "; " names)

let status_of name =
  match status_suffix name with
  | Some status -> status
  | None -> Alcotest.failf "%s: unreadable status" name

(* ---------- the set ---------- *)

let the_set () =
  let all = Fixture.names ~prefix:"plantnet_" in
  List.iter
    (fun name ->
      match status_suffix name with
      | Some _ -> ()
      | None ->
          Alcotest.failf "%s does not match plantnet_<...>_<3 digits>.json" name)
    all;
  List.iter
    (fun name ->
      Alcotest.(check bool) (name ^ " is recorded") true (List.mem name all))
    fixed_names;
  List.iter (fun prefix -> ignore (the_one prefix)) variable_prefixes;
  let origin_refused =
    status_of (the_one "plantnet_projects_origin_refused_")
  in
  Alcotest.(check bool)
    "origin_refused: status starts with 4" true
    (origin_refused.[0] = '4');
  (match status_of (the_one "plantnet_identify_not_plant_no_reject_") with
  | "200" | "404" -> ()
  | status ->
      Alcotest.failf "no_reject: status %s is neither 200 nor 404" status);
  if List.length all <> 8 then
    Alcotest.failf "expected 8 plantnet_* fixtures, got [%s]"
      (String.concat "; " all)

(* ---------- JSON ---------- *)

let all_json () =
  List.iter
    (fun name -> ignore (parse name))
    (Fixture.names ~prefix:"plantnet_")

(* ---------- no api-key parameter ---------- *)

let api_host = "my-api.plantnet.org/v2/"

(* True when some [api_host] in [body] is followed by a query string: a '?'
   before the next '"', space or end of [body]. *)
let echoes_request_url body =
  let n = String.length body and h = String.length api_host in
  let rec query_follows i =
    match i < n with
    | false -> false
    | true -> (
        match body.[i] with
        | '?' -> true
        | '"' | ' ' -> false
        | _ -> query_follows (i + 1))
  in
  let rec from i =
    match i + h <= n with
    | false -> false
    | true -> (
        match String.equal (String.sub body i h) api_host with
        | true -> query_follows (i + h) || from (i + 1)
        | false -> from (i + 1))
  in
  from 0

let no_key () =
  List.iter
    (fun name ->
      let body = Fixture.read name in
      Alcotest.(check bool)
        (name ^ ": no api-key= ") true
        (not (Text.contains ~sub:"api-key=" body));
      Alcotest.(check bool)
        (name ^ ": no api-key\"") true
        (not (Text.contains ~sub:"api-key\"" body));
      Alcotest.(check bool)
        (name ^ ": no apiKey") true
        (not (Text.contains ~sub:"apiKey" body));
      Alcotest.(check bool)
        (name ^ ": no echoed request URL")
        true
        (not (echoes_request_url body)))
    (Fixture.names ~prefix:"plantnet_")

(* ---------- identify 200s ---------- *)

let non_increasing scores =
  let rec go = function
    | a :: (b :: _ as rest) -> a >= b && go rest
    | _ -> true
  in
  go scores

let check_identify_200 name ~organs ~images_count =
  let open Yojson.Safe.Util in
  let json = parse name in
  let query = member "query" json in
  Alcotest.(check (list string))
    (name ^ ": query.organs") organs
    (member "organs" query |> to_list |> List.map to_string);
  Alcotest.(check bool)
    (name ^ ": query.includeRelatedImages")
    true
    (member "includeRelatedImages" query |> to_bool);
  Alcotest.(check string)
    (name ^ ": query.project") "all"
    (member "project" query |> to_string);
  Alcotest.(check bool)
    (name ^ ": query.noReject")
    false
    (member "noReject" query |> to_bool);
  Alcotest.(check int)
    (name ^ ": query.images count")
    images_count
    (member "images" query |> to_list |> List.length);
  Alcotest.(check string)
    (name ^ ": language") "fr"
    (member "language" json |> to_string);
  (match member "remainingIdentificationRequests" json with
  | `Int _ -> ()
  | _ -> Alcotest.failf "%s: remainingIdentificationRequests is not an int" name);
  let predicted = member "predictedOrgans" json |> to_list in
  Alcotest.(check int)
    (name ^ ": predictedOrgans length")
    images_count (List.length predicted);
  let results = member "results" json |> to_list in
  let n = List.length results in
  Alcotest.(check bool)
    (name ^ ": results has 1 to 5 elements")
    true
    (n >= 1 && n <= 5);
  let scores =
    List.map
      (fun r ->
        match member "score" r with
        | `Float f -> f
        | `Int i -> float_of_int i
        | _ -> Alcotest.failf "%s: a result's score is not a number" name)
      results
  in
  List.iter
    (fun s ->
      Alcotest.(check bool)
        (name ^ ": a score is in [0, 1]")
        true
        (s >= 0.0 && s <= 1.0))
    scores;
  Alcotest.(check bool)
    (name ^ ": scores do not increase along the list")
    true (non_increasing scores);
  List.iter
    (fun r ->
      let species = member "species" r in
      (match member "scientificNameWithoutAuthor" species with
      | `String _ -> ()
      | _ ->
          Alcotest.failf
            "%s: a result's species.scientificNameWithoutAuthor is not a string"
            name);
      (match
         member "family" species |> member "scientificNameWithoutAuthor"
       with
      | `String _ -> ()
      | _ ->
          Alcotest.failf
            "%s: a result's species.family.scientificNameWithoutAuthor is not \
             a string"
            name);
      (match member "commonNames" species with
      | `List (_ :: _ as names) ->
          List.iter
            (function
              | `String _ -> ()
              | _ -> Alcotest.failf "%s: a common name is not a string" name)
            names
      | _ ->
          Alcotest.failf
            "%s: a result's species.commonNames is not a non-empty list" name);
      match member "gbif" r with
      | `Null -> ()
      | `Assoc _ as gbif -> (
          match member "id" gbif with
          | `String _ -> ()
          | _ -> Alcotest.failf "%s: a result's gbif.id is not a string" name)
      | _ ->
          Alcotest.failf "%s: a result's gbif is neither null nor an object"
            name)
    results;
  json

let one_auto_200 () =
  let json =
    check_identify_200 "plantnet_identify_one_auto_200.json" ~organs:["auto"]
      ~images_count:1
  in
  let open Yojson.Safe.Util in
  Alcotest.(check bool)
    "one_auto_200: a genus-level result has gbif null" true
    (List.exists
       (fun r -> member "gbif" r = `Null)
       (member "results" json |> to_list))

let two_flower_leaf_200 () =
  let json =
    check_identify_200 "plantnet_identify_two_flower_leaf_200.json"
      ~organs:["flower"; "leaf"] ~images_count:2
  in
  let open Yojson.Safe.Util in
  Alcotest.(check (list string))
    "two_flower_leaf_200: predictedOrgans echo the organs sent"
    ["flower"; "leaf"]
    (member "predictedOrgans" json
    |> to_list
    |> List.map (fun p -> member "organ" p |> to_string))

(* ---------- related images ---------- *)

let check_related_images name =
  let open Yojson.Safe.Util in
  let json = parse name in
  let results = member "results" json |> to_list in
  let has_images =
    List.exists
      (fun r ->
        match member "images" r with `List (_ :: _) -> true | _ -> false)
      results
  in
  Alcotest.(check bool)
    (name ^ ": at least one result has related images")
    true has_images;
  List.iter
    (fun r ->
      match member "images" r with
      | `List imgs ->
          Alcotest.(check bool)
            (name ^ ": at most six related images per result")
            true
            (List.length imgs <= 6);
          List.iter
            (fun img ->
              let url =
                match member "url" img with
                | `Assoc _ as url -> url
                | _ -> Alcotest.failf "%s: an image url is not an object" name
              in
              List.iter
                (fun key ->
                  match member key url with
                  | `String s ->
                      Alcotest.(check bool)
                        (Printf.sprintf
                           "%s: image url.%s starts with \
                            https://bs.plantnet.org/"
                           name key)
                        true
                        (String.starts_with ~prefix:"https://bs.plantnet.org/" s)
                  | `Null -> ()
                  | _ ->
                      Alcotest.failf "%s: image url.%s is not a string" name key)
                ["s"; "m"])
            imgs
      | _ -> ())
    results

let related_images () =
  check_related_images "plantnet_identify_one_auto_200.json";
  check_related_images "plantnet_identify_two_flower_leaf_200.json"

(* ---------- refusals ---------- *)

let message name =
  match Yojson.Safe.Util.member "message" (parse name) with
  | `String msg -> msg
  | _ -> Alcotest.failf "%s: message is not a string" name

let not_a_plant () =
  Alcotest.(check string)
    "not_plant_404: message" "Species not found"
    (message "plantnet_identify_not_plant_404.json")

(* A 404 with no-reject is the same answer as without it. *)
let no_reject () =
  let name = the_one "plantnet_identify_not_plant_no_reject_" in
  match status_of name with
  | "404" ->
      Alcotest.(check Herbier_test_support.Testable.yojson)
        "no_reject 404 = not_plant 404"
        (parse "plantnet_identify_not_plant_404.json")
        (parse name)
  | _ -> ()

let origin_refused () =
  Alcotest.(check string)
    "origin_refused: message" "CORS error: Origin not allowed"
    (message (the_one "plantnet_projects_origin_refused_"))

let no_origin () =
  Alcotest.(check string)
    "no_origin: message" "error: remote IP not allowed"
    (message (the_one "plantnet_projects_no_origin_"))

(* Every body with a statusCode agrees with the status in its name. *)
let status_codes () =
  List.iter
    (fun name ->
      match Yojson.Safe.Util.member "statusCode" (parse name) with
      | `Int code ->
          Alcotest.(check int)
            (name ^ ": statusCode")
            (int_of_string (status_of name))
            code
      | _ -> ())
    (List.filter
       (fun name -> match parse name with `Assoc _ -> true | _ -> false)
       (Fixture.names ~prefix:"plantnet_"))

let invalid_key () =
  Alcotest.(check string)
    "invalid_key_401: message" "Bad token"
    (message "plantnet_identify_invalid_key_401.json")

(* ---------- floras ---------- *)

let floras () =
  let open Yojson.Safe.Util in
  let json = parse "plantnet_projects_fr_200.json" in
  let projects = to_list json in
  Alcotest.(check bool) "floras: non-empty" true (projects <> []);
  List.iter
    (fun p ->
      match (member "id" p, member "title" p) with
      | `String _, `String _ -> ()
      | _ -> Alcotest.fail "floras: a project is missing a string id or title")
    projects;
  let ids = List.map (fun p -> member "id" p |> to_string) projects in
  Alcotest.(check bool)
    "floras: k-southwestern-europe is listed" true
    (List.mem "k-southwestern-europe" ids);
  Alcotest.(check bool)
    "floras: no project has id = all" true
    (not (List.mem "all" ids))

let case name f = (name, `Quick, f)

let suite =
  ( "plantnet fixtures",
    [
      case
        "the set: eight plantnet_* fixtures, named plantnet_<...>_<status>.json"
        the_set;
      case "every fixture parses as JSON" all_json;
      case "no fixture contains an api-key parameter or an echoed request URL"
        no_key;
      case "one photo, 200: query, predictedOrgans and results shape"
        one_auto_200;
      case "two photos, 200: query, predictedOrgans and results shape"
        two_flower_leaf_200;
      case "related images: url.s and url.m start with https://bs.plantnet.org/"
        related_images;
      case "not a plant: the 404 says \"Species not found\"" not_a_plant;
      case "no-reject on a non-plant: the same 404" no_reject;
      case "another Origin: 403 \"CORS error: Origin not allowed\""
        origin_refused;
      case "no Origin: 403 \"error: remote IP not allowed\"" no_origin;
      case "statusCode agrees with the status in the name" status_codes;
      case "invalid key: \"Bad token\"" invalid_key;
      case "floras: k-southwestern-europe is listed, \"all\" is not" floras;
    ] )
