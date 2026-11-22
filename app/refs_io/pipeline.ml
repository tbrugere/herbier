module Reference = Herbier_domain.Reference
module Source = Reference.Source
module Db = Herbier_store_io.Db
module References = Herbier_store.References
module Fanout = Herbier_refs.Fanout
module Step = Herbier_refs.Step
module Regional = Herbier_refs.Regional
module Uses_fetch = Herbier_refs.Uses_fetch

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

(* What one branch did: what happened to each source it answered for, and
   the program's rows before [decide] ([[]] when it raised), which the
   regional program reads. *)
type settled = {outcomes : (Source.t * outcome) list; rows : Fanout.row list}

let branch ~save ~plant ~previous program =
  let open Fut.Syntax in
  let* rows =
    Http.run (Step.recover Result.error (Step.map Result.ok program))
  in
  match rows with
  | Error msg ->
      let+ outcomes = raised msg in
      {outcomes; rows = []}
  | Ok rows -> (
      let settled outcomes = {outcomes; rows} in
      match edits ~plant ~previous rows with
      | exception e ->
          let+ outcomes = raised (Printexc.to_string e) in
          settled outcomes
      | stored, [] ->
          Fut.return (settled (outcomes rows stored (fun s -> Written s)))
      | stored, (_ :: _ as edits) -> (
          match save edits with
          | None ->
              Fut.return (settled (outcomes rows stored (fun _ -> Skipped)))
          | Some saved -> (
              let+ saved = saved in
              match saved with
              | Ok (_ : int) ->
                  settled (outcomes rows stored (fun s -> Written s))
              | Error e -> settled (outcomes rows stored (fun _ -> Not_saved e))
              )))

let notify on_branch entries =
  match on_branch entries with
  | () -> ()
  | exception e ->
      Brr.Console.(
        error [str "refs: on_branch raised"; str (Printexc.to_string e)])

(* The regional and Pl@ntUse programs read the name (and the TaxRef id) of
   the gbif and wiki rows: they start once the branches have settled, on one
   input, and run concurrently. *)
let after_branches ~on_branch ~save ~plant ~previous branches =
  let open Fut.Syntax in
  let* settled = branches in
  let run program =
    match program () with
    | exception e -> raised (Printexc.to_string e)
    | program ->
        let+ {outcomes; rows = _} = branch ~save ~plant ~previous program in
        notify on_branch outcomes;
        outcomes
  in
  match
    Regional.input ~previous
      (List.concat_map (fun (b : settled) -> b.rows) settled)
  with
  | exception e -> raised (Printexc.to_string e)
  | input ->
      let+ outcomes =
        Fut.of_list
          [
            run (fun () -> Regional.program input);
            run (fun () -> Uses_fetch.program input);
          ]
      in
      List.concat outcomes

let fetch ?(on_branch = fun (_ : report) -> ()) db ~save ~plant ~gbif_key =
  let open Fut.Syntax in
  let* previous = Db.all db (References.of_plant plant) in
  match previous with
  | Error e -> Fut.return (Error e)
  | Ok previous ->
      let branches =
        Fut.of_list
          (List.map
             (fun program ->
               let+ settled = branch ~save ~plant ~previous program in
               notify on_branch settled.outcomes;
               settled)
             (Fanout.branches ~gbif_key))
      in
      let+ results =
        Fut.of_list
          [
            Fut.map (List.concat_map (fun (b : settled) -> b.outcomes)) branches;
            after_branches ~on_branch ~save ~plant ~previous branches;
          ]
      in
      let answered = List.concat results in
      Ok
        (List.map
           (fun source ->
             ( source,
               Option.value ~default:Not_fetched
                 (List.assoc_opt source answered) ))
           Fanout.sources)
