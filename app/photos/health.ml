module Photo = Herbier_domain.Photo
module Photo_id = Herbier_domain.Ids.Photo_id

let interval = Ptime.Span.of_int_s (7 * 24 * 3600)

let due ~now ~last =
  match last with
  | None -> true
  | Some last ->
      let age = Ptime.diff now last in
      Ptime.Span.compare age Ptime.Span.zero < 0
      || Ptime.Span.compare age interval >= 0

type item = {
  photo_id : Photo_id.t;
  file_id : string;
  state : Photo.Upload_state.t;
}
[@@deriving eq]

let item (p : Photo.t) =
  match
    ( p.deleted_at,
      p.original_target,
      p.upload_state,
      Option.bind p.drive_file_id Herbier_domain.Text.non_blank )
  with
  | None, Drive, ((Uploaded | Original_missing) as state), Some file_id ->
      Some {photo_id = p.id; file_id; state}
  | Some _, _, _, _
  | _, App_only, _, _
  | _, _, (Pending | Failed), _
  | _, _, _, None ->
      None

let items photos = List.filter_map item photos

(* Text order, as [Photos.in_drive]'s [order by id]. *)
let resume ~after items =
  match after with
  | None -> items
  | Some after ->
      let after = Photo_id.to_string after in
      List.filter
        (fun i -> String.compare (Photo_id.to_string i.photo_id) after > 0)
        items

let verdict (state : Photo.Upload_state.t) (presence : Drive.presence) :
    Photo.Upload_state.t option =
  match (state, presence) with
  | Uploaded, (Trashed | Missing) -> Some Original_missing
  | Original_missing, Present -> Some Uploaded
  | Uploaded, Present | Original_missing, (Trashed | Missing) -> None
  | (Pending | Failed), (Present | Trashed | Missing) -> None

type change = {item : item; state : Photo.Upload_state.t} [@@deriving eq]

type report = {
  checked : int;
  changes : change list;
  skipped : (item * Drive.error) list;
  stopped : Drive.error option;
  reached : Photo_id.t option;
}
[@@deriving eq]

let empty_report =
  {checked = 0; changes = []; skipped = []; stopped = None; reached = None}

let finish r =
  {r with changes = List.rev r.changes; skipped = List.rev r.skipped}

let program items =
  let rec go acc = function
    | [] -> Drive.Done (finish acc)
    | item :: rest ->
        Drive.bind (Drive.presence ~file_id:item.file_id) (function
          | Ok presence ->
              let changes =
                match verdict item.state presence with
                | Some state -> {item; state} :: acc.changes
                | None -> acc.changes
              in
              go
                {
                  acc with
                  checked = acc.checked + 1;
                  changes;
                  reached = Some item.photo_id;
                }
                rest
          | Error e -> (
              match Drive.error_scope e with
              | This_file ->
                  go
                    {
                      acc with
                      skipped = (item, e) :: acc.skipped;
                      reached = Some item.photo_id;
                    }
                    rest
              | Account -> Drive.Done (finish {acc with stopped = Some e})))
  in
  go empty_report items

let summary r =
  Printf.sprintf "checked %d, changed %d, skipped %d%s" r.checked
    (List.length r.changes) (List.length r.skipped)
    (match r.stopped with
    | None -> ""
    | Some e -> ", stopped: " ^ Drive.error_to_string e)
