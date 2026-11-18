module Identify = Herbier_identify
module Plantnet = Herbier_identify.Plantnet
module Identify_io = Herbier_identify.Make (Plantnet_transport)
module Files = Herbier_store_io.Files
module Cap_error = Herbier_bindings.Cap_error
module Photo_id = Herbier_domain.Ids.Photo_id
module Identify_settings = Herbier_ui_model.Identify_settings
module Settings = Herbier_store.Settings
module Db = Herbier_store_io.Db
module Preferences = Herbier_bindings.Cap_preferences

type image = Preview of Brr.Blob.t | Stored of Photo_id.t

(* style: mutable because an answer settles in a future's callback and is
   checked then against the caller's latest request: the channel's
   generation. *)
type channel = int ref

let channel () = ref 0

type identify_error =
  | Identify_offline
  | Preview_unreadable of Photo_id.t
  | Plantnet of Plantnet.error

type 'a current = Settled of ('a, identify_error) result | Superseded

let flora_list_text : identify_error -> string = function
  | Plantnet e -> Identify_settings.flora_list_error e
  | Identify_offline -> Identify_settings.flora_list_offline
  | Preview_unreadable (_ : Herbier_domain.Ids.Photo_id.t) ->
      Identify_settings.flora_list_generic

let blob (image, organ) =
  match image with
  | Preview b -> Fut.return (Ok (b, organ))
  | Stored id ->
      Fut.map
        (function Ok b -> Ok (b, organ) | Error e -> Error (id, e))
        (Files.read_blob ~path:(Files.preview id) ~type':"image/jpeg")

(* Only the photos Make sends are read. *)
let blobs photos =
  Herbier_bindings.Fut_result.traverse blob
    (List.take Identify.Organ.max_photos photos)

(* The gates run cheapest first and nothing is read for a request that cannot
   leave. Make would refuse a blank key or no photo itself, but it takes the
   previews' bytes, read only after the offline gate. *)
let identify (t : Core.t) channel ~key ~flora ?(no_reject = false) photos =
  incr channel;
  let mine = !channel in
  let settle result =
    match Int.equal !channel mine with
    | true -> Settled result
    | false -> Superseded
  in
  let not_sent reason error =
    Core.log [Identify.identify_not_sent ~flora photos reason];
    Fut.return (settle (Error error))
  in
  match Plantnet.identify_request ~key ~flora ~no_reject photos with
  | Error e -> not_sent (Plantnet.error_to_string e) (Plantnet e)
  | Ok (_ : image Plantnet.request) -> (
      match Core.online t with
      | false -> not_sent "offline" Identify_offline
      | true ->
          Fut.bind (blobs photos) (function
            | Error (id, e) ->
                Core.log_error
                  [
                    "identify: preview";
                    Photo_id.to_string id;
                    "unreadable:";
                    Cap_error.to_string e;
                  ];
                not_sent "preview unreadable" (Preview_unreadable id)
            | Ok sent ->
                Fut.map
                  (fun ({result; line} : _ Identify.logged) ->
                    Core.log [line];
                    settle (Result.map_error (fun e -> Plantnet e) result))
                  (Identify_io.identify ~key ~flora ~no_reject sent)))

(* The list is the same for every key, so a key change keeps it. *)
let ask_floras (t : Core.t) ~key =
  let asked = Identify_io.projects ~key in
  t.floras := Asking asked;
  Fut.await asked (fun ({result; line} : _ Identify.logged) ->
      Core.log [line];
      t.floras :=
        match result with
        | Ok l -> Received l
        | Error (_ : Plantnet.error) -> Not_asked);
  asked

let floras (t : Core.t) ~key =
  let settled (logged : _ Identify.logged) =
    Result.map_error (fun e -> Plantnet e) logged.result
  in
  match Plantnet.projects_request ~key with
  | Error (_ : Plantnet.error) ->
      Fut.map
        (fun (logged : _ Identify.logged) ->
          Core.log [logged.line];
          settled logged)
        (Identify_io.projects ~key)
  | Ok (_ : string) -> (
      match !(t.floras) with
      | Received l -> Fut.return (Ok l)
      | Asking asked -> Fut.map settled asked
      | Not_asked -> (
          match Core.online t with
          | false ->
              Core.log [Identify.projects_not_sent "offline"];
              Fut.return (Error Identify_offline)
          | true -> Fut.map settled (ask_floras t ~key)))

let load_plantnet_key (t : Core.t) =
  Herbier_sync.Serial.run t.key_writes (fun () ->
      Fut.map
        (fun read ->
          t.set_plantnet_key
            (match read with
            | Ok stored -> Identify_settings.key_of_stored stored
            | Error e ->
                Core.log_error
                  ["identify: key unreadable:"; Cap_error.to_string e];
                Absent))
        (Preferences.get ~key:Identify_settings.preferences_key))

let plantnet_key (t : Core.t) = t.plantnet_key

(* The signal follows Preferences only once the write is confirmed: a key
   shown but not stored would be gone at the next start. *)
let set_plantnet_key (t : Core.t) input =
  Herbier_sync.Serial.run t.key_writes (fun () ->
      let key = Identify_settings.Key.of_input input in
      let write =
        match key with
        | None -> Preferences.remove ~key:Identify_settings.preferences_key
        | Some k ->
            Preferences.set ~key:Identify_settings.preferences_key
              ~value:(Identify_settings.Key.to_string k)
      in
      Fut.map
        (function
          | Ok () ->
              (match key with
              | None ->
                  t.set_plantnet_key Absent;
                  Core.log ["identify: key cleared"]
              | Some k ->
                  t.set_plantnet_key (Present k);
                  Core.log ["identify: key saved"]);
              Ok ()
          | Error e ->
              Core.log_error ["identify: key not saved:"; Cap_error.to_string e];
              Error e)
        write)

(* Shown before the write, so a second tap while it runs flips it back; a
   failure reverts, to the value SQLite last confirmed, only when no later
   write was started. The writes settle in the order they were issued. *)
let write_setting (t : Core.t) ~writes ~stored ~set ~what value stmt =
  incr writes;
  let mine = !writes in
  set value;
  Fut.map
    (function
      | Ok (_ : int) ->
          stored := value;
          Ok ()
      | Error e ->
          Core.log_error
            ["réglages: identification"; what; Db.error_to_string e];
          (match Int.equal !writes mine with
          | true -> set !stored
          | false -> ());
          Error e)
    (Db.write t.db stmt)

let identify_on_photo (t : Core.t) = t.identify_on_photo

let set_identify_on_photo (t : Core.t) v =
  write_setting t ~writes:t.on_photo_writes ~stored:t.on_photo_stored
    ~set:(fun v -> t.set_identify_on_photo v)
    ~what:"on_photo" v
    (Settings.set Identify_on_photo v)

let plantnet_flora (t : Core.t) = t.plantnet_flora

let set_plantnet_flora (t : Core.t) flora =
  write_setting t ~writes:t.flora_writes ~stored:t.flora_stored
    ~set:(fun f -> t.set_plantnet_flora f)
    ~what:"flora" flora
    (match flora with
    | Some f -> Settings.set Plantnet_project f
    | None -> Settings.unset Plantnet_project)

let identify_gate (t : Core.t) = t.identify_gate

module Choice = Herbier_ui_model.Identify.Choice

let resolve_choice (p : Plantnet.proposal) =
  let what =
    match p.gbif with
    | Some k -> "gbif " ^ string_of_int k
    | None -> p.scientific_name
  in
  let program =
    Herbier_refs.Step.recover (fun m -> Choice.Unavailable m) (Choice.resolve p)
  in
  Fut.map
    (fun (r : Choice.resolution) ->
      (match r with
      | Unavailable m ->
          Core.log_error ["identify: GBIF unavailable for"; what ^ ":"; m]
      | Unknown -> Core.log ["identify: GBIF has no species for"; what]
      | Resolved (_ : Herbier_refs.Sources.Gbif.Taxon.t) -> ());
      r)
    (Herbier_refs_io.Http.run program)
