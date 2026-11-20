module Tag = Herbier_domain.Tag
module Tag_id = Herbier_domain.Ids.Tag_id
module Plant_id = Herbier_domain.Ids.Plant_id

type editor = New | Edit of {tag : Tag.t; plants : Plant_id.t list}
type name_check = Blank | Same | Taken of Tag.t | Free of string

let edited = function New -> None | Edit {tag; _} -> Some tag

let is_edited editor (t : Tag.t) =
  match edited editor with Some e -> Tag_id.equal e.id t.id | None -> false

let check ~tags editor text =
  let name = String.trim text in
  let taken () =
    List.find_opt
      (fun (t : Tag.t) ->
        (not (is_edited editor t)) && Plant_form.same_text t.name name)
      tags
  in
  match (name, edited editor) with
  | "", _ -> Blank
  | _, Some tag when String.equal tag.name name -> Same
  | _, (Some _ | None) -> (
      match taken () with Some t -> Taken t | None -> Free name)

type primary = {label : string; enabled : bool; line : string option}

let primary editor check =
  match (editor, check) with
  | New, (Blank | Same) -> {label = "Créer"; enabled = false; line = None}
  | New, Taken t ->
      {
        label = "Créer";
        enabled = false;
        line = Some (Printf.sprintf "« %s » existe déjà." t.name);
      }
  | New, Free _ -> {label = "Créer"; enabled = true; line = None}
  | Edit _, (Blank | Same) ->
      {label = "Enregistrer"; enabled = false; line = None}
  | Edit _, Free _ -> {label = "Enregistrer"; enabled = true; line = None}
  | Edit {tag; _}, Taken t ->
      {
        label = "Fusionner";
        enabled = true;
        line =
          Some
            (Printf.sprintf "« %s » existe déjà : « %s » y sera fusionné."
               t.name tag.name);
      }

let title = function New -> "Nouveau tag" | Edit _ -> "Modifier le tag"

type change =
  | Create of string
  | Rename of {tag : Tag.t; name : string}
  | Merge of {from : Tag_id.t; into : Tag_id.t; plants : Plant_id.t list}
  | Delete of Tag_id.t

let submit ~tags editor text =
  match (editor, check ~tags editor text) with
  | New, Free n -> Some (Create n)
  | Edit {tag; _}, Free name -> Some (Rename {tag; name})
  | Edit {tag; plants}, Taken t ->
      Some (Merge {from = tag.id; into = t.id; plants})
  | New, (Blank | Same | Taken _) | Edit _, (Blank | Same) -> None

let delete = function New -> None | Edit {tag; _} -> Some (Delete tag.id)
let delete_title (t : Tag.t) = Printf.sprintf "Supprimer « %s » ?" t.name

let delete_text ~plants =
  if plants <= 0 then "Aucune plante ne le porte."
  else
    Printf.sprintf "Il sera retiré de %s. Les plantes restent."
      (Fr_text.plural plants "plante" "plantes")

let subtitle = function
  | Error _ -> "Lecture impossible"
  | Ok 0 -> "Aucun tag pour l’instant. Touchez + pour en créer un."
  | Ok n ->
      Fr_text.plural n "tag" "tags" ^ " · touchez pour filtrer la collection"

let edit_label (t : Tag.t) = "Modifier « " ^ t.name ^ " »"

type op =
  | Insert_tag of string
  | Rename_tag of Tag.t * string
  | Delete_tag of Tag_id.t
  | Link of {plant : Plant_id.t; tag : Tag_id.t}
  | Unlink of {plant : Plant_id.t; tag : Tag_id.t}

let plan = function
  | Create n -> [Insert_tag n]
  | Rename {tag; name} -> [Rename_tag (tag, name)]
  | Merge {from; into; plants} ->
      List.map (fun plant -> Link {plant; tag = into}) plants
      @ List.map (fun plant -> Unlink {plant; tag = from}) plants
      @ [Delete_tag from]
  | Delete id -> [Delete_tag id]

let followed change tags =
  List.sort_uniq Tag_id.compare
    (List.filter_map
       (fun id ->
         match change with
         | Delete d when Tag_id.equal d id -> None
         | Merge {from; into; _} when Tag_id.equal from id -> Some into
         | Delete _ | Merge _ | Create _ | Rename _ -> Some id)
       tags)
