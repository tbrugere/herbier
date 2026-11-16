(** Binding to Herbier's own [GoogleAuthorization] Capacitor plugin
    (android/app/src/main/java/re/bruge/herbier/GoogleAuthorizationPlugin.java,
    [globalThis.herbier.googleAuthorization], native only): Play Services'
    AuthorizationClient, which grants OAuth scopes to a Google account (the
    Drive account the user chose in 4m) and hands out 1-hour access tokens it
    caches itself; and Credential Manager's « Sign in with Google » chooser,
    which tells which account that is. *)

val authorize :
  scopes:string list ->
  account:string option ->
  interactive:bool ->
  (string, Cap_error.t) result Fut.t
(** [authorize({scopes, account, interactive})] → [accessToken]. [account] (an
    email: the Drive account the user chose in 4m, {!choose_account}) is
    [AuthorizationRequest.Builder.setAccount]; [None] lets Play Services choose
    (an account chooser when the device has several). When the grant needs the
    user ([hasResolution]): [interactive = true] shows the consent screen and
    resolves with its token; [interactive = false] rejects with code
    ["NEEDS_CONSENT"] and shows nothing. Rejection codes (see
    [Herbier_sync_core.Auth.Drive_consent]): ["NEEDS_CONSENT"],
    ["USER_CANCELLED"] (consent dismissed), ["SCOPE_NOT_GRANTED"] (the result's
    granted scopes lack one of [scopes]: the user unchecked it),
    ["NETWORK_ERROR"], ["DEVELOPER_ERROR"], ["SIGN_IN_REQUIRED"] (those Play
    Services statuses), ["AUTHORIZATION_FAILED"] (any other failure: no consent
    intent, no access token, another Play Services error, its status code in the
    message), ["INVALID_ARGUMENT"] ([scopes] empty, or other than drive.file:
    the plugin grants nothing else), ["NO_ACTIVITY"], ["BUSY"] (an interactive
    request is already showing). Resolved value without a string [accessToken] →
    [Unexpected "accessToken"]. Plugin missing →
    [Unavailable "googleAuthorization"]. Never logs the token. Never raises. *)

val choose_account : web_client_id:string -> (string, Cap_error.t) result Fut.t
(** [chooseAccount({webClientId})] → [email] (a non-empty string, else
    [Unexpected "email"]). Credential Manager's « Sign in with Google » chooser
    ([GetSignInWithGoogleOption] with that server client id: every account on
    the device, « add account » included); the email is the credential's
    [getEmail()], the id token stays in the plugin (never returned, stored or
    logged). Rejection codes (read by
    [Herbier_sync_core.Auth.Drive_account.choose_error_of_code]):
    ["USER_CANCELLED"] (chooser dismissed), ["NO_CREDENTIAL"] (no account to
    choose), ["CHOOSE_FAILED"] (any other failure, its type in the message),
    ["INVALID_ARGUMENT"] (empty client id), ["NO_ACTIVITY"], ["BUSY"] (a choice
    is already showing). Plugin missing → [Unavailable "googleAuthorization"].
    Never logs the email. Never raises. *)

val clear_token : token:string -> (unit, Cap_error.t) result Fut.t
(** [clearToken({token})]: removes that token from Play Services' cache (after
    the API answered 401 with it), so that the next {!authorize} fetches a new
    one. Rejects with ["INVALID_ARGUMENT"] (empty token), ["NO_ACTIVITY"], or a
    Play Services failure's code as {!authorize}'s. *)
