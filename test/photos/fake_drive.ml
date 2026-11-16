(* An in-memory Drive for start_session runs between which a test moves,
   renames, trashes or deletes folders. It recognises each request by
   comparing it with Drive's own request builders ([Drive.equal_request]),
   never by parsing the query string, so a move or a rename changes only what
   [net] answers about a folder, never how a request is matched. *)

module Drive = Herbier_photos.Drive
module Fixture = Herbier_test_support.Fixture

type folder = {
  id : string;
  name : string;
  parent : Drive.parent;
  trashed : bool;
}

type t = {
  mutable folders : folder list; (* creation order, oldest first *)
  mutable sessions : string list; (* parent folder id of each create_session *)
  mutable counter : int;
}

let create () = {folders = []; sessions = []; counter = 0}

let next_id t prefix =
  t.counter <- t.counter + 1;
  prefix ^ string_of_int t.counter

let add_folder t ~name ~parent =
  let id = next_id t "F" in
  t.folders <- t.folders @ [{id; name; parent; trashed = false}];
  id

let replace t ~id f =
  t.folders <-
    List.map
      (fun g -> match g.id = id with true -> f g | false -> g)
      t.folders

let move t ~id ~parent = replace t ~id (fun f -> {f with parent})
let rename t ~id ~name = replace t ~id (fun f -> {f with name})
let trash t ~id = replace t ~id (fun f -> {f with trashed = true})
let delete t ~id = t.folders <- List.filter (fun f -> f.id <> id) t.folders
let folders t = t.folders
let sessions t = t.sessions

let answer ?(status = 200) ?(headers = []) body : Drive.response =
  Drive.Answer {status; headers; body}

let field fields name what =
  match List.assoc_opt name fields with
  | Some v -> v
  | None -> Alcotest.failf "fake_drive: %s: no %s field" what name

let string_field fields name what =
  match field fields name what with
  | `String s -> s
  | _ -> Alcotest.failf "fake_drive: %s: %s is not a string" what name

let parent_of_parents fields what =
  match field fields "parents" what with
  | `List [`String "root"] -> Drive.Root
  | `List [`String id] -> Drive.Folder id
  | _ -> Alcotest.failf "fake_drive: %s: parents is not a one-element list" what

let files_json ids =
  Yojson.Safe.to_string
    (`Assoc
       [("files", `List (List.map (fun id -> `Assoc [("id", `String id)]) ids))])

let not_found_404 =
  match Fixture.exists "drive_files_get_unknown_404.json" with
  | true -> fun () -> Fixture.read "drive_files_get_unknown_404.json"
  | false ->
      fun () ->
        {|{"error":{"code":404,"message":"File not found.","errors":[{"reason":"notFound"}]}}|}

let handle_get t (req : Drive.request) =
  let folder_matches =
    List.filter
      (fun f ->
        (not f.trashed)
        && Drive.equal_request req
             (Drive.find_folder ~name:f.name ~parent:f.parent))
      t.folders
  in
  let trashed_match () =
    List.find_opt
      (fun f -> Drive.equal_request req (Drive.get_trashed ~file_id:f.id))
      t.folders
  in
  match folder_matches with
  | _ :: _ -> answer (files_json (List.map (fun f -> f.id) folder_matches))
  | [] -> (
      match trashed_match () with
      | Some f ->
          answer (Printf.sprintf {|{"id":"%s","trashed":%b}|} f.id f.trashed)
      | None -> (
          match () with
          | () when String.starts_with ~prefix:(Drive.api ^ "/") req.url ->
              answer ~status:404 (not_found_404 ())
          (* A folder lookup by a name nothing has, or the appProperties lookup
             of a photo never uploaded. *)
          | () when String.starts_with ~prefix:(Drive.api ^ "?q=") req.url ->
              answer (files_json [])
          | () -> Alcotest.failf "fake_drive: unrecognised GET %s" req.url))

let json_body what (req : Drive.request) =
  match req.body with
  | Drive.Json s -> (
      match Yojson.Safe.from_string s with
      | `Assoc fields -> fields
      | _ -> Alcotest.failf "fake_drive: %s: body is not an object" what)
  | Drive.Empty | Drive.Multipart _ ->
      Alcotest.failf "fake_drive: %s: body is not Json" what

let handle_create_folder t req =
  let fields = json_body "create_folder" req in
  let name = string_field fields "name" "create_folder" in
  let parent = parent_of_parents fields "create_folder" in
  let id = add_folder t ~name ~parent in
  answer (Printf.sprintf {|{"id":"%s"}|} id)

let handle_create_session t req =
  let fields = json_body "create_session" req in
  match parent_of_parents fields "create_session" with
  | Drive.Root -> Alcotest.fail "fake_drive: create_session: parent is root"
  | Drive.Folder parent ->
      t.sessions <- t.sessions @ [parent];
      let upload_id = next_id t "fake" in
      answer
        ~headers:
          [
            ( "location",
              Drive.upload_api ^ "?uploadType=resumable&upload_id=" ^ upload_id
            );
          ]
        "{}"

let net t (req : Drive.request) : Drive.response =
  match req.meth with
  | `GET -> handle_get t req
  | `POST -> (
      match () with
      | () when req.url = Drive.api ^ "?fields=id" -> handle_create_folder t req
      | ()
        when req.url
             = Drive.upload_api ^ "?uploadType=resumable&fields=id,webViewLink"
        ->
          handle_create_session t req
      | () -> Alcotest.failf "fake_drive: unrecognised POST %s" req.url)
