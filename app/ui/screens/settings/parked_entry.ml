module Synced = Herbier_sync.Synced
module Last_error = Herbier_sync.Cycle.Last_error
module Tables = Herbier_store.Tables

type t = {title : string; detail : string}

let field (col : (_, _, _) Postgrest.Col.t) = function
  | `Assoc fields -> (
      match List.assoc_opt col.name fields with
      | Some (`String s) -> Some s
      | Some _ | None -> None)
  | _ -> None

let named label col payload =
  match field col payload with
  | Some value -> Printf.sprintf "%s « %s »" label value
  | None -> label

let reference_title payload =
  match field Tables.Reference.source payload with
  | Some source -> "Référence " ^ source
  | None -> "Référence"

(* One title per table of [Synced.all]. *)
let titles : (Synced.any * (Yojson.Safe.t -> string)) list =
  [
    (Any Synced.plants, named "Plante" Tables.Plants.display_name);
    (Any Synced.tags, named "Étiquette" Tables.Tags.name);
    (Any Synced.observations, Fun.const "Observation");
    (Any Synced.photos, Fun.const "Photo");
    (Any Synced.plant_tags, Fun.const "Étiquette d’une plante");
    (Any Synced.plant_refs, Fun.const "Lien de référence");
    (Any Synced.reference, reference_title);
  ]

let title ~table_name payload =
  match
    List.find_opt
      (fun (Synced.Any t, _) -> String.equal (Synced.name t) table_name)
      titles
  with
  | Some (_, title) -> title payload
  | None -> table_name

let detail last_error =
  match Last_error.of_string last_error with
  | Invalid _ -> "Entrée illisible"
  | Rejected status -> Printf.sprintf "Refusée par le serveur (%d)" status
  | Other text -> text

let describe ~table_name ~payload ~last_error =
  {title = title ~table_name payload; detail = detail last_error}
