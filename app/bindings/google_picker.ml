open Brr

type error = Load_failed of string | Picker_failed of string | Busy
[@@deriving eq]

let error_to_string = function
  | Load_failed m -> "load: " ^ m
  | Picker_failed m -> "picker: " ^ m
  | Busy -> "busy"

let load_timeout_ms = 15_000
let script_url = "https://apis.google.com/js/api.js"

type config = {app_id : string; developer_key : string option; origin : string}
type picked = {id : string; name : string; mime_type : string} [@@deriving eq]
type outcome = Picked of picked | Cancelled [@@deriving eq]

(* style: module state because the script, its load and the Picker shown are
   page-wide platform state: one api.js per page, one Picker at a time. *)
type load_state = Idle | Loading of (unit, error) result Fut.t | Loaded

let load_state = ref Idle

type shown = {picker : Jv.t; settle : (outcome, error) result -> unit}

let shown : shown option ref = ref None

(* Bumped by every [dismiss]: a pick whose ticket is older was cancelled while
   it waited for its token or for api.js. *)
let generation = ref 0

type ticket = int

let ticket () = !generation
let cancelled ticket = ticket <> !generation

let js_message = function
  | Jv.Error e -> Some (Jstr.to_string (Jv.Error.message e))
  | Failure m -> Some m
  | _ -> None

