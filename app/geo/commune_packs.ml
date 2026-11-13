module Db = Herbier_store.Db
module Files = Herbier_store.Files
module Rows = Herbier_store.Commune_packs
module Cap_error = Herbier_bindings.Cap_error
module Code = Communes.Code

type error = Fetch of Geocoder.error | File of Cap_error.t | Store of Db.error

let error_to_string = function
  | Fetch e -> Geocoder.error_to_string e
  | File e -> "file: " ^ Cap_error.to_string e
  | Store e -> Db.error_to_string e

let download_timeout_ms = 120_000
let log_error parts = Brr.Console.(error [str (String.concat " " parts)])

let fetch program =
  Fut.map
    (Result.map_error (fun e -> Fetch e))
    (Geocoder.run ~timeout_ms:download_timeout_ms program)

let departements () =
  fetch
    (Geocode.Get
       ( Communes.departements_request,
         fun json -> Geocode.Done (Communes.departements json) ))

let stamp now = Printf.sprintf "%.0f" (Ptime.to_float_s now *. 1000.)

let delete_file ~why path =
  Fut.map
    (function
      | Ok () -> ()
      | Error e -> log_error ["communes:"; why; path; Cap_error.to_string e])
    (Files.delete ~path)

let pack_count (p : Communes.pack) = List.length p.communes

let store db ~now (d : Communes.departement) pack =
  let open Fut.Syntax in
  let code = Code.to_string d.code in
  let text = Communes.to_string pack in
  let path = Files.commune_pack ~departement:code ~stamp:(stamp now) in
  let row =
    {
      Rows.departement = code;
      name = d.name;
      path;
      size_bytes = String.length text;
      communes = pack_count pack;
      downloaded_at = now;
    }
  in
  (* The new file is referenced by nothing until the row is written. *)
  let cleanup error =
    let+ () = delete_file ~why:"cleanup" path in
    Error error
  in
  let* written = Files.write_text ~path text in
  match written with
  | Error e -> cleanup (File e)
  | Ok () -> (
      let* previous = Db.find db (Rows.find code) in
      match previous with
      | Error e -> cleanup (Store e)
      | Ok previous -> (
          let* put = Db.write db (Rows.put row) in
          match (put, previous) with
          | Error e, _ -> cleanup (Store e)
          | Ok (_ : int), Some (old : Rows.t)
            when not (String.equal old.path path) ->
              let+ () = delete_file ~why:"previous" old.path in
              Ok (row, pack)
          | Ok (_ : int), (Some _ | None) -> Fut.return (Ok (row, pack))))

(* A decoder that raises (a JS stack overflow on a hostile payload) must not
   leave the download's future undetermined. *)
let pack_of_payload ~departement json =
  match Communes.pack_of_payload ~departement json with
  | result -> result
  | exception e ->
      Error
        (Geocode.Unexpected
           {
             path = "";
             expected = "a decodable payload: " ^ Printexc.to_string e;
           })

let download db ~now (d : Communes.departement) =
  let open Fut.Syntax in
  let* fetched =
    fetch
      (Geocode.Get
         ( Communes.communes_request ~departement:d.code,
           fun json -> Geocode.Done (pack_of_payload ~departement:d.code json)
         ))
  in
  match fetched with
  | Error e -> Fut.return (Error e)
  | Ok pack -> store db ~now d pack

let delete db code =
  let open Fut.Syntax in
  let code = Code.to_string code in
  let* row = Db.find db (Rows.find code) in
  match row with
  | Error e -> Fut.return (Error (Store e))
  | Ok None -> Fut.return (Ok ())
  | Ok (Some (row : Rows.t)) -> (
      let* removed = Db.write db (Rows.remove ~departement:code) in
      match removed with
      | Error e -> Fut.return (Error (Store e))
      | Ok (_ : int) ->
          let+ () = delete_file ~why:"delete" row.path in
          Ok ())

type loaded = {
  index : Communes.t;
  rows : (Code.t * Rows.t) list;
  unreadable : Code.t list;
}

let decode code text =
  match Communes.of_string text with
  | Ok (pack : Communes.pack) when Code.equal pack.departement code -> Ok pack
  | Ok pack ->
      Error ("the file holds département " ^ Code.to_string pack.departement)
  | Error e -> Error (Geocode.error_to_string e)
  (* As in [pack_of_payload]: the load must settle. *)
  | exception e -> Error (Printexc.to_string e)

let read_pack code (row : Rows.t) =
  Fut.map
    (function
      | Error e -> Error (Cap_error.to_string e) | Ok text -> decode code text)
    (Files.read_text ~path:row.path)

let load db =
  let open Fut.Syntax in
  let* rows = Db.all db Rows.all in
  match rows with
  | Error e -> Fut.return (Error (Store e))
  | Ok rows ->
      let rows =
        List.filter_map
          (fun (row : Rows.t) ->
            match Code.of_string row.departement with
            | Some code -> Some (code, row)
            | None ->
                log_error ["communes: bad code"; row.departement; row.path];
                None)
          rows
      in
      let step acc (code, (row : Rows.t)) =
        let* index, unreadable = acc in
        let+ pack = read_pack code row in
        match pack with
        | Ok pack -> (Communes.add index pack, unreadable)
        | Error e ->
            log_error ["communes: read"; row.departement; row.path; e];
            (index, code :: unreadable)
      in
      let+ index, unreadable =
        List.fold_left step (Fut.return (Communes.empty, [])) rows
      in
      Ok {index; rows; unreadable = List.rev unreadable}
