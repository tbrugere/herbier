module Original_target = struct
  type t = App_only | Drive [@@deriving eq, show]

  let all = [App_only; Drive]
  let to_string = function App_only -> "app_only" | Drive -> "drive"

  include Lookup.Make (struct
    type nonrec t = t

    let all = all
    let to_string = to_string
  end)
end

module Upload_state = struct
  type t = Pending | Uploaded | Failed | Original_missing
  [@@deriving eq, show]

  let all = [Pending; Uploaded; Failed; Original_missing]

  let to_string = function
    | Pending -> "pending"
    | Uploaded -> "uploaded"
    | Failed -> "failed"
    | Original_missing -> "original_missing"

  include Lookup.Make (struct
    type nonrec t = t

    let all = all
    let to_string = to_string
  end)
end

(* style: [original_target], [drive_file_id] and [upload_state] are three
   fields, not one [App_only | Drive of ...] variant, because the record
   mirrors the [photos] row column for column and the store reads it through
   flat [Postgrest] columns, whose row specs cannot fail. *)
type id = Ids.Photo_id.t [@@deriving eq, show]

type t = {
  id : id;
  observation_id : Ids.Observation_id.t;
  taken_at : Ptime.t;
  width : int;
  height : int;
  sha256 : string;
  preview_path : string;
  preview_bucket_key : string option;
  original_target : Original_target.t;
  drive_file_id : string option;
  upload_state : Upload_state.t;
  created_at : Ptime.t;
  updated_at : Ptime.t;
  deleted_at : Ptime.t option;
}
[@@deriving eq, show]

let awaiting_drive p =
  match (p.original_target, p.upload_state) with
  | Original_target.Drive, (Upload_state.Pending | Failed) -> true
  | Drive, (Uploaded | Original_missing)
  | App_only, (Pending | Uploaded | Failed | Original_missing) ->
      false
