module Photo_id = Herbier_domain.Ids.Photo_id
module Plant = Herbier_domain.Plant
module Text = Herbier_domain.Text
module Json = Herbier_net.Json
module Url = Herbier_net.Url

type body =
  | Empty
  | Json of string
  | Multipart of {boundary : string; prefix : string; suffix : string}
[@@deriving eq]

type request = {meth : [`GET | `POST]; url : string; body : body}
[@@deriving eq]

let json_type = "application/json; charset=UTF-8"

let content_type = function
  | Empty -> None
  | Json _ -> Some json_type
  | Multipart {boundary; _} -> Some ("multipart/related; boundary=" ^ boundary)

type response =
  | Answer of {status : int; headers : (string * string) list; body : string}
  | Unreachable of string

type error =
  | Unauthorized
  | Api_disabled
  | Scope_missing
  | Quota_full
  | Rate_limited
  | Not_found
  | Server of int
  | Http of {status : int; reason : string option; message : string option}
  | Malformed of string
  | Network of string
[@@deriving eq]

let error_to_string = function
  | Unauthorized -> "unauthorized"
  | Api_disabled -> "Drive API disabled"
  | Scope_missing -> "Drive scope missing"
  | Quota_full -> "Drive storage full"
  | Rate_limited -> "rate limited"
  | Not_found -> "not found"
  | Server status -> Printf.sprintf "server error HTTP %d" status
  | Http {status; reason; message} ->
      Printf.sprintf "HTTP %d%s%s" status
        (Option.fold ~none:"" ~some:(fun r -> " " ^ r) reason)
        (Option.fold ~none:"" ~some:(fun m -> ": " ^ m) message)
  | Malformed what -> "malformed answer: " ^ what
  | Network m -> "network: " ^ m

let pp_error ppf e = Format.pp_print_string ppf (error_to_string e)

type scope = Account | This_file [@@deriving eq]

let error_scope = function
  | Unauthorized | Api_disabled | Scope_missing | Quota_full | Rate_limited
  | Server _ | Network _ ->
      Account
  | Not_found | Http _ | Malformed _ -> This_file

let list_member name json =
  match Json.member name json with Some (`List l) -> l | _ -> []

(* Google's error body: errors[0].reason, the message, and the reasons of the
   google.rpc.ErrorInfo details. *)
type google_error = {
  reason : string option;
  message : string option;
  details : string list;
}

let error_info detail =
  match Json.string_member "@type" detail with
  | Some ty when String.ends_with ~suffix:"google.rpc.ErrorInfo" ty ->
      Json.string_member "reason" detail
  | Some _ | None -> None

let google_error body =
  let error =
    match Json.parse body with
    | Ok json -> Json.member "error" json
    | Error (_ : string) -> None
  in
  match error with
  | None -> {reason = None; message = None; details = []}
  | Some error ->
      {
        reason =
          (match list_member "errors" error with
          | first :: _ -> Json.string_member "reason" first
          | [] -> None);
        message = Json.string_member "message" error;
        details = List.filter_map error_info (list_member "details" error);
      }

let forbidden ~status {reason; message; details} =
  let has r = Option.equal String.equal reason (Some r) || List.mem r details in
  match () with
  | () when has "accessNotConfigured" || has "SERVICE_DISABLED" -> Api_disabled
  | ()
    when has "insufficientPermissions" || has "ACCESS_TOKEN_SCOPE_INSUFFICIENT"
    ->
      Scope_missing
  | () when has "storageQuotaExceeded" -> Quota_full
  | () when has "userRateLimitExceeded" || has "rateLimitExceeded" ->
      Rate_limited
  | () -> Http {status; reason; message}

let error_of_answer ~status ~body =
  match status with
  | 401 -> Unauthorized
  | 429 -> Rate_limited
  | 404 -> Not_found
  | n when 500 <= n && n <= 599 -> Server n
  | 403 -> forbidden ~status (google_error body)
  | _ ->
      let {reason; message; _} = google_error body in
      Http {status; reason; message}

(* Names *)

let root_folder = "Herbier"
let unidentified_folder = "À identifier"

let species_folder = function
  | None -> unidentified_folder
  | Some (plant : Plant.t) -> (
      match
        ( Option.bind plant.scientific_name Text.non_blank,
          Text.non_blank plant.display_name )
      with
      | Some name, _ | None, Some name -> name
      | None, None -> unidentified_folder)

let extension = function
  | "image/jpeg" -> ".jpg"
  | "image/png" -> ".png"
  | "image/webp" -> ".webp"
  | "image/heic" -> ".heic"
  | _ -> ""

let file_name ~taken_at ~offset_s ~id ~mime =
  let (y, mo, d), ((h, mi, s), _) =
    Ptime.to_date_time ~tz_offset_s:offset_s taken_at
  in
  let id = Photo_id.to_string id in
  Printf.sprintf "%04d-%02d-%02d %02d.%02d.%02d %s%s" y mo d h mi s
    (String.sub id (String.length id - 8) 8)
    (extension mime)

(* Requests *)

let api = "https://www.googleapis.com/drive/v3/files"
let upload_api = "https://www.googleapis.com/upload/drive/v3/files"

let quote s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '\'';
  String.iter
    (function
      | ('\'' | '\\') as c ->
          Buffer.add_char b '\\';
          Buffer.add_char b c
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '\'';
  Buffer.contents b

let folder_mime = "application/vnd.google-apps.folder"

type parent = Root | Folder of string [@@deriving eq]

let parent_id = function Root -> "root" | Folder id -> id

let list_files ~q ~fields =
  {
    meth = `GET;
    url =
      Printf.sprintf
        "%s?q=%s&fields=%s&orderBy=createdTime&pageSize=10&spaces=drive" api
        (Url.encode q) (Url.encode fields);
    body = Empty;
  }

