open Brr
module Auth = Herbier_sync.Auth
module Api = Herbier_photos.Drive
module Drive = Herbier_photos_io.Drive
module Preview = Herbier_photos_io.Preview
module Canvas_jpeg = Herbier_bindings.Canvas_jpeg
module Cap_error = Herbier_bindings.Cap_error
module Photo_id = Herbier_domain.Ids.Photo_id
module Drive_consent = Herbier_sync_core.Auth.Drive_consent
module C2d = Brr_canvas.C2d
module Photo = Herbier_domain.Photo
module Photos = Herbier_store.Photos
module Db = Herbier_store_io.Db
module Health = Herbier_photos_io.Health
module Drive_root = Herbier_photos_io.Drive_root
module Settings = Herbier_store.Settings

type mark = Uploaded | Missing

let dev_file_id = "herbier-dev-file"

(* The newest live Drive-bound photo ([Photos.live] is newest first). *)
let mark_original app mark =
  let open Fut.Syntax in
  let* photos = Db.all (App.db app) Photos.live in
  match photos with
  | Error e -> Fut.return (Error (Db.error_to_string e))
  | Ok photos -> (
      match
        List.find_opt
          (fun (p : Photo.t) ->
            match p.original_target with Drive -> true | App_only -> false)
          photos
      with
      | None -> Fut.return (Error "no Drive photo")
      | Some p -> (
          let state, drive_file_id =
            match mark with
            | Uploaded -> (Photo.Upload_state.Uploaded, Some dev_file_id)
            | Missing ->
                ( Photo.Upload_state.Original_missing,
                  Some (Option.value p.drive_file_id ~default:dev_file_id) )
          in
          let+ saved =
            App.save app
              [
                Photos.set_upload p.id ~state ~drive_file_id
                  ~at:(Ptime_clock.now ());
              ]
          in
          match saved with
          | Ok (_ : int) ->
              Ok
                (Printf.sprintf "%s %s" (Photo_id.to_string p.id)
                   (Photo.Upload_state.to_string state))
          | Error e -> Error (Db.error_to_string e)))

let token_detail token = Printf.sprintf "token, %d chars" (String.length token)

let file_line label ({id; web_view_link} : Api.file) =
  Printf.sprintf "%s %s %s" label id
    (Option.value web_view_link ~default:"(no link)")

let put_detail = function
  | Api.Created f -> file_line "Created" f
  | Api.Already_there f -> file_line "Already_there" f

(* Without the id: the « Dossier racine » line shows it. *)
let root_detail = function
  | Api.Keep -> "keep"
  | Api.Store (_ : string) -> "store"
  | Api.Forget -> "forget"

let presence_detail = function
  | Api.Present -> "Present"
  | Api.Trashed -> "Trashed"
  | Api.Missing -> "Missing"

