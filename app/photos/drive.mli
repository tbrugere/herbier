(** Google Drive v3 for the originals (architecture §5), without IO: the
    requests, the multipart frame, the answers decoded, and the two programs the
    app runs — put an original into [Herbier/<species>/], and check one is still
    there. Run on the device by [Herbier_photos_io.Drive], in tests by {!run}
    over a function standing for the network. Requests carry no Authorization
    header: the runner adds the token. Nothing here raises. *)

module Photo_id := Herbier_domain.Ids.Photo_id

(** {1 Requests and answers} *)

type body =
  | Empty
  | Json of string  (** [Content-Type: application/json; charset=UTF-8] *)
  | Multipart of {boundary : string; prefix : string; suffix : string}
      (** [multipart/related]: [prefix] (the metadata part and the media part's
          headers), then the media bytes the runner holds, then [suffix] *)

type request = {meth : [`GET | `POST]; url : string; body : body}

val equal_request : request -> request -> bool

val content_type : body -> string option
(** [None] for [Empty]; ["application/json; charset=UTF-8"];
    ["multipart/related; boundary=<boundary>"]. *)

type response =
  | Answer of {status : int; headers : (string * string) list; body : string}
      (** [headers]: names lowercased (as fetch gives them); only
          {!start_session} reads them *)
  | Unreachable of string  (** network failure or timeout, its message *)

(** {1 Errors} *)

