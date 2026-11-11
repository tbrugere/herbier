module Tag = Herbier_domain.Tag
module Tag_id = Herbier_domain.Ids.Tag_id
module Plant = Herbier_domain.Plant

type tag = Existing of Tag.t | Created of string
type t = {name : string; aliases : string list; tags : tag list}

let of_plant (p : Plant.t) tags =
  {
    name = p.display_name;
    aliases = p.aliases;
    tags = List.map (fun t -> Existing t) tags;
  }

let fold s = String.lowercase_ascii (String.trim s)
let same_text a b = String.equal (fold a) (fold b)

let add_alias a f =
  match String.trim a with
  | "" -> f
  | a when List.exists (same_text a) f.aliases -> f
  | a -> {f with aliases = f.aliases @ [a]}

let remove_alias a f =
  {f with aliases = List.filter (fun x -> not (String.equal x a)) f.aliases}

let tag_name = function Existing t -> t.Tag.name | Created n -> n

let add_tag ~all name f =
  match String.trim name with
  | "" -> f
  | n when List.exists (fun t -> same_text (tag_name t) n) f.tags -> f
  | n -> (
      match List.find_opt (fun (t : Tag.t) -> same_text t.name n) all with
      | Some t -> {f with tags = f.tags @ [Existing t]}
      | None -> {f with tags = f.tags @ [Created n]})

let same_tag a b =
  match (a, b) with
  | Existing x, Existing y -> Tag_id.equal x.id y.id
  | Created x, Created y -> String.equal x y
  | (Existing _ | Created _), _ -> false

let remove_tag t f =
  {f with tags = List.filter (fun x -> not (same_tag x t)) f.tags}

let valid f = not (String.equal (String.trim f.name) "")

type change = {
  plant : Plant.t option;
  create_tags : string list;
  link : Tag_id.t list;
  unlink : Tag_id.t list;
}

let diff ~(before : Plant.t) ~before_tags f =
  let name = String.trim f.name in
  let plant =
    match
      String.equal name before.display_name
      && List.equal String.equal f.aliases before.aliases
    with
    | true -> None
    | false -> Some {before with display_name = name; aliases = f.aliases}
  in
  let existing =
    List.filter_map
      (function Existing t -> Some t.Tag.id | Created _ -> None)
      f.tags
  in
  let had = List.map (fun (t : Tag.t) -> t.id) before_tags in
  let mem id = List.exists (Tag_id.equal id) in
  {
    plant;
    create_tags =
      List.filter_map
        (function Created n -> Some n | Existing _ -> None)
        f.tags;
    link = List.filter (fun id -> not (mem id had)) existing;
    unlink = List.filter (fun id -> not (mem id existing)) had;
  }
