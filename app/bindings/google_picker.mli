(** Google Picker (the web Picker: {!script_url}, [gapi.load "picker"]), in
    folder-selection mode, over a drive.file OAuth token. The script is loaded
    on first use (one [<script>] element appended to [<head>]; never at
    startup). Never logs the token or the key; the Picker's iframe [src] carries
    the token in its query, so it is never logged either. *)

type error =
  | Load_failed of string
      (** api.js did not load (network, blocked), [gapi.load] failed, or did not
          finish within {!load_timeout_ms}; its message *)
  | Picker_failed of string
      (** building or showing the Picker threw (its message), or the Picker
          answered the ["error"] action or a pick with no document id *)
  | Busy  (** a Picker is already shown *)

val equal_error : error -> error -> bool

val error_to_string : error -> string
(** ["load: <m>"], ["picker: <m>"], ["busy"]. *)

val load_timeout_ms : int
(** 15 000. *)

val script_url : string
(** ["https://apis.google.com/js/api.js"]. *)

val load : unit -> (unit, error) result Fut.t
(** Single-flight and memoised: a second call during a load gets that load's
    result; after [Ok ()] later calls resolve at once; after an [Error] the next
    call retries (it removes the failed [<script>] and appends a new one). A JS
    error or a load failure resolves to [Error _]; any other exception is a bug
    and propagates. *)

type config = {
  app_id : string;  (** the Cloud project number: [PickerBuilder.setAppId] *)
  developer_key : string option;  (** [setDeveloperKey] when [Some] *)
  origin : string;
      (** [setOrigin]: the page's [window.location.origin]
          (["https://localhost"] in the app) *)
}

type picked = {id : string; name : string; mime_type : string}

val equal_picked : picked -> picked -> bool

type outcome = Picked of picked | Cancelled

val equal_outcome : outcome -> outcome -> bool

type ticket
(** Taken when a pick starts, before its token is asked for: a {!dismiss} after
    it cancels that pick. *)

val ticket : unit -> ticket

val pick_folder :
  ?on_action:(string -> unit) ->
  ?title:string ->
  ticket ->
  config ->
  token:string ->
  (outcome, error) result Fut.t
(** A ticket cancelled by a {!dismiss} → [Ok Cancelled], nothing shown (checked
    before and after the load). Else {!load}, then one Picker:
    [DocsView(ViewId.FOLDERS)] with [setSelectFolderEnabled true],
    [setIncludeFolders true],
    [setMimeTypes "application/vnd.google-apps.folder"], [setParent "root"];
    builder [addView], [setOAuthToken token], [setAppId app_id],
    [setDeveloperKey] when given, [setOrigin origin], [setLocale "fr"],
    [setTitle title] (default « Choisir le dossier Drive »; 4m's sheet names the
    account there, the Picker having no account line of its own), [setCallback],
    [build], [setVisible true].

    Callback: [on_action] (default: nothing) gets every action string in order
    (for [#dev/picker]); action ["picked"] → [Picked] of [docs[0]]'s [id]
    (trimmed), [name], [mimeType] (a missing name or type: [""]), or
    [Error (Picker_failed "no document")] when there is no doc or its id is
    blank; ["cancel"] → [Cancelled]; ["error"] →
    [Error (Picker_failed "error action")]; any other action (["loaded"]) is
    ignored. A Picker that never calls back (Google's error page) stays shown
    until {!dismiss}. The future resolves once; the Picker is disposed at that
    point. A call while one is shown → [Error Busy] (nothing built). A JS error
    resolves to [Error _]; any other exception raised building the Picker is a
    bug and propagates. *)

val dismiss : unit -> unit
(** Cancels every ticket taken so far, and disposes the Picker shown, if any;
    its future resolves [Ok Cancelled]. *)

val dismiss_if_shown : unit -> bool
(** {!dismiss} when a Picker is shown, and [true]; else [false], nothing done.
    For Android back: it closes the Picker before it navigates. *)
