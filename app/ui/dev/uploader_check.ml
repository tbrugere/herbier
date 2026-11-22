open Brr
module Cap_uploader = Herbier_bindings.Cap_uploader
module Cap_error = Herbier_bindings.Cap_error
module Files = Herbier_store_io.Files
module Queue = Herbier_photos_io.Upload_queue
module Photo = Herbier_domain.Photo
module Db = Herbier_store_io.Db

let failure_text : Cap_uploader.failure -> string = function
  | Answered {status; body} -> Printf.sprintf "FAILED %d %s" status body
  | File_missing -> "FAILED file missing"
  | Gave_up m -> "FAILED gave up: " ^ m

let state_text : Cap_uploader.state -> string = function
  | Enqueued -> "ENQUEUED"
  | Blocked -> "BLOCKED"
  | Running -> "RUNNING"
  | Succeeded {status; body} -> Printf.sprintf "SUCCEEDED %d %s" status body
  | Failed f -> failure_text f
  | Cancelled -> "CANCELLED"

let job_text ({id; state; attempts} : Cap_uploader.job) =
  Printf.sprintf "%s · %s · attempts %d" id (state_text state) attempts

let text_input ~label value =
  El.input
    ~at:
      [
        At.type' (Jstr.v "text");
        At.value (Jstr.v value);
        At.v (Jstr.v "aria-label") (Jstr.v label);
      ]
    ()

let value input = String.trim (Jstr.to_string (El.prop El.Prop.value input))

(* Random bytes, so that a corrupted or truncated upload changes the
   SHA-256 the sink prints. *)
let random_blob n =
  let rng = Random.State.make_self_init () in
  let a = Tarray.create Tarray.Uint8 n in
  let b = Tarray.to_bigarray1 a in
  Seq.iter
    (fun i -> Bigarray.Array1.set b i (Random.State.int rng 256))
    (Seq.init n Fun.id);
  Blob.of_array_buffer (Tarray.buffer a)

(* style: local mutable state because the buttons share the last file
   written; it lives as long as the page. *)
type last = {mutable file : string option; mutable count : int}

