module Original_target = struct
  type t = App_only | Drive

  let all = [App_only; Drive]

  let equal a b =
    match (a, b) with
    | App_only, App_only | Drive, Drive -> true
    | (App_only | Drive), _ -> false

  let to_string = function App_only -> "app_only" | Drive -> "drive"

  let of_string = function
    | "app_only" -> Some App_only
    | "drive" -> Some Drive
    | _ -> None

  let to_json t = `String (to_string t)
  let of_json = function `String s -> of_string s | _ -> None
end

module Upload_state = struct
  type t = Pending | Uploaded | Failed | Original_missing

  let all = [Pending; Uploaded; Failed; Original_missing]

  let to_string = function
    | Pending -> "pending"
    | Uploaded -> "uploaded"
    | Failed -> "failed"
    | Original_missing -> "original_missing"

  let of_string = function
    | "pending" -> Some Pending
    | "uploaded" -> Some Uploaded
    | "failed" -> Some Failed
    | "original_missing" -> Some Original_missing
    | _ -> None

  let to_json t = `String (to_string t)
  let of_json = function `String s -> of_string s | _ -> None
end

(* style: [original_target], [drive_file_id] and [upload_state] are three
   fields, not one [App_only | Drive of ...] variant, because the record
   mirrors the [photos] row column for column and the store reads it through
   flat [Postgrest] columns, whose row specs cannot fail. *)
type id = Ids.Photo_id.t

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

let awaiting_drive p =
  match (p.original_target, p.upload_state) with
  | Original_target.Drive, (Upload_state.Pending | Failed) -> true
  | Drive, (Uploaded | Original_missing)
  | App_only, (Pending | Uploaded | Failed | Original_missing) ->
      false