type error =
  | Unauthorized  (** 401: the token expired or was revoked *)
  | Api_disabled
      (** 403 whose [errors[0].reason] is ["accessNotConfigured"] or whose
          ErrorInfo detail reason is ["SERVICE_DISABLED"]: the Drive API is off
          in the Google Cloud project *)
  | Scope_missing
      (** 403 ["insufficientPermissions"] or ErrorInfo
          ["ACCESS_TOKEN_SCOPE_INSUFFICIENT"]: the token lacks drive.file *)
  | Quota_full  (** 403 ["storageQuotaExceeded"]: the 15 GB are full *)
  | Rate_limited
      (** 429, or 403 ["userRateLimitExceeded"] / ["rateLimitExceeded"] *)
  | Not_found  (** 404 where a file had to exist (a parent folder) *)
  | Server of int  (** 5xx *)
  | Http of {status : int; reason : string option; message : string option}
      (** any other non-2xx; [reason] = [error.errors[0].reason], [message] =
          [error.message], each [None] when absent or not a string *)
  | Malformed of string
      (** a 2xx whose body does not decode as the request's answer; names what
          is missing *)
  | Network of string  (** {!response}'s [Unreachable]: its message *)

val equal_error : error -> error -> bool

val pp_error : Format.formatter -> error -> unit
(** Prints {!error_to_string} (tests' printer). *)

val error_to_string : error -> string
(** One line: ["unauthorized"], ["Drive API disabled"],
    ["HTTP 418 <reason>: <message>"], …; never a token. *)

val error_of_answer : status:int -> body:string -> error
(** A non-2xx answer classified. The body is Google's
    [{"error": {"code", "message", "errors": [{"reason"}], "status", "details":
     [{"@type", "reason"}]}}] when it parses, else ignored (a proxy's HTML page
    gives [Http {reason = None; message = None}] or [Server n]). Order: 401 →
    [Unauthorized]; 429 → [Rate_limited]; 404 → [Not_found]; 500–599 → [Server];
    403 → by reason ([Api_disabled], [Scope_missing], [Quota_full],
    [Rate_limited]), else [Http]; anything else [Http]. Called only on non-2xx
    (a 2xx gives [Http]). *)

(** {1 Names} *)

val root_folder : string
(** ["Herbier"], in My Drive's root. *)

val unidentified_folder : string
(** ["À identifier"]: the folder of an observation without a plant. *)

val species_folder : Herbier_domain.Plant.t option -> string
(** The plant's [scientific_name] ({!Herbier_domain.Text.non_blank}), else its
    [display_name] (same), else {!unidentified_folder}; [None] (observation not
    identified) → {!unidentified_folder}. Authorship never part of it. *)

val file_name :
  taken_at:Ptime.t -> offset_s:int -> id:Photo_id.t -> mime:string -> string
(** ["YYYY-MM-DD HH.MM.SS <last 8 hex digits of the id><ext>"]: [taken_at] at
    [offset_s] seconds east of UTC (the caller passes the device's zone at that
    instant, [Js_date.offset_at_s]); [ext] from [mime]: ["image/jpeg"] →
    [".jpg"], ["image/png"] → [".png"], ["image/webp"] → [".webp"],
    ["image/heic"] → [".heic"], anything else → [""]. E.g.
    ["2026-06-14 10.32.05 5f3c91d2.jpg"] (a v7 id's first digits are its
    timestamp, its last ones random). Near {!Ptime.min} / {!Ptime.max}, where
    the offset would leave Ptime's range, the time is shown in UTC
    ([Ptime.to_date_time]'s fallback). *)

(** {1 Requests} *)

val api : string
(** ["https://www.googleapis.com/drive/v3/files"]. *)

val upload_api : string
(** ["https://www.googleapis.com/upload/drive/v3/files"]. *)

val quote : string -> string
(** A string literal of Drive's [q] syntax: single quotes and backslashes
    backslash-escaped, the whole in single quotes (Herbe d'or gives 'Herbe
    d\'or'). *)

(** Where a folder is looked up or created: My Drive's root, or a folder id. *)
type parent = Root | Folder of string

val equal_parent : parent -> parent -> bool

val find_folder : name:string -> parent:parent -> request
(** GET
    {!api}[?q=<q>&fields=files(id)&orderBy=createdTime&pageSize=10&spaces=drive],
    [q] =
    [name = <quote name> and mimeType = 'application/vnd.google-apps.folder' and
     <quote parent> in parents and trashed = false] (["root"] for [Root]); the
    [q] and [fields] values {!Herbier_net.Url.encode}d (keys and [=]/[&]
    literal). *)

val create_folder : name:string -> parent:parent -> request
(** POST {!api}[?fields=id], [Json] of
    [{"name", "mimeType": "application/vnd.google-apps.folder", "parents":
     [parent]}]. *)

val find_original : id:Photo_id.t -> request
(** GET
    {!api}[?q=<q>&fields=files(id,webViewLink)&orderBy=createdTime&pageSize=10&spaces=drive],
    [q] =
    [appProperties has { key='herbier_photo_id' and value='<id>' } and trashed =
     false]. *)

type metadata = {
  name : string;
  mime : string;
  folder_id : string;  (** parent folder id *)
  photo_id : Photo_id.t;
  sha256 : string;  (** lowercase hex of the original, [Photo.sha256] *)
}

val metadata_json : metadata -> Yojson.Safe.t
(** [{"name", "mimeType", "parents": [folder_id], "appProperties":
     {"herbier_photo_id": <id>, "sha256": <sha256>}}] (architecture §5). *)

val boundary : random:string -> string
(** ["herbier-"] followed by the lowercase hex of [random] (the runner passes 16
    random bytes: 40 characters, within RFC 2046's 70, bchars only). *)

val media_type : string -> string
(** [mime] when it is [type/subtype] of RFC 2045 token characters, else
    ["application/octet-stream"] (no CR or LF reaches the part headers). *)

val create_original : metadata -> boundary:string -> request
(** POST {!upload_api}[?uploadType=multipart&fields=id,webViewLink],
    [Multipart {boundary; prefix; suffix}] with [prefix] =
    ["--B\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n" ^ <metadata
     JSON, compact> ^ "\r\n--B\r\nContent-Type: <media_type mime>\r\n\r\n"] and
    [suffix] = ["\r\n--B--\r\n"] (B the boundary). *)

val create_session : metadata -> request
(** POST {!upload_api}[?uploadType=resumable&fields=id,webViewLink], [Json] of
    {!metadata_json} (so [mimeType], [parents] and [appProperties] travel with
    the session; no X-Upload-* header: the metadata's [mimeType] types the
    file). Exact URL:
    ["https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,webViewLink"].
    The session's final answer (the last PUT of the bytes) is then the file's
    [{"id", "webViewLink"}], {!decode_file}'s input. *)

val decode_session : (string * string) list -> (string, error) result
(** A 2xx answer's headers → the session URL: the [location] header (name
    compared case-insensitively; the first one) when it starts with
    [upload_api ^ "?"]; absent, or another URL → [Malformed "location"]. *)

val get_trashed : file_id:string -> request
(** GET {!api}[/<file_id, Url.encode>?fields=id,trashed]. *)

(** {1 Decoders}

    2xx bodies; [Error (Malformed _)] when a field the request's [fields=] names
    is missing or mistyped. *)

type file = {id : string; web_view_link : string option}

val equal_file : file -> file -> bool

val decode_files : string -> (file list, error) result
(** [{"files": [{"id", "webViewLink"?}, …]}]: an entry without a string [id] →
    [Malformed "files[].id"]; [webViewLink] absent → [None]; ["files"] absent →
    [Malformed "files"] (Drive always sends it with [fields=files(...)], even
    empty); not JSON → [Malformed "not JSON"]. *)

val decode_file : string -> (file, error) result
(** [{"id", "webViewLink"?}]: no string [id] → [Malformed "id"]; not JSON →
    [Malformed "not JSON"]. *)

type presence =
  | Present
  | Trashed  (** in the bin, restorable for 30 days *)
  | Missing  (** 404: deleted for good, or no longer accessible *)

val equal_presence : presence -> presence -> bool

(** {1 Programs} *)

(* style: transparent: the runners (Photos_io.Drive.run, tests) match on it. *)
type 'a t = Done of 'a | Send of request * (response -> 'a t)

val bind : 'a t -> ('a -> 'b t) -> 'b t

val folder : name:string -> parent:parent -> (string, error) result t
(** {!find_folder}; the first (oldest) entry's id; none → {!create_folder}, its
    id. A non-2xx or [Unreachable] ends the program with its error. *)

type target = {
  species : string;  (** folder name, from {!species_folder} *)
  name : string;  (** from {!file_name} *)
  mime : string;
  photo_id : Photo_id.t;
  sha256 : string;
}
(** An original to upload: where it goes and what it is. *)

type original = {target : target; boundary : string  (** from {!boundary} *)}
(** An original sent in one multipart request. *)

type put =
  | Created of file  (** uploaded now *)
  | Already_there of file
      (** a file with this [herbier_photo_id] already exists (an earlier upload
          whose answer was lost): nothing uploaded *)

val equal_put : put -> put -> bool

val put_original : original -> (put, error) result t
(** {!find_original}: an entry → [Already_there] (the oldest). None →
    [folder ~name:root_folder ~parent:Root], then
    [folder ~name:o.target.species ~parent:(Folder <root id>)], then
    {!create_original} into it → [Created]. Stops at the first error. These
    requests in this order, nothing else. Two runs for one account must not
    overlap (two first uploads of one species would create two folders). A
    create whose answer was lost (a timeout) is found by the next run's search;
    should Drive's search lag behind the create, that run uploads a second copy.
*)

type start =
  | Already_there of file
      (** a file with this [herbier_photo_id] exists: nothing to upload *)
  | Session of string  (** the resumable session's URL: a credential *)

val equal_start : start -> start -> bool

val start_session : target -> (start, error) result t
(** {!find_original}: an entry → [Already_there] (the oldest). None →
    [folder ~name:root_folder ~parent:Root], then
    [folder ~name:t.species ~parent:(Folder <root id>)], then {!create_session}
    with [folder_id] the species folder → 2xx → {!decode_session} of its headers
    → [Session url]. Stops at the first error (a non-2xx → {!error_of_answer};
    [Unreachable m] → [Network m]). These requests in this order, nothing else.
    Same overlap rule as {!put_original}: two runs for one account must not
    overlap. *)

val presence : file_id:string -> (presence, error) result t
(** {!get_trashed}: 2xx [trashed = false] → [Present], [true] → [Trashed]
    ([trashed] absent or not a bool → [Malformed "trashed"]); 404 → [Missing];
    anything else → its error. *)

val run : (request -> response) -> 'a t -> 'a
(** Runs the program, answering each request with the function, in order. *)

val requests : (request -> response) -> 'a t -> request list
(** The requests {!run} would make, in order (tests and logs). *)