let find_folder ~name ~parent =
  list_files ~fields:"files(id)"
    ~q:
      (Printf.sprintf
         "name = %s and mimeType = %s and %s in parents and trashed = false"
         (quote name) (quote folder_mime)
         (quote (parent_id parent)))

let create_folder ~name ~parent =
  {
    meth = `POST;
    url = api ^ "?fields=id";
    body =
      Json
        (Yojson.Safe.to_string
           (`Assoc
              [
                ("name", `String name);
                ("mimeType", `String folder_mime);
                ("parents", `List [`String (parent_id parent)]);
              ]));
  }

let photo_id_key = "herbier_photo_id"

let find_original ~id =
  list_files ~fields:"files(id,webViewLink)"
    ~q:
      (Printf.sprintf
         "appProperties has { key=%s and value=%s } and trashed = false"
         (quote photo_id_key)
         (quote (Photo_id.to_string id)))

type metadata = {
  name : string;
  mime : string;
  folder_id : string;
  photo_id : Photo_id.t;
  sha256 : string;
}

let metadata_json {name; mime; folder_id; photo_id; sha256} =
  `Assoc
    [
      ("name", `String name);
      ("mimeType", `String mime);
      ("parents", `List [`String folder_id]);
      ( "appProperties",
        `Assoc
          [
            (photo_id_key, `String (Photo_id.to_string photo_id));
            ("sha256", `String sha256);
          ] );
    ]

let boundary ~random = "herbier-" ^ Herbier_net.Hex.encode random

(* RFC 2045 token characters. *)
let token_char = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' -> true
  | '!' | '#' | '$' | '%' | '&' | '\'' | '*' | '+' | '-' | '.' | '^' | '_' | '`'
  | '{' | '|' | '}' | '~' ->
      true
  | _ -> false

let is_token s = s <> "" && String.for_all token_char s

let media_type mime =
  match String.split_on_char '/' mime with
  | [ty; sub] when is_token ty && is_token sub -> mime
  | _ -> "application/octet-stream"

let create_original (m : metadata) ~boundary =
  let prefix =
    String.concat ""
      [
        "--";
        boundary;
        "\r\nContent-Type: ";
        json_type;
        "\r\n\r\n";
        Yojson.Safe.to_string (metadata_json m);
        "\r\n--";
        boundary;
        "\r\nContent-Type: ";
        media_type m.mime;
        "\r\n\r\n";
      ]
  in
  {
    meth = `POST;
    url = upload_api ^ "?uploadType=multipart&fields=id,webViewLink";
    body = Multipart {boundary; prefix; suffix = "\r\n--" ^ boundary ^ "--\r\n"};
  }

let create_session m =
  {
    meth = `POST;
    url = upload_api ^ "?uploadType=resumable&fields=id,webViewLink";
    body = Json (Yojson.Safe.to_string (metadata_json m));
  }

let decode_session headers =
  match
    List.find_opt
      (fun (name, _) -> String.equal (String.lowercase_ascii name) "location")
      headers
  with
  | Some (_, url) when String.starts_with ~prefix:(upload_api ^ "?") url ->
      Ok url
  | Some _ | None -> Error (Malformed "location")

