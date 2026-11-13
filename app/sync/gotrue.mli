(** Supabase Auth (GoTrue) over HTTP, sans IO: the three calls the app makes and
    their answers. No supabase-js. *)

type request = {
  url : string;
  headers : (string * string) list;
  body : string option;  (** JSON text; [None] for logout *)
}
(** Always a POST. *)

val id_token_grant :
  base_url:string -> apikey:string -> id_token:string -> nonce:string -> request
(** [<base_url>/auth/v1/token?grant_type=id_token] (one slash between [base_url]
    and [/auth], whether or not [base_url] ends with ['/']), headers
    [apikey: <apikey>] and [Content-Type: application/json], no [Authorization];
    body [{"provider":"google","id_token":…,"nonce":…}] ([nonce] is the raw
    nonce, whose SHA-256 hex is the token's claim). *)

val refresh_grant :
  base_url:string -> apikey:string -> refresh_token:string -> request
(** [<base_url>/auth/v1/token?grant_type=refresh_token], same headers, body
    [{"refresh_token":…}]. *)

val logout : base_url:string -> apikey:string -> access_token:string -> request
(** [<base_url>/auth/v1/logout?scope=local], headers [apikey] and
    [Authorization: Bearer <access_token>], no body: revokes this session's
    refresh tokens only. *)

type error =
  | Rejected of {status : int; code : string option; message : string}
      (** A non-2xx answer: [code] is [error_code] and [message] is [msg] of
          GoTrue's JSON error ([code = None] when only [msg] is there), or
          [error] and [error_description] of its OAuth-style one; when the body
          is neither, [code = None] and [message] is the body text. *)
  | Malformed of string
      (** A 2xx answer that is not a session: the missing or ill-typed field, or
          ["not JSON"] / ["not an object"]. *)

val error_to_string : error -> string
(** One line, never a token. *)

val decode_session :
  now:Ptime.t -> status:int -> string -> (Session.t, error) result
(** The answer of {!id_token_grant} or {!refresh_grant}, [now] being when the
    request was sent. 200–299: the body must be an object with string
    [access_token] and [refresh_token], positive int [expires_in] (seconds) and
    object [user] with string [id]; [user.email] optional ([""] → [None]); other
    fields ignored ([expires_at] too: the session's [expires_at] is [now]
    truncated to the second plus [expires_in], so that a device clock set wrong
    does not shift the refresh). Else {!Rejected} as described. Never raises. *)

val decode_empty : status:int -> string -> (unit, error) result
(** The answer of {!logout}: any 2xx → [Ok ()] whatever the body; else as
    {!decode_session}. *)

val revokes_session : error -> bool
(** A refresh answered so means the stored session is dead and must be dropped:
    [Rejected] by GoTrue itself ([code = Some _]) with 400 ≤ status ≤ 499 except
    408 and 429. [false] for 408, 429, ≥ 500, a body that is not GoTrue's
    ([code = None]: a proxy's page, a gateway's 401) and [Malformed] (transient:
    keep it and retry). *)

val signup_disabled : error -> bool
(** [Rejected {code = Some "signup_disabled"; _}]: the Google account has no
    Herbier user (sign-ups are off, the account is created by hand). *)