(* gapi.load "picker" once api.js has run: its callback and onerror race
   start_load's timer through [settle]. *)
let gapi_load ~settle =
  match Jv.find Jv.global "gapi" with
  | None -> settle (Error (Load_failed "gapi missing after api.js"))
  | Some gapi -> (
      let fail m = settle (Error (Load_failed m)) in
      let options =
        Jv.obj
          [|
            ("callback", Jv.callback ~arity:1 (fun (_ : Jv.t) -> settle (Ok ())));
            ( "onerror",
              Jv.callback ~arity:1 (fun (_ : Jv.t) -> fail "gapi.load failed")
            );
          |]
      in
      match Jv.call gapi "load" [|Jv.of_string "picker"; options|] with
      | (_ : Jv.t) -> ()
      | exception exn -> (
          match js_message exn with Some m -> fail m | None -> raise exn))

let start_load () =
  let fut, resolve = Fut.create () in
  let script =
    El.v (Jstr.v "script")
      ~at:
        [
          At.v (Jstr.v "src") (Jstr.v script_url);
          At.v (Jstr.v "async") Jstr.empty;
        ]
      []
  in
  (* style: a local flag, so that only the first of load, error, timeout
     settles. *)
  let settled = ref false in
  let settle r =
    match !settled with
    | true -> ()
    | false ->
        settled := true;
        (match r with
        | Ok () -> load_state := Loaded
        | Error (_ : error) ->
            El.remove script;
            load_state := Idle);
        resolve r
  in
  let target = El.as_target script in
  let (_ : Ev.listener) =
    Ev.listen Ev.load (fun (_ : Ev.Type.void Ev.t) -> gapi_load ~settle) target
  in
  let (_ : Ev.listener) =
    Ev.listen Ev.error
      (fun (_ : Ev.Error.t Ev.t) ->
        settle (Error (Load_failed ("cannot load " ^ script_url))))
      target
  in
  let (_ : G.timer_id) =
    G.set_timeout ~ms:load_timeout_ms (fun () ->
        settle (Error (Load_failed "timeout")))
  in
  load_state := Loading fut;
  El.append_children (Document.head G.document) [script];
  fut

let load () =
  match !load_state with
  | Loaded -> Fut.return (Ok ())
  | Loading fut -> fut
  | Idle -> start_load ()

(* The constants of google.picker (Response.ACTION, Document.ID, …), read at
   run time; their documented values when absent. *)
let constant path ~default =
  let rec walk v = function
    | [] -> Some v
    | k :: rest -> Option.bind (Jv.find v k) (fun v -> walk v rest)
  in
  match walk Jv.global ("google" :: "picker" :: path) with
  | Some v when Jstr.equal (Jv.typeof v) (Jstr.v "string") -> Jv.to_string v
  | Some _ | None -> default

let string_field v key =
  match Jv.find v key with
  | Some s when Jstr.equal (Jv.typeof s) (Jstr.v "string") -> Jv.to_string s
  | Some _ | None -> ""

let first_doc data =
  match Jv.find data (constant ["Response"; "DOCUMENTS"] ~default:"docs") with
  | Some docs when Jv.is_array docs -> (
      match Jv.to_list Fun.id docs with
      | doc :: (_ : Jv.t list) -> (
          match
            String.trim
              (string_field doc (constant ["Document"; "ID"] ~default:"id"))
          with
          | "" -> None
          | id ->
              Some
                {
                  id;
                  name =
                    string_field doc
                      (constant ["Document"; "NAME"] ~default:"name");
                  mime_type =
                    string_field doc
                      (constant ["Document"; "MIME_TYPE"] ~default:"mimeType");
                })
      | [] -> None)
  | Some _ | None -> None

let dispose picker =
  match Jv.call picker "dispose" [||] with
  | (_ : Jv.t) -> ()
  | exception exn -> (
      match js_message exn with
      | Some m -> Console.error [Jstr.v "picker: dispose"; Jstr.v m]
      | None -> raise exn)

let finish r =
  match !shown with
  | None -> ()
  | Some s ->
      shown := None;
      dispose s.picker;
      s.settle r

let on_callback ~on_action data =
  let action =
    string_field data (constant ["Response"; "ACTION"] ~default:"action")
  in
  on_action action;
  let picked = constant ["Action"; "PICKED"] ~default:"picked"
  and cancel = constant ["Action"; "CANCEL"] ~default:"cancel"
  and error = constant ["Action"; "ERROR"] ~default:"error" in
  match () with
  | () when String.equal action picked -> (
      match first_doc data with
      | Some p -> finish (Ok (Picked p))
      | None -> finish (Error (Picker_failed "no document")))
  | () when String.equal action cancel -> finish (Ok Cancelled)
  | () when String.equal action error ->
      finish (Error (Picker_failed "error action"))
  | () -> ()

let build ~on_action config ~token =
  let picker_ns = Jv.get (Jv.get Jv.global "google") "picker" in
  let view =
    Jv.new'
      (Jv.get picker_ns "DocsView")
      [|Jv.get (Jv.get picker_ns "ViewId") "FOLDERS"|]
  in
  let (_ : Jv.t) = Jv.call view "setSelectFolderEnabled" [|Jv.true'|] in
  let (_ : Jv.t) = Jv.call view "setIncludeFolders" [|Jv.true'|] in
  let (_ : Jv.t) =
    Jv.call view "setMimeTypes"
      [|Jv.of_string "application/vnd.google-apps.folder"|]
  in
  let (_ : Jv.t) = Jv.call view "setParent" [|Jv.of_string "root"|] in
  let builder = Jv.new' (Jv.get picker_ns "PickerBuilder") [||] in
  let set m v = ignore (Jv.call builder m [|v|] : Jv.t) in
  set "addView" view;
  set "setOAuthToken" (Jv.of_string token);
  set "setAppId" (Jv.of_string config.app_id);
  Option.iter
    (fun k -> set "setDeveloperKey" (Jv.of_string k))
    config.developer_key;
  set "setOrigin" (Jv.of_string config.origin);
  set "setLocale" (Jv.of_string "fr");
  set "setTitle" (Jv.of_string "Choisir le dossier Drive");
  set "setCallback" (Jv.callback ~arity:1 (on_callback ~on_action));
  Jv.call builder "build" [||]

let show ~on_action config ~token =
  match !shown with
  | Some (_ : shown) -> Fut.return (Error Busy)
  | None -> (
      let fut, settle = Fut.create () in
      match build ~on_action config ~token with
      | picker -> (
          shown := Some {picker; settle};
          match Jv.call picker "setVisible" [|Jv.true'|] with
          | (_ : Jv.t) -> fut
          | exception exn ->
              let m =
                match js_message exn with
                | Some m -> m
                | None -> Printexc.to_string exn
              in
              finish (Error (Picker_failed m));
              fut)
      | exception exn -> (
          match js_message exn with
          | Some m -> Fut.return (Error (Picker_failed m))
          | None -> raise exn))

let pick_folder ?(on_action = fun (_ : string) -> ()) ticket config ~token =
  match !shown with
  | Some (_ : shown) -> Fut.return (Error Busy)
  | None when cancelled ticket -> Fut.return (Ok Cancelled)
  | None -> (
      let open Fut.Syntax in
      let* loaded = load () in
      match loaded with
      | Ok () when cancelled ticket -> Fut.return (Ok Cancelled)
      | Ok () -> show ~on_action config ~token
      | Error e -> Fut.return (Error e))

let dismiss () =
  incr generation;
  finish (Ok Cancelled)

let dismiss_if_shown () =
  match !shown with
  | Some (_ : shown) ->
      dismiss ();
      true
  | None -> false
