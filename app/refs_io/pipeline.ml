module Reference = Herbier_domain.Reference
module Source = Reference.Source
module Db = Herbier_store_io.Db
module References = Herbier_store.References
module Fanout = Herbier_refs.Fanout
module Step = Herbier_refs.Step

type outcome =
  | Written of Reference.Status.t
  | Kept
  | Skipped
  | Not_fetched
  | Not_saved of Db.error

type report = (Source.t * outcome) list

let outcome_to_string = function
  | Written status -> Reference.Status.to_string status
  | Kept -> "kept"
  | Skipped -> "skipped"
  | Not_fetched -> "not fetched"
  | Not_saved e -> "not saved: " ^ Db.error_to_string e

(* What happened to each source the branch answered for: a row [decide]
   dropped is a stored row left as it was. *)
let outcomes (rows : Fanout.row list) (stored : Fanout.row list) written =
  List.map
    (fun (row : Fanout.row) ->
      match
        List.exists
          (fun (s : Fanout.row) -> Source.equal s.source row.source)
          stored
      with
      | true -> (row.source, written row.status)
      | false -> (row.source, Kept))
    rows

(* A bug in a program or in [decide] must not leave the fetch's future
   pending (the plant would stay « mise à jour… »): the branch answers for
   no source instead. *)
let raised text =
  Brr.Console.(error [str "refs: branch raised"; str text]);
  Fut.return []

let edits ~plant ~previous rows =
  let stored = Fanout.decide ~previous rows in
  let now = Ptime_clock.now () in
  ( stored,
    List.map
      (fun (r : Fanout.row) ->
        References.put ~plant ~source:r.source ~fetched_at:now
          ~payload:r.payload ~status:r.status ~at:now)
      stored )

let branch ~save ~plant ~previous program =
  let open Fut.Syntax in
  let* rows =
    Http.run (Step.recover Result.error (Step.map Result.ok program))
  in
  match rows with
  | Error msg -> raised msg
  | Ok rows -> (
      match edits ~plant ~previous rows with
      | exception e -> raised (Printexc.to_string e)
      | stored, [] -> Fut.return (outcomes rows stored (fun s -> Written s))
      | stored, (_ :: _ as edits) -> (
          match save edits with
          | None -> Fut.return (outcomes rows stored (fun _ -> Skipped))
          | Some saved -> (
              let+ saved = saved in
              match saved with
              | Ok (_ : int) -> outcomes rows stored (fun s -> Written s)
              | Error e -> outcomes rows stored (fun _ -> Not_saved e))))

let fetch db ~save ~plant ~gbif_key =
  let open Fut.Syntax in
  let* previous = Db.all db (References.of_plant plant) in
  match previous with
  | Error e -> Fut.return (Error e)
  | Ok previous ->
      let+ results =
        Fut.of_list
          (List.map (branch ~save ~plant ~previous) (Fanout.branches ~gbif_key))
      in
      let answered = List.concat results in
      Ok
        (List.map
           (fun source ->
             ( source,
               Option.value ~default:Not_fetched
                 (List.assoc_opt source answered) ))
           Fanout.sources)
