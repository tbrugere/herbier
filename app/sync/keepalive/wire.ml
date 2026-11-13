module Client = Postgrest.Client
module Tags = Herbier_store.Tables.Tags
module Outbox = Herbier_store.Outbox

let label = "re.bruge.herbier.keepalive"
let version = 1
let interval_minutes = 720
let queue_limit = 200

type event =
  | Run
  | Run_now
  | Set_session
  | Take_session
  | Hand_off
  | Reclaim
  | Report

let event_to_string = function
  | Run -> "keepAlive"
  | Run_now -> "runNow"
  | Set_session -> "setSession"
  | Take_session -> "takeSession"
  | Hand_off -> "handOff"
  | Reclaim -> "reclaim"
  | Report -> "report"

type meth = [`DELETE | `GET | `PATCH | `POST] [@@deriving eq]

let meth_to_yojson : meth -> Yojson.Safe.t = function
  | `DELETE -> `String "DELETE"
  | `GET -> `String "GET"
  | `PATCH -> `String "PATCH"
  | `POST -> `String "POST"

let headers_to_yojson headers =
  `Assoc
    (List.map
       (fun (name, value) -> (String.lowercase_ascii name, `String value))
       headers)

type request = {
  meth : meth; [@key "method"]
  url : string;
  headers : (string * string) list; [@to_yojson headers_to_yojson]
  body : string option;
}
[@@deriving eq, to_yojson]

(* The requests are rendered, not sent: an IO that carries the requests
   made along with the value, so that the very code the engine runs builds
   them. *)
module Recorder = struct
  module IO = struct
    type 'a t = {value : 'a; sent : request list}

    let return value = {value; sent = []}

    let bind m f =
      let r = f m.value in
      {value = r.value; sent = m.sent @ r.sent}
  end

  type error = |

  let error_to_string : error -> string = function _ -> .

  let without_authorization =
    List.filter (fun (name, _) ->
        not (String.equal (String.lowercase_ascii name) "authorization"))

  (* An upsert answers 201 with no body, the ping's select an empty array:
     what the callers' decoders accept. *)
  let send ~meth ~url ~headers ?body () =
    let answer =
      match meth with
      | `GET -> {Client.status = 200; headers = []; body = "[]"}
      | `DELETE | `PATCH | `POST ->
          {Client.status = 201; headers = []; body = ""}
    in
    {
      IO.value = Ok answer;
      sent =
        [
          {
            meth;
            url = Uri.to_string url;
            headers = without_authorization headers;
            body;
          };
        ];
    }
end

module Remote = Net.Rest.Make (Recorder)
module Select = Client.Make (Recorder)

(* The token is never rendered: the recorder drops the header it makes. *)
let conn ~supabase_url ~apikey = Net.Rest.conn ~supabase_url ~apikey ~token:""

let only_request (io : _ Recorder.IO.t) =
  match io.sent with
  | [r] -> Ok r
  | [] | _ :: _ :: _ -> Error "not exactly one request"

let push_request ~supabase_url ~apikey (e : Outbox.entry) =
  match Synced.decode_entry ~table_name:e.table_name e.payload with
  | Error err -> Error (Synced.entry_error_to_string err)
  | Ok (Entry (t, row)) -> (
      let io = Remote.upsert (conn ~supabase_url ~apikey) t row in
      match io.value with
      | Error e -> Error (Remote.error_to_string e)
      | Ok () -> only_request io)

let nil_tag =
  match
    Herbier_domain.Ids.Tag_id.of_string "00000000-0000-0000-0000-000000000000"
  with
  | Some id -> id
  | None -> invalid_arg "Keepalive.Wire: nil uuid"

let ping_request ~supabase_url ~apikey =
  let io =
    Select.select
      (conn ~supabase_url ~apikey)
      (Many (Postgrest.Row.col Tags.id))
      (Eq (Tags.id, Value nil_tag))
      Tags.table
  in
  match only_request io with
  | Ok r -> r
  | Error why -> invalid_arg ("Keepalive.Wire.ping_request: " ^ why)

(* GoTrue's request, as the job sends it: the [authorization] header is the
   job's to add. *)
let gotrue_template (r : Auth.Gotrue.request) =
  {
    meth = `POST;
    url = r.url;
    headers = Recorder.without_authorization r.headers;
    body = None;
  }

type backend = {
  v : int;
  supabase_url : string;
  apikey : string;
  ping : request;
  refresh : request;
  logout : request;
}
[@@deriving to_yojson]

type session_doc = {
  backend : backend;
  session : Auth.Session.t; [@to_yojson Auth.Session.to_json]
}
[@@deriving to_yojson]

let session_doc ~supabase_url ~apikey session =
  let backend =
    {
      v = version;
      supabase_url = Net.Rest.base_url supabase_url;
      apikey;
      ping = ping_request ~supabase_url ~apikey;
      refresh =
        gotrue_template
          (Auth.Gotrue.refresh_grant ~base_url:supabase_url ~apikey
             ~refresh_token:"");
      logout =
        gotrue_template
          (Auth.Gotrue.logout ~base_url:supabase_url ~apikey ~access_token:"");
    }
  in
  Yojson.Safe.to_string (session_doc_to_yojson {backend; session})

type skipped = {seq : int; why : string}
type queue = {doc : string; count : int; skipped : skipped option}
type queue_doc = {v : int; requests : request list} [@@deriving to_yojson]

let queue_doc ~supabase_url ~apikey entries =
  let rec take n acc = function
    | [] -> (List.rev acc, None)
    | _ :: _ when n >= queue_limit -> (List.rev acc, None)
    | (e : Outbox.entry) :: rest -> (
        match push_request ~supabase_url ~apikey e with
        | Ok r -> take (n + 1) (r :: acc) rest
        | Error why -> (List.rev acc, Some {seq = Outbox.seq_to_int e.seq; why})
        )
  in
  let requests, skipped = take 0 [] entries in
  {
    doc = Yojson.Safe.to_string (queue_doc_to_yojson {v = version; requests});
    count = List.length requests;
    skipped;
  }

let decode_reclaim text =
  let open Result.Syntax in
  let* fields = Json_read.versioned version text in
  match List.assoc_opt "in_flight" fields with
  | Some (`Bool in_flight) -> Ok in_flight
  | Some _ | None -> Error "bad or missing in_flight"

let decode_taken_session text =
  let open Result.Syntax in
  let* fields = Json_read.versioned version text in
  match List.assoc_opt "session" fields with
  | Some `Null -> Ok None
  | Some (`Assoc _ as session) ->
      Result.map Option.some (Auth.Session.of_json session)
  | Some _ | None -> Error "bad or missing session"
