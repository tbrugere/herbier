module Photo = Herbier_domain.Photo

let max_attempts = 3
let session_lifetime = Ptime.Span.of_int_s (6 * 24 * 3600)

type session = {url : string; created_at : Ptime.t} [@@deriving eq]

let session_usable ~now s =
  let age = Ptime.diff now s.created_at in
  Ptime.Span.compare age Ptime.Span.zero >= 0
  && Ptime.Span.compare age session_lifetime < 0

type pending = {attempts : int; session : session option}

type failure =
  | Answered of {status : int; body : string}
  | File_missing
  | Gave_up of string

type job =
  | Waiting
  | Running
  | Succeeded of {status : int; body : string}
  | Failed of failure
  | Cancelled

type resume = Resume of session | Restart [@@deriving eq]

type action =
  | Nothing
  | Start
  | Enqueue of session
  | Finish of Drive.file
  | Retry of {attempts : int; error : string; resume : resume}
  | Give_up of {attempts : int; error : string}
  | Discard
[@@deriving eq]

(* Never the session URL: it is a credential. *)
let pp_action ppf = function
  | Nothing -> Format.pp_print_string ppf "nothing"
  | Start -> Format.pp_print_string ppf "start"
  | Enqueue _ -> Format.pp_print_string ppf "enqueue"
  | Finish f -> Format.fprintf ppf "finish %s" f.id
  | Retry {attempts; error; resume} ->
      Format.fprintf ppf "retry %d (%s) %s" attempts error
        (match resume with Resume _ -> "resume" | Restart -> "restart")
  | Give_up {attempts; error} ->
      Format.fprintf ppf "give up %d (%s)" attempts error
  | Discard -> Format.pp_print_string ppf "discard"

let usable ~now = function
  | Some s when session_usable ~now s -> Some s
  | Some _ | None -> None

type count = {attempts : int; error : string}
type counted = Retry_later of count | Give_up_now of count

let count_failure (p : pending) error =
  let attempts = p.attempts + 1 in
  match attempts >= max_attempts with
  | true -> Give_up_now {attempts; error}
  | false -> Retry_later {attempts; error}

let missing_file (p : pending) =
  {attempts = p.attempts + 1; error = "original file missing"}

let fail ~resume (p : pending) error =
  match count_failure p error with
  | Give_up_now {attempts; error} -> Give_up {attempts; error}
  | Retry_later {attempts; error} -> Retry {attempts; error; resume}

let resume ~now (p : pending) =
  match usable ~now p.session with Some s -> Resume s | None -> Restart

let answer_error ~status ~body =
  Drive.error_to_string (Drive.error_of_answer ~status ~body)

let pending_next ~now (p : pending) = function
  | Some (Waiting | Running) -> Nothing
  | Some (Succeeded {status = 200 | 201; body}) -> (
      match Drive.decode_file body with Ok f -> Finish f | Error _ -> Start)
  | Some (Succeeded _) -> Start
  | Some (Failed (Answered {status = (404 | 410) as status; body})) ->
      fail ~resume:Restart p (answer_error ~status ~body)
  | Some (Failed File_missing) ->
      let {attempts; error} = missing_file p in
      Give_up {attempts; error}
  | Some (Failed (Answered {status; body})) ->
      fail ~resume:(resume ~now p) p (answer_error ~status ~body)
  | Some (Failed (Gave_up m)) -> fail ~resume:(resume ~now p) p m
  | Some Cancelled | None -> (
      match usable ~now p.session with Some s -> Enqueue s | None -> Start)

let next ~now ~(photo : Photo.t option) pending job =
  match photo with
  | None -> Discard
  | Some {original_target = App_only; _} -> Discard
  | Some {upload_state = Uploaded | Original_missing; _} -> Discard
  | Some {upload_state = Failed; _} -> Nothing
  | Some {upload_state = Pending; original_target = Drive; _} ->
      pending_next ~now pending job

type scope = Account | This_photo [@@deriving eq]

let start_error_scope : Drive.error -> scope = function
  | Unauthorized | Api_disabled | Scope_missing | Quota_full | Rate_limited
  | Server _ | Network _ ->
      Account
  | Not_found | Http _ | Malformed _ -> This_photo

let on_network_change ~now (p : pending) = function
  | Some Waiting -> usable ~now p.session
  | Some (Running | Succeeded _ | Failed _ | Cancelled) | None -> None
