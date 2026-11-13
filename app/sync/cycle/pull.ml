module Store = Herbier_store
module Smap = Map.Make (String)
module Sset = Set.Make (String)

type table_report = {
  table : string;
  fetched : int;
  inserted : int;
  replaced : int;
  unchanged : int;
  kept_local : int;
  repeated : bool;
  cursor : Ptime.t option;
}
[@@deriving eq, show]

type report = table_report list [@@deriving eq, show]
type t = Done of report | Stopped of Outcome.stop [@@deriving eq, show]

let writes report =
  List.fold_left (fun n r -> n + r.inserted + r.replaced) 0 report

(* One table's rows as received, in server order. *)
type fetched = Fetched : ('table, 'row) Synced.t * 'row list -> fetched

let chunks size l =
  let rec go acc current n = function
    | [] ->
        List.rev (match current with [] -> acc | _ -> List.rev current :: acc)
    | x :: rest when n < size -> go acc (x :: current) (n + 1) rest
    | x :: rest -> go (List.rev current :: acc) [x] 1 rest
  in
  go [] [] 0 l

(* Keeps each id's last occurrence, at that occurrence's place: the server
   orders by updated_at, so the last one is the newest. *)
let dedup t rows =
  List.fold_left
    (fun (seen, acc) row ->
      let id = Synced.id t row in
      match Sset.mem id seen with
      | true -> (seen, acc)
      | false -> (Sset.add id seen, row :: acc))
    (Sset.empty, []) (List.rev rows)
  |> snd

let newest t rows =
  List.fold_left
    (fun acc row ->
      let at = Synced.updated_at t row in
      match acc with
      | Some m when Ptime.compare m at >= 0 -> acc
      | Some _ | None -> Some at)
    None rows

module Make (H : Net.Rest.HTTP) (L : Local.S with module IO = H.IO) = struct
  module R = Net.Rest.Make (H)
  module C = Io.Make (H) (L)

  let fetch_table ~conn t ~since =
    let open C.Syntax in
    let rec page n acc =
      let*? c = conn () in
      let* rows = R.select_since c t ~since ~page:n in
      match rows with
      | Error e -> C.return (Error (C.stop_of_error e))
      | Ok rows -> (
          let acc = List.rev_append rows acc in
          match List.length rows < Net.Rest.page_size with
          | true -> C.return (Ok (Fetched (t, List.rev acc)))
          | false -> page (n + 1) acc)
    in
    page 0 []

  let fetch_all ~conn cursors =
    let open C.Syntax in
    let*? fetched =
      C.fold
        (fun acc (Synced.Any t) ->
          let since = Smap.find_opt (Synced.name t) cursors in
          let*? fetched = fetch_table ~conn t ~since in
          C.return (Ok (fetched :: acc)))
        [] Synced.all
    in
    C.return (Ok (List.rev fetched))

  let locals tx t ids =
    C.fold
      (fun acc chunk ->
        let open C.Syntax in
        let*? rows = L.Tx.all tx (Synced.local t chunk) in
        C.return
          (Ok
             (List.fold_left
                (fun acc row -> Smap.add (Synced.id t row) row acc)
                acc rows)))
      Smap.empty
      (chunks Herbier_store.Stmt.max_ids ids)

  let merge_rows tx t ~local ~pending report rows =
    C.fold
      (fun r row ->
        let open C.Syntax in
        let id = Synced.id t row in
        let write r =
          let*? (_ : int) = L.Tx.write tx (Synced.write t row) in
          C.return (Ok r)
        in
        match
          Synced.decide t ~pending:(Sset.mem id pending)
            ~local:(Smap.find_opt id local) row
        with
        | Insert -> write {r with inserted = r.inserted + 1}
        | Replace -> write {r with replaced = r.replaced + 1}
        | Unchanged -> C.return (Ok {r with unchanged = r.unchanged + 1})
        | Keep_local -> C.return (Ok {r with kept_local = r.kept_local + 1}))
      report rows

  (* The cursor moves to the newest updated_at fetched, unless an id came
     twice (the offset race, architecture §4). *)
  let advance_cursor tx t rows (report : table_report) =
    let open C.Syntax in
    match (report.repeated, newest t rows) with
    | true, _ | false, None -> C.return (Ok report)
    | false, Some at ->
        let*? (_ : int) =
          L.Tx.write_local tx (Store.Sync_state.set ~table_name:report.table at)
        in
        C.return (Ok {report with cursor = Some at})

  let apply_table tx cursors (Fetched (t, rows)) =
    let open C.Syntax in
    let table = Synced.name t in
    let empty =
      {
        table;
        fetched = List.length rows;
        inserted = 0;
        replaced = 0;
        unchanged = 0;
        kept_local = 0;
        repeated = false;
        cursor = Smap.find_opt table cursors;
      }
    in
    match rows with
    | [] -> C.return (Ok empty)
    | _ :: _ ->
        let unique = dedup t rows in
        let repeated = List.compare_lengths unique rows <> 0 in
        let*? local = locals tx t (List.map (Synced.id t) unique) in
        let*? pending =
          L.Tx.all tx (Store.Outbox.pending_ids ~table_name:table)
        in
        let*? report =
          merge_rows tx t ~local ~pending:(Sset.of_list pending)
            {empty with repeated} unique
        in
        advance_cursor tx t rows report

  let apply_all store cursors fetched =
    L.bare_transaction store (fun tx ->
        let open C.Syntax in
        let*? reports =
          C.fold
            (fun acc f ->
              let*? r = apply_table tx cursors f in
              C.return (Ok (r :: acc)))
            [] fetched
        in
        C.return (Ok (List.rev reports)))

  let run store ~conn =
    let open C.Syntax in
    let* result =
      let*? cursors = C.store (L.all store Store.Sync_state.all) in
      let cursors = Smap.of_list cursors in
      let*? fetched = fetch_all ~conn cursors in
      C.store (apply_all store cursors fetched)
    in
    C.return
      (match result with
      | Ok report -> Done report
      | Error stop -> Stopped stop)
end
