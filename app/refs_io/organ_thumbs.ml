module Reference = Herbier_domain.Reference
module Organ = Reference.Organ
module Image = Reference.Image
module Db = Herbier_store_io.Db
module Files = Herbier_store_io.Files
module Ref_images = Herbier_store.Ref_images
module References = Herbier_store.References
module Organ_photos = Herbier_refs.Organ_photos
module Projection = Herbier_refs.Projection
module Cap_error = Herbier_bindings.Cap_error
module Cap_http = Herbier_bindings.Cap_http
module Image_bitmap = Herbier_bindings.Image_bitmap
module Canvas_jpeg = Herbier_bindings.Canvas_jpeg
module Fut_result = Herbier_bindings.Fut_result

type failure =
  | Host
  | Download of Cap_error.t
  | Http of int
  | Too_large of int
  | Base64 of Cap_error.t
  | Decode of Cap_error.t
  | Draw of Cap_error.t
  | Encode of Cap_error.t
  | Not_jpeg of string
  | Write of Cap_error.t
  | Stale

type outcome = failure Organ_photos.outcome
type report = (Organ.t * outcome) list

let failure_to_string = function
  | Host -> "host"
  | Download e -> "download: " ^ Cap_error.to_string e
  | Http status -> "HTTP " ^ string_of_int status
  | Too_large n -> "too large: " ^ string_of_int n
  | Base64 e -> "base64: " ^ Cap_error.to_string e
  | Decode e -> "decode: " ^ Cap_error.to_string e
  | Draw e -> "draw: " ^ Cap_error.to_string e
  | Encode e -> "encode: " ^ Cap_error.to_string e
  | Not_jpeg t -> "encode: the WebView produced " ^ t ^ ", not JPEG"
  | Write e -> "write: " ^ Cap_error.to_string e
  | Stale -> "stale"

let outcome_to_string : outcome -> string = function
  | Organ_photos.Present -> "present"
  | Updated -> "updated"
  | Downloaded -> "downloaded"
  | Removed -> "removed"
  | Failed f -> "failed: " ^ failure_to_string f

let changed = Organ_photos.changed
let default_timeout_ms = 20_000
let max_base64 = 16_000_000
let mime = "image/jpeg"

(* {1 One thumbnail} *)

let fetch ~timeout_ms url =
  Fut.map
    (function
      | Error e -> Error (Download e)
      | Ok (Cap_http.Status status) -> Error (Http status)
      | Ok (Body base64) -> (
          match String.length base64 with
          | n when n > max_base64 -> Error (Too_large n)
          | _ -> Ok base64))
    (Cap_http.get_bytes ~url ~timeout_ms)

let draw bitmap =
  let width, height =
    Organ_photos.fit
      ~width:(Image_bitmap.width bitmap)
      ~height:(Image_bitmap.height bitmap)
  in
  match Canvas_jpeg.draw ~width ~height bitmap with
  | Ok canvas -> Ok canvas
  | Error e -> Error (Draw e)
  (* jsoo raises a thrown value that is not an Error as [Failure]. *)
  | exception Failure message ->
      Error (Draw (Cap_error.Rejected {code = None; message}))

let encode canvas =
  Fut_result.map_error
    (function
      | Canvas_jpeg.Encode e -> Encode e | Canvas_jpeg.Not_jpeg t -> Not_jpeg t)
    (Canvas_jpeg.encode ~quality:Organ_photos.quality canvas)

(* The thumbnail's file, written; [Error] for any failure before the
   database is touched. *)
let thumbnail ~timeout_ms (row : Image.t) path =
  let open Fut.Result_syntax in
  let* base64 = fetch ~timeout_ms row.remote_url in
  let* blob =
    Fut.return
      (Result.map_error
         (fun e -> Base64 e)
         (Files.blob_of_base64 ~type':mime base64))
  in
  let* bitmap =
    Fut_result.map_error (fun e -> Decode e) (Image_bitmap.of_blob blob)
  in
  let* canvas = Fut.return (draw bitmap) in
  let* jpeg = encode canvas in
  Fut_result.map_error (fun e -> Write e) (Files.write_blob ~path jpeg)

let download db ~timeout_ms (row : Image.t) =
  let open Fut.Syntax in
  match Organ_photos.downloadable row.remote_url with
  | false -> Fut.ok (Organ_photos.Failed Host)
  | true -> (
      let path =
        Files.refthumb ~plant:row.plant_id ~source:row.source ~organ:row.organ
      in
      let* file = thumbnail ~timeout_ms row path in
      match file with
      | Error why -> Fut.ok (Organ_photos.Failed why)
      | Ok () ->
          let+ set =
            Db.write db
              (Ref_images.set_thumb ~plant:row.plant_id ~source:row.source
                 ~organ:row.organ ~remote_url:row.remote_url ~path)
          in
          Result.map
            (function 0 -> Organ_photos.Failed Stale | _ -> Downloaded)
            set)

(* {1 The plant} *)

let each items f =
  Fut_result.traverse
    (fun x -> Fut.map (Result.map (fun r -> (x, r))) (f x))
    items

(* Best effort: a missing or undeletable file is an orphan no row points
   to. *)
let delete_file (row : Image.t) =
  match row.thumb_path with
  | None -> Fut.return ()
  | Some path ->
      Fut.map (fun (_ : (unit, Cap_error.t) result) -> ()) (Files.delete ~path)

let sync ?(timeout_ms = default_timeout_ms) db ~plant =
  let open Fut.Result_syntax in
  let* references = Db.all db (References.of_plant plant) in
  let* stored = Db.all db (Ref_images.of_plant plant) in
  let wanted =
    Projection.organ_photos_wanted
      (Projection.project ~references ~plant_refs:[])
  in
  let plan = Organ_photos.plan ~plant ~wanted ~stored in
  let* (_ : (Image.t * unit) list) =
    each plan.remove (fun (r : Image.t) ->
        let* (_ : int) =
          Db.write db
            (Ref_images.remove ~plant:r.plant_id ~source:r.source ~organ:r.organ)
        in
        Fut.map Result.ok (delete_file r))
  in
  let* (_ : (Image.t * int) list) =
    each plan.put (fun r -> Db.write db (Ref_images.put r))
  in
  let* rows = Db.all db (Ref_images.of_plant plant) in
  let+ downloads =
    each (Organ_photos.to_download rows) (download db ~timeout_ms)
  in
  Organ_photos.report ~wanted ~plan downloads
