module Tag_id = Herbier_domain.Ids.Tag_id
module Plant_id = Herbier_domain.Ids.Plant_id

type fate = Kept | Deleted | Merged_into of Tag_id.t

type entry = {
  id : Tag_id.t;
  original : string;
  name : string;
  plants : Plant_id.t list;
  fate : fate;
}

let init =
  List.map (fun (id, name, plants) ->
      {id; original = name; name; plants; fate = Kept})

let visible =
  List.filter (fun e ->
      match e.fate with Kept -> true | Deleted | Merged_into _ -> false)

let mem id = List.exists (Tag_id.equal id)

let union a b =
  List.rev
    (List.fold_left
       (fun acc p ->
         match List.exists (Plant_id.equal p) acc with
         | true -> acc
         | false -> p :: acc)
       (List.rev a) b)

let plants model e =
  List.fold_left
    (fun acc x ->
      match x.fate with
      | Merged_into w when Tag_id.equal w e.id -> union acc x.plants
      | Merged_into _ | Kept | Deleted -> acc)
    e.plants model

let rename id name model =
  match String.trim name with
  | "" -> model
  | name ->
      List.map
        (fun e ->
          match Tag_id.equal e.id id with true -> {e with name} | false -> e)
        model

let delete ids model =
  List.map
    (fun e ->
      match e.fate with
      | Kept when mem e.id ids -> {e with fate = Deleted}
      | Merged_into w when mem w ids -> {e with fate = Deleted}
      | Kept | Deleted | Merged_into _ -> e)
    model

let winner ids model =
  let chosen = List.filter (fun e -> mem e.id ids) (visible model) in
  match chosen with
  | [] | [_] -> None
  | first :: rest ->
      let count e = List.length (plants model e) in
      Some
        (List.fold_left
           (fun best e ->
             match count e > count best with true -> e | false -> best)
           first rest)

let merge ids model =
  match winner ids model with
  | None -> model
  | Some w ->
      let losers = List.filter (fun id -> not (Tag_id.equal id w.id)) ids in
      List.map
        (fun e ->
          match e.fate with
          | Kept when mem e.id losers -> {e with fate = Merged_into w.id}
          | Merged_into l when mem l losers -> {e with fate = Merged_into w.id}
          | Kept | Deleted | Merged_into _ -> e)
        model

let followed model tags =
  List.sort_uniq Tag_id.compare
    (List.filter_map
       (fun id ->
         match List.find_opt (fun e -> Tag_id.equal e.id id) model with
         | Some {fate = Kept; _} | None -> Some id
         | Some {fate = Deleted; _} -> None
         | Some {fate = Merged_into w; _} -> Some w)
       tags)

type op =
  | Rename of Tag_id.t * string
  | Delete of Tag_id.t
  | Link of {plant : Plant_id.t; tag : Tag_id.t}
  | Unlink of {plant : Plant_id.t; tag : Tag_id.t}

let plan model =
  List.concat_map
    (fun e ->
      match e.fate with
      | Kept -> (
          match String.equal e.name e.original with
          | true -> []
          | false -> [Rename (e.id, e.name)])
      | Deleted -> [Delete e.id]
      | Merged_into w ->
          List.map (fun plant -> Link {plant; tag = w}) e.plants
          @ List.map (fun plant -> Unlink {plant; tag = e.id}) e.plants
          @ [Delete e.id])
    model
