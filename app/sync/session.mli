(** A Supabase Auth session as the device keeps it, its stored form, and when it
    must be refreshed. Pure: no clock is read here, [now] is passed in. *)

type t = {
  access_token : string;  (** JWT sent to PostgREST; never logged *)
  refresh_token : string;  (** single use (rotation); never logged *)
  expires_at : Ptime.t;  (** of the access token, whole seconds *)
  user_id : string;  (** [user.id] (auth.uid()) *)
  email : string option;  (** [user.email]; [None] when absent or [""] *)
}

val equal : t -> t -> bool

val to_string : t -> string
(** JSON object
    [{"v":1,"access_token":…,"refresh_token":…,"expires_at":<int s>,
     "user_id":…,"email":<string|null>}], the Preferences value. *)

val of_string : string -> (t, string) result
(** Inverse of {!to_string}. [Error] (a short reason, never containing a token)
    for non-JSON, a non-object, ["v"] absent or not [1], a missing or ill-typed
    field, an [expires_at] that is not an int or out of Ptime's range. Unknown
    extra fields are ignored. Never raises. *)

val refresh_margin : Ptime.Span.t
(** 90 s: a session is refreshed this long before its access token expires. *)

val due : now:Ptime.t -> t -> bool
(** [expires_at - now <= refresh_margin]. *)

val refresh_in : now:Ptime.t -> t -> Ptime.Span.t
(** Time until {!due} becomes true: [expires_at - refresh_margin - now], or zero
    when already due. Never negative. *)

val expired : now:Ptime.t -> t -> bool
(** [expires_at - now <= 5 s]: the access token must not be sent any more. *)

val retry_delay : attempt:int -> Ptime.Span.t
(** Delay before retrying a refresh that failed transiently: 10 s ×
    2^(attempt-1), at most 300 s; [attempt <= 1] → 10 s. No overflow for large
    [attempt]. *)

val with_expiry : Ptime.t -> t -> t
(** The same session with [expires_at] replaced (the dev page's « Expirer »). *)
