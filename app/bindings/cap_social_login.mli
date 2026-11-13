(** Binding to [@capgo/capacitor-social-login]
    ([globalThis.herbier.socialLogin]), Google provider only: Credential Manager
    sign-in returning an OpenID id token. *)

val initialize_google : web_client_id:string -> (unit, Cap_error.t) result Fut.t
(** [SocialLogin.initialize({google: {webClientId, mode: "online"}})]. Must
    resolve before {!login_google}. Calling it again re-initialises (harmless).
*)

val login_google : nonce:string -> (string, Cap_error.t) result Fut.t
(** [SocialLogin.login({provider: "google", options: {nonce, style:
     "standard"}})] → [result.idToken], the OpenID Connect id token (a JWT,
    never logged). [nonce] is put in the id token's [nonce] claim as given (the
    caller passes the SHA-256 hex of the nonce it later sends to Supabase).
    Errors: plugin missing → [Unavailable "socialLogin"]; rejection →
    [Rejected {code; message}] (code ["USER_CANCELLED"] when the user dismissed
    the chooser, see {!cancelled}); a resolved value whose [result.responseType]
    is not ["online"] → [Unexpected "result.responseType"]; [result.idToken]
    null or not a string → [Unexpected "result.idToken"]. Never raises. *)

val logout_google : unit -> (unit, Cap_error.t) result Fut.t
(** [SocialLogin.logout({provider: "google"})]: clears Credential Manager's
    sign-in state on the device (not the Supabase session). *)

val cancelled : Cap_error.t -> bool
(** [true] exactly for [Rejected {code = Some "USER_CANCELLED"; _}], what the
    plugin (8.7.5, GoogleProvider.java [handleSignInError]) rejects a dismissed
    chooser with. *)