let get_trashed ~file_id =
  {
    meth = `GET;
    url = api ^ "/" ^ Url.encode file_id ^ "?fields=id,trashed";
    body = Empty;
  }

let view_url ~file_id =
  "https://drive.google.com/file/d/" ^ Url.encode file_id ^ "/view"

(* Decoders *)

type file = {id : string; web_view_link : string option} [@@deriving eq]

let parse body =
  Result.map_error (fun (_ : string) -> Malformed "not JSON") (Json.parse body)

let file_of_json ~what json =
  match Json.string_member "id" json with
  | None -> Error (Malformed what)
  | Some id -> Ok {id; web_view_link = Json.string_member "webViewLink" json}

let decode_files body =
  let open Result.Syntax in
  let* json = parse body in
  match Json.member "files" json with
  | Some (`List entries) ->
      List.fold_right
        (fun entry acc ->
          let* files = acc in
          let+ file = file_of_json ~what:"files[].id" entry in
          file :: files)
        entries (Ok [])
  | Some _ | None -> Error (Malformed "files")

let decode_file body = Result.bind (parse body) (file_of_json ~what:"id")

type presence = Present | Trashed | Missing [@@deriving eq]

let decode_trashed body =
  Result.bind (parse body) (fun json ->
      match Json.member "trashed" json with
      | Some (`Bool false) -> Ok Present
      | Some (`Bool true) -> Ok Trashed
      | Some _ | None -> Error (Malformed "trashed"))

(* Programs *)

type 'a t = Done of 'a | Send of request * (response -> 'a t)

let rec bind t f =
  match t with
  | Done x -> f x
  | Send (request, k) -> Send (request, fun response -> bind (k response) f)

(* Binding operators over a program whose result is a [result]: the first
   [Error] ends it. *)
module Result_syntax = struct
  let ( let* ) t f = bind t (function Ok x -> f x | Error e -> Done (Error e))
  let ( let+ ) t f = bind t (fun r -> Done (Result.map f r))
end

let ok status = 200 <= status && status <= 299

let send request decode =
  Send
    ( request,
      function
      | Unreachable m -> Done (Error (Network m))
      | Answer {status; body; _} when ok status -> Done (decode body)
      | Answer {status; body; _} -> Done (Error (error_of_answer ~status ~body))
    )

(* As [send], for an answer read from its headers. *)
let send_headers request decode =
  Send
    ( request,
      function
      | Unreachable m -> Done (Error (Network m))
      | Answer {status; headers; _} when ok status -> Done (decode headers)
      | Answer {status; body; _} -> Done (Error (error_of_answer ~status ~body))
    )

let folder ~name ~parent =
  let open Result_syntax in
  let* found = send (find_folder ~name ~parent) decode_files in
  match found with
  | first :: _ -> Done (Ok first.id)
  | [] ->
      let+ created = send (create_folder ~name ~parent) decode_file in
      created.id

type target = {
  species : string;
  name : string;
  mime : string;
  photo_id : Photo_id.t;
  sha256 : string;
}

type original = {target : target; boundary : string}
type put = Created of file | Already_there of file [@@deriving eq]
type start = Already_there of file | Session of string [@@deriving eq]

(* The part put_original and start_session share: the lookup by
   [herbier_photo_id], then the folders and the new file's metadata. *)
type located = Found of file | New of metadata

let locate (t : target) =
  let open Result_syntax in
  let* found = send (find_original ~id:t.photo_id) decode_files in
  match found with
  | first :: _ -> Done (Ok (Found first))
  | [] ->
      let* root = folder ~name:root_folder ~parent:Root in
      let+ species = folder ~name:t.species ~parent:(Folder root) in
      New
        {
          name = t.name;
          mime = t.mime;
          folder_id = species;
          photo_id = t.photo_id;
          sha256 = t.sha256;
        }

let put_original (o : original) =
  let open Result_syntax in
  let* located = locate o.target in
  match located with
  | Found first -> Done (Ok (Already_there first : put))
  | New metadata ->
      let+ file =
        send (create_original metadata ~boundary:o.boundary) decode_file
      in
      Created file

let start_session (t : target) =
  let open Result_syntax in
  let* located = locate t in
  match located with
  | Found first -> Done (Ok (Already_there first : start))
  | New metadata ->
      let+ url = send_headers (create_session metadata) decode_session in
      Session url

(* see exploratory_research/photo-storage-google.md §3.4 *)
let presence ~file_id =
  bind
    (send (get_trashed ~file_id) decode_trashed)
    (function Error Not_found -> Done (Ok Missing) | r -> Done r)

let rec run answer = function
  | Done x -> x
  | Send (request, k) -> run answer (k (answer request))

let requests answer t =
  let rec go acc = function
    | Done _ -> List.rev acc
    | Send (request, k) -> go (request :: acc) (k (answer request))
  in
  go [] t
