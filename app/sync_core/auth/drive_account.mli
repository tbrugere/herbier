(** The Google account Drive uses (architecture §5, "Drive account"): chosen in
    4m « Dossier Drive », kept in the local setting [drive_account], independent
    of the Supabase session. Pure: no IO. *)

type t =
  | Unconfigured  (** this build has no Google web client id *)
  | Unchosen  (** configured, no account stored yet *)
  | Chosen of {email : string}  (** trimmed, non-empty *)
[@@deriving eq, show]

val of_stored : configured:bool -> string option -> t
(** [configured = false] → [Unconfigured] whatever is stored. Else [None], or a
    value blank after trimming → [Unchosen]; [Some s] →
    [Chosen {email = String.trim s}]. *)

val email : t -> string option
(** [Chosen {email}] → [Some email]; else [None]. *)

type unavailable =
  | No_client  (** [Unconfigured] *)
  | No_account  (** [Unchosen] *)
[@@deriving eq, show]

val request : t -> (string, unavailable) result
(** The account a Drive token request names ([setAccount]), whatever the
    Supabase session: [Chosen {email}] → [Ok email]; [Unchosen] →
    [Error No_account]; [Unconfigured] → [Error No_client]. *)

(** The chooser's failures (the plugin's rejection codes). *)
type choose_error =
  | Cancelled  (** ["USER_CANCELLED"]: the user closed the chooser *)
  | No_google_account  (** ["NO_CREDENTIAL"]: nothing to choose *)
  | Choose_failed
      (** ["CHOOSE_FAILED"], ["INVALID_ARGUMENT"], ["NO_ACTIVITY"], ["BUSY"],
          any other code, none *)
[@@deriving eq, show]

val choose_error_of_code : string option -> choose_error
(** Exact, case-sensitive match. *)