(* A small test image: a green square with a red band, so that a corrupted
   upload shows in Drive's preview. *)
let test_jpeg () =
  let canvas = Brr_canvas.Canvas.create ~w:64 ~h:64 [] in
  let ctx = C2d.get_context canvas in
  C2d.set_fill_style ctx (C2d.color (Jstr.v "#2e7d32"));
  C2d.fill_rect ctx ~x:0. ~y:0. ~w:64. ~h:64.;
  C2d.set_fill_style ctx (C2d.color (Jstr.v "#c62828"));
  C2d.fill_rect ctx ~x:0. ~y:24. ~w:64. ~h:16.;
  Fut.map
    (Result.map_error (function
      | Canvas_jpeg.Encode e -> "encode: " ^ Cap_error.to_string e
      | Canvas_jpeg.Not_jpeg t -> "not a JPEG: " ^ t))
    (Canvas_jpeg.encode ~quality:0.9 canvas)

let species_of input =
  match
    Herbier_domain.Text.non_blank (Jstr.to_string (El.prop El.Prop.value input))
  with
  | Some name -> name
  | None -> Api.unidentified_folder

let fresh_original ~species =
  let open Fut.Result_syntax in
  let* blob = test_jpeg () in
  let* sha256 =
    Herbier_bindings.Fut_result.map_error Preview.error_to_string
      (Preview.sha256_hex blob)
  in
  let* boundary =
    Fut.return (Result.map_error (fun m -> "crypto: " ^ m) (Drive.boundary ()))
  in
  let photo_id = Photo_id.fresh () in
  let now = Ptime_clock.now () in
  let name =
    Api.file_name ~taken_at:now
      ~offset_s:(Herbier_bindings.Js_date.offset_at_s (Ptime.to_float_s now))
      ~id:photo_id ~mime:Canvas_jpeg.mime
  in
  Fut.return
    (Ok
       ( {
           Api.target =
             {species; name; mime = Canvas_jpeg.mime; photo_id; sha256};
           boundary;
         },
         blob ))

let drive_error = Drive.error_to_string Auth.drive_error_to_string

(* « Plugin seul »: the binding past the account gate, so it needs no app; the
   page without an app keeps it, to show [Unavailable] in a browser. *)
let plugin_only log ~after =
  Kit.action "Plugin seul" (fun () ->
      Fut.await
        (Kit.step log "plugin"
           ~detail:(fun t -> Some (token_detail t))
           ~error:Cap_error.to_string
           (Herbier_bindings.Cap_google_authorization.authorize
              ~scopes:[Drive_consent.scope] ~account:None ~interactive:false))
        (fun _ -> after ()))

(* style: local refs because the buttons share what the last upload made;
   they live as long as the page. *)
type last = {
  mutable original : (Api.original * Brr.Blob.t) option;
  mutable file_id : string option;
}

let page app =
  let auth = App.auth app in
  let log = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "log")] [] in
  let status = El.p [] in
  let root_line = El.p [] in
  let db = App.db app in
  let render () =
    El.set_children status
      [El.txt' ("status: " ^ Auth_check.status_to_string (Auth.status auth))];
    Fut.await (Drive_root.stored db) (fun stored ->
        let shown =
          match stored with
          | Ok (Some id) -> id
          | Ok None -> "aucun"
          | Error e -> "illisible : " ^ Db.error_to_string e
        in
        El.set_children root_line [El.txt' ("Dossier racine : " ^ shown)])
  in
  render ();
  let species =
    El.input
      ~at:
        [
          At.type' (Jstr.v "text");
          At.value (Jstr.v "Digitalis purpurea");
          At.v (Jstr.v "aria-label") (Jstr.v "Espèce");
        ]
      ()
  in
  let last = {original = None; file_id = None} in
  let token ~interactive () = Auth.drive_token auth ~interactive in
  let drop_token = Auth.drop_drive_token auth in
  let step label ~detail ~error fut =
    Fut.await (Kit.step log label ~detail ~error fut) (fun _ -> render ())
  in
  let ask label ~interactive =
    step label
      ~detail:(fun t -> Some (token_detail t))
      ~error:Auth.drive_error_to_string
      (Auth.drive_token auth ~interactive)
  in
  let put label (original, blob) =
    last.original <- Some (original, blob);
    let upload =
      Fut.map
        (function
          | Ok ({result; root = change} : _ Api.rooted) ->
              Kit.append log ("root: " ^ root_detail change);
              Result.map_error drive_error result
          | Error e -> Error ("root folder: " ^ Db.error_to_string e))
        (Drive_root.run db
           (Drive.put_original ~token:(token ~interactive:true) ~drop_token
              original blob))
    in
    Fut.await upload (function
      | Ok (Api.Created f | Api.Already_there f) -> last.file_id <- Some f.id
      | Error _ -> ());
    step label ~detail:(fun p -> Some (put_detail p)) ~error:Fun.id upload
  in
  let fresh label k =
    Fut.await
      (fresh_original ~species:(species_of species))
      (function
        | Ok made -> k made | Error m -> Kit.append log (label ^ ": " ^ m))
  in
  let authorize =
    Kit.action "Autoriser Drive" (fun () -> ask "authorize" ~interactive:true)
  and silent =
    Kit.action "Jeton silencieux" (fun () -> ask "silent" ~interactive:false)
  and plugin = plugin_only log ~after:render
  and upload =
    Kit.action "Envoyer un fichier test" (fun () ->
        fresh "upload" (put "upload"))
  and again =
    Kit.action "Renvoyer le même" (fun () ->
        match last.original with
        | Some made -> put "again" made
        | None -> Kit.append log "again: nothing sent yet")
  and check =
    Kit.action "Vérifier" (fun () ->
        match last.file_id with
        | Some file_id ->
            step "presence"
              ~detail:(fun p -> Some (presence_detail p))
              ~error:drive_error
              (Drive.presence ~token:(token ~interactive:true) ~drop_token
                 ~file_id)
        | None -> Kit.append log "presence: no file yet")
  and invalid =
    Kit.action "Jeton invalide" (fun () ->
        fresh "invalid" (fun (original, blob) ->
            (* style: a local counter, read once the run has ended. *)
            let drops = ref 0 in
            let upload =
              Fut.map
                (fun ({result; _} : _ Api.rooted) -> result)
                (Drive.put_original
                   ~token:(fun () -> Fut.return (Ok "ya29.invalid"))
                   ~drop_token:(fun (_ : string) ->
                     incr drops;
                     Fut.return ())
                   ~root:None original blob)
            in
            step "invalid"
              ~detail:(fun p -> Some (put_detail p))
              ~error:(fun e ->
                Printf.sprintf "%s (drops: %d)"
                  (Drive.error_to_string (fun (_ : unit) -> "") e)
                  !drops)
              upload))
  in
  let forget =
    Kit.action "Oublier le dossier" (fun () ->
        step "forget root"
          ~detail:(fun (_ : int) -> None)
          ~error:Db.error_to_string (Drive_root.forget db))
  in
  let originals =
    Kit.action "Vérifier les originaux" (fun () ->
        let open Fut.Syntax in
        Fut.await
          (let* outcome = Health.run (App.health app) ~force:true in
           Kit.append log ("health: " ^ Health.outcome_to_string outcome);
           Db.find db (Settings.get Drive_health_checked_at))
          (function
            | Ok (Some at) ->
                Kit.append log ("checked at: " ^ Ptime.to_rfc3339 at)
            | Ok None -> Kit.append log "checked at: never"
            | Error e -> Kit.append log ("checked at: " ^ Db.error_to_string e)))
  in
  let mark label m =
    Kit.action label (fun () ->
        step "mark" ~detail:Option.some ~error:Fun.id (mark_original app m))
  in
  El.div
    [
      El.h1 [El.txt' "Drive check"];
      status;
      El.p [El.txt' ("scope: " ^ Drive_consent.scope)];
      El.div [authorize; silent; plugin];
      El.div [species; upload; again; check; invalid];
      root_line;
      El.div [forget];
      El.div
        [
          originals;
          mark "Original envoyé (factice)" Uploaded;
          mark "Original introuvable" Missing;
        ];
      log;
    ]

let el = function
  | Error e ->
      let log = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "log")] [] in
      El.div
        [
          El.h1 [El.txt' "Drive check"];
          El.p [El.txt' ("no app: " ^ e)];
          El.div [plugin_only log ~after:ignore];
          log;
        ]
  | Ok app -> page app
