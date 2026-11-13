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

val email_of_json : Yojson.Safe.t -> (string option, string) result
(** The email rule of the stored value and of GoTrue's [user.email]: [null] and
    [""] are [None], a string is [Some], anything else an [Error]. *)

val to_string : t -> string
(** JSON object
    [{"v":1,"access_token":…,"refresh_token":…,"expires_at":<int s>,
     "user_id":…,"email":<string|null>}], the Preferences value. *)

val to_json : t -> Yojson.Safe.t
(** {!to_string}'s object, not yet printed. *)

val of_string : string -> (t, string) result
(** Inverse of {!to_string}. [Error] with a short reason that names a field,
    never its value: ["not JSON"], ["not an object"], ["no version"],
    ["unknown version"] (["v"] not [1]), ["<field> missing or ill-typed"],
    ["expires_at is not an int"], ["expires_at out of range"] (Ptime's),
    ["email is not a string"]. Unknown extra fields are ignored. Never raises.
*)

val of_json : Yojson.Safe.t -> (t, string) result
(** {!of_string} on an already parsed value: the same reasons but ["not JSON"].
*)

val refresh_margin : Ptime.Span.t
(** 90 s: a session is refreshed this long before its access token expires. *)

val due : now:Ptime.t -> t -> bool
(** [expires_at - now <= refresh_margin]. *)

val refresh_in : now:Ptime.t -> t -> Ptime.Span.t
(** Time until {!due} becomes true: [expires_at - refresh_margin - now], or zero
    when already due. Never negative. *)

val expired : now:Ptime.t -> t -> bool
(** [expires_at - now <= 5 s]: the access token must not be sent any more. *)

val with_expiry : Ptime.t -> t -> t
(** The same session with [expires_at] replaced (the dev page's « Expirer »). *)