let plugin_part () =
  let log = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "log")] [] in
  let jobs = El.div [] in
  let base = text_input ~label:"URL du puits" "http://localhost:8787/upload" in
  let size = text_input ~label:"Taille (octets)" "2097152" in
  let last =
    {file = None; count = int_of_float (Ptime.to_float_s (Ptime_clock.now ()))}
  in
  let refresh () =
    Fut.await (Cap_uploader.jobs ()) (function
      | Ok l ->
          El.set_children jobs
            (match l with
            | [] -> [El.p [El.txt' "(aucun job)"]]
            | l -> List.map (fun j -> El.p [El.txt' (job_text j)]) l)
      | Error e -> Kit.append log ("jobs: " ^ Cap_error.to_string e))
  in
  let write () =
    match int_of_string_opt (value size) with
    | Some n when n > 0 ->
        last.count <- last.count + 1;
        let id = Printf.sprintf "dev-%d" last.count in
        let blob = random_blob n in
        let open Fut.Syntax in
        Fut.await
          (let* written =
             Files.write_blob ~path:(Files.original_of_name id) blob
           in
           match written with
           | Error e -> Fut.return (Error (Cap_error.to_string e))
           | Ok () ->
               Fut.map
                 (Result.map_error Herbier_photos_io.Preview.error_to_string)
                 (Herbier_photos_io.Preview.sha256_hex blob))
          (function
            | Ok sha ->
                last.file <- Some id;
                Kit.append log
                  (Printf.sprintf "write: %s %d bytes sha256 %s" id n sha)
            | Error m -> Kit.append log ("write: " ^ m))
    | Some _ | None -> Kit.append log "write: taille invalide"
  in
  let send network () =
    match last.file with
    | None -> Kit.append log "enqueue: aucun fichier"
    | Some id ->
        Fut.await
          (Kit.step log ("enqueue " ^ id)
             ~detail:(fun () -> None)
             ~error:Cap_error.to_string
             (Cap_uploader.enqueue ~id
                ~path:(Files.original_of_name id)
                ~url:(value base ^ "/" ^ id)
                ~mime:"application/octet-stream" ~network))
          (fun _ -> refresh ())
  in
  let cancel () =
    match last.file with
    | None -> Kit.append log "cancel: aucun fichier"
    | Some id ->
        Fut.await
          (Kit.step log ("cancel " ^ id)
             ~detail:(fun () -> None)
             ~error:Cap_error.to_string (Cap_uploader.cancel ~id))
          (fun _ -> refresh ())
  in
  Fut.await (Cap_uploader.on_change refresh) (function
    | Ok (_ : Cap_uploader.listener) -> ()
    | Error e -> Kit.append log ("listener: " ^ Cap_error.to_string e));
  refresh ();
  El.div
    [
      El.h2 [El.txt' "Plugin"];
      El.div [base; size];
      El.div
        [
          Kit.action "Écrire un fichier" write;
          Kit.action "Envoyer (Wi-Fi seulement)" (send Unmetered);
          Kit.action "Envoyer (tout réseau)" (send Any);
          Kit.action "Annuler" cancel;
          Kit.action "Rafraîchir" refresh;
        ];
      jobs;
      log;
    ]

let entry_text ({row; photo; job} : Queue.entry) =
  Printf.sprintf "%s · photo %s · job %s · attempts %d · session %s%s"
    (Herbier_domain.Ids.Photo_id.to_string row.photo_id)
    (Option.fold ~none:"(absente)" ~some:Photo.Upload_state.to_string photo)
    (Option.fold ~none:"(aucun)"
       ~some:(fun (j : Cap_uploader.job) -> state_text j.state)
       job)
    row.attempts
    (match row.session with Some _ -> "oui" | None -> "non")
    (Option.fold ~none:"" ~some:(fun e -> " · " ^ e) row.last_error)

let trash_text (r : Herbier_store.Drive_trash.t) =
  Printf.sprintf "corbeille · %s · fichier %s · attempts %d%s"
    (Herbier_domain.Ids.Photo_id.to_string r.photo_id)
    r.file_id r.attempts
    (Option.fold ~none:"" ~some:(fun e -> " · " ^ e) r.last_error)

(* The emulator has no Google account: a live Drive photo not uploaded yet
   gets a made-up Drive file id, so that deleting it fills the Drive bin's
   queue (its request then waits for a token). *)
let fake_uploaded app log refresh () =
  let open Fut.Syntax in
  Fut.await
    (let* photos = Db.all (App.db app) Herbier_store.Photos.live in
     match photos with
     | Error e -> Fut.return (Error (Db.error_to_string e))
     | Ok photos -> (
         match
           List.find_opt
             (fun (p : Photo.t) ->
               match (p.original_target, p.drive_file_id) with
               | Drive, None -> true
               | Drive, Some _ | App_only, _ -> false)
             photos
         with
         | None -> Fut.return (Error "no Drive photo without a file")
         | Some p ->
             let file =
               "dev-fake-" ^ Herbier_domain.Ids.Photo_id.to_string p.id
             in
             Fut.map
               (function
                 | Ok (_ : int) ->
                     Ok
                       (file
                       ^ " ← "
                       ^ Herbier_domain.Ids.Photo_id.to_string p.id)
                 | Error e -> Error (Db.error_to_string e))
               (App.save app
                  [
                    Herbier_store.Photos.set_upload p.id ~state:Uploaded
                      ~drive_file_id:(Some file) ~at:(Ptime_clock.now ());
                  ])))
    (fun r ->
      Kit.append log
        (match r with
        | Ok m -> "fake upload: " ^ m
        | Error e -> "fake upload: " ^ e);
      refresh ())

let queue_part app =
  let uploads = App.uploads app in
  let log = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "log")] [] in
  let rows = El.div [] in
  let trash = El.div [] in
  let refresh () =
    Fut.await (Queue.entries uploads) (function
      | Ok [] -> El.set_children rows [El.p [El.txt' "(file vide)"]]
      | Ok l ->
          El.set_children rows
            (List.map (fun e -> El.p [El.txt' (entry_text e)]) l)
      | Error e -> Kit.append log ("entries: " ^ Db.error_to_string e));
    Fut.await (Queue.trash_entries uploads) (function
      | Ok [] -> El.set_children trash [El.p [El.txt' "(corbeille vide)"]]
      | Ok l ->
          El.set_children trash
            (List.map (fun r -> El.p [El.txt' (trash_text r)]) l)
      | Error e -> Kit.append log ("trash: " ^ Db.error_to_string e))
  in
  let pass ~interactive () =
    Kit.append log
      (match interactive with
      | true -> "pass: interactive"
      | false -> "pass: silent");
    Fut.await (Queue.run uploads ~interactive) (fun () ->
        Kit.append log "pass: done";
        refresh ())
  in
  (* « Envoyer maintenant » needs a failed photo, which the emulator cannot
     produce without Drive. *)
  let mark_failed () =
    let open Fut.Syntax in
    Fut.await
      (let* rows = Db.all (App.db app) Herbier_store.Uploads.all in
       match rows with
       | Error e -> Fut.return (Error (Db.error_to_string e))
       | Ok [] -> Fut.return (Error "no row")
       | Ok (row :: _) -> (
           let* written =
             Db.write (App.db app)
               (Herbier_store.Uploads.put
                  {row with attempts = 3; last_error = Some "dev"})
           in
           match written with
           | Error e -> Fut.return (Error (Db.error_to_string e))
           | Ok (_ : int) ->
               Fut.map
                 (function
                   | Ok (_ : int) ->
                       Ok (Herbier_domain.Ids.Photo_id.to_string row.photo_id)
                   | Error e -> Error (Db.error_to_string e))
                 (App.save app
                    [
                      Herbier_store.Photos.set_upload row.photo_id ~state:Failed
                        ~drive_file_id:None ~at:(Ptime_clock.now ());
                    ])))
      (fun r ->
        Kit.append log
          (match r with Ok id -> "failed: " ^ id | Error e -> "failed: " ^ e);
        refresh ())
  in
  refresh ();
  El.div
    [
      El.h2 [El.txt' "File"];
      El.div
        [
          Kit.action "Passe silencieuse" (pass ~interactive:false);
          Kit.action "Passe interactive" (pass ~interactive:true);
          Kit.action "Rafraîchir la file" refresh;
          Kit.action "Marquer en échec" mark_failed;
          Kit.action "Faux envoi Drive" (fake_uploaded app log refresh);
        ];
      rows;
      trash;
      log;
    ]

let el app =
  El.div
    (El.h1 [El.txt' "Uploader check"]
    ::
    (match app with
    | Ok app -> [plugin_part (); queue_part app]
    | Error e -> [El.p [El.txt' ("no app: " ^ e)]; plugin_part ()]))
