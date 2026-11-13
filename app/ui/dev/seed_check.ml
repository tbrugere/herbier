module Db = Herbier_store.Db
module Dev_seed = Herbier_store.Dev_seed
module Plants = Herbier_store.Plants
module Tags = Herbier_store.Tags
module Observations = Herbier_store.Observations
module Search = Herbier_store.Search
module Plant = Herbier_domain.Plant

(* Duplicated from storage_check: the dev pages share no module. *)
let append log text = Brr.El.append_children log [Brr.El.div [Brr.El.txt' text]]

let step log label ~detail fut =
  Fut.map
    (fun r ->
      (match r with
      | Ok v -> (
          match detail v with
          | "" -> append log (label ^ ": ok")
          | d -> append log (label ^ ": ok · " ^ d))
      | Error e -> append log (label ^ ": " ^ Db.error_to_string e));
      r)
    fut

let count v = string_of_int (List.length v)

let names plants =
  String.concat ", " (List.map (fun (p : Plant.t) -> p.display_name) plants)

let search db =
  match Search.plants "digitale" with
  | None -> Fut.ok []
  | Some q -> Db.all db q

(* One transaction: the seed is applied whole or not at all. *)
let apply db =
  let open Fut.Result_syntax in
  Db.bare_transaction db (fun tx ->
      let rec go = function
        | [] -> Fut.ok ()
        | bare :: rest ->
            let* (_ : int) = Db.Tx.write tx bare in
            go rest
      in
      go Dev_seed.statements)

let steps log db =
  let open Fut.Result_syntax in
  let* () =
    step log "apply seed"
      ~detail:(fun () ->
        Printf.sprintf "%d statements" (List.length Dev_seed.statements))
      (apply db)
  in
  let* (_ : Plant.t list) =
    step log "live plants" ~detail:count (Db.all db Plants.list)
  in
  let* (_ : Herbier_domain.Tag.t list) =
    step log "live tags" ~detail:count (Db.all db Tags.list)
  in
  let* (_ : Herbier_domain.Observation.t list) =
    step log "live observations" ~detail:count (Db.all db Observations.list)
  in
  let+ (_ : Plant.t list) =
    step log "search \"digitale\"" ~detail:names (search db)
  in
  ()

let el db =
  let log =
    Brr.El.div
      ~at:[Brr.At.v (Jstr.v "role") (Jstr.v "log")]
      [Brr.El.h1 [Brr.El.txt' "Seed check"]]
  in
  (match db with
  | Error e -> append log ("no herbier database: " ^ e)
  | Ok db ->
      Fut.await (steps log db) (fun (_ : (unit, Db.error) result) ->
          append log "done"));
  log
