module Fold = Herbier_domain.Fold
module Tag = Herbier_domain.Tag

type entry = Pick of Tag.t | Create of string

let key s = Fold.fold (String.trim s)

let suggestions ~tags ~current text =
  let taken = List.map key current in
  let free =
    List.filter (fun ((t : Tag.t), _) -> not (List.mem (key t.name) taken)) tags
  in
  let by_use (_, a) (_, b) = Int.compare b a in
  match String.trim text with
  | "" -> List.map (fun (t, _) -> Pick t) (List.stable_sort by_use free)
  | trimmed -> (
      let k = key trimmed in
      let exact ((t : Tag.t), _) = String.equal (key t.name) k in
      (* The exact match first, even when [Fold.matches] finds no term in it
         (a name of emoji only). *)
      let first, others = List.partition exact free in
      let rest =
        List.filter
          (fun ((t : Tag.t), _) -> Fold.matches ~query:trimmed t.name)
          others
      in
      let picks =
        List.map (fun (t, _) -> Pick t) (first @ List.stable_sort by_use rest)
      in
      let known = List.exists exact tags || List.mem k taken in
      match known with true -> picks | false -> picks @ [Create trimmed])

let name = function Pick (t : Tag.t) -> t.name | Create s -> s

let label = function
  | Pick (t : Tag.t) -> t.name
  | Create s -> Printf.sprintf "Créer « %s »" s
