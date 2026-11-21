module Source = Herbier_domain.Reference.Source
module Tela = Sources.Tela

type habitat = {phrase : string option; chips : string list}

let cited value = Cited.v [Source.Tela] value
let trimmed s = Decode.non_blank (String.trim s)

let life_form (b : Tela.baseflor) =
  Option.map cited (Option.bind b.type_bio trimmed)

let month s =
  match Herbier_net.Json.is_digits s with
  | false -> None
  | true -> (
      match int_of_string_opt s with
      | Some m when m >= 1 && m <= 12 -> Some m
      | Some _ | None -> None)

(* "a-b", wrapping through December when a > b. *)
let range a b =
  match a <= b with
  | true -> List.init (b - a + 1) (fun i -> a + i)
  | false ->
      List.init (12 - a + 1) (fun i -> a + i) @ List.init b (fun i -> i + 1)

let piece p =
  match String.split_on_char '-' (String.trim p) with
  | [a] -> Option.map (fun m -> [m]) (month a)
  | [a; b] -> (
      match (month a, month b) with
      | Some a, Some b -> Some (range a b)
      | None, _ | _, None -> None)
  | _ -> None

let months floraison =
  let rec all acc = function
    | [] -> Some acc
    | p :: rest -> (
        match piece p with
        | None -> None
        | Some ms -> all (List.rev_append ms acc) rest)
  in
  match all [] (String.split_on_char ',' floraison) with
  | None | Some [] -> None
  | Some months -> Some (List.sort_uniq Int.compare months)

let flowering (b : Tela.baseflor) =
  Option.map cited (Option.bind b.floraison months)

(* The label before its first " (": "acidophiles (4,5<pH<5,0)" gives
   "acidophiles". *)
let before_parenthesis s =
  let rec go i =
    match i + 1 < String.length s with
    | false -> s
    | true -> (
        match (s.[i], s.[i + 1]) with
        | ' ', '(' -> String.sub s 0 i
        | _ -> go (i + 1))
  in
  go 0

let habitat (b : Tela.baseflor) =
  let phrase = Option.bind b.carac_ecolo trimmed in
  let chips =
    List_ext.dedup
      (List.filter_map
         (fun label ->
           Option.bind label (fun l -> trimmed (before_parenthesis l)))
         [b.lumiere; b.humidite_edaph; b.reaction_sol; b.nutriments_sol])
  in
  match (phrase, chips) with
  | None, [] -> None
  | phrase, chips -> Some (cited {phrase; chips})
