module Link = Herbier_domain.Link
module Gbif = Sources.Gbif
module Wikidata = Sources.Wikidata
module Wikipedia = Sources.Wikipedia
module Taxon = Gbif.Taxon

type unresolved = No_species | Observation_link | Unavailable of string

type outcome =
  | Taxon of Taxon.t
  | Candidates of Taxon.t list
  | Unresolved of {query : string; why : unresolved}

let equal_outcome (a : outcome) (b : outcome) = a = b

let species_ranks =
  [
    "SPECIES";
    "SUBSPECIES";
    "VARIETY";
    "SUBVARIETY";
    "FORM";
    "SUBFORM";
    "INFRASPECIFIC_NAME";
  ]

(* One call and its decoded body; a 404 means the source has no such thing. *)
let fetch request decode =
  let open Step.Syntax in
  let+ response = Step.get request in
  match response with
  | Step.Absent -> Error No_species
  | Step.Failed msg -> Error (Unavailable msg)
  | Step.Body json ->
      Result.map_error
        (fun e -> Unavailable (Decode.error_to_string e))
        (decode json)

let ( let*? ) t f =
  Step.bind t (function Ok v -> f v | Error e -> Step.return (Error e))

let no_species = Step.return (Error No_species)

(* A synonym is replaced by its accepted taxon, one hop only so inconsistent
   data cannot loop. *)
let accepted (t : Taxon.t) =
  match (t.status, t.accepted_key) with
  | Some Gbif.Status.Synonym, Some a when a <> t.key ->
      fetch (Gbif.species ~key:a) Gbif.species_of_json
  | Some (Gbif.Status.Accepted | Doubtful | Synonym | Other _), _ | None, _ ->
      Step.return (Ok t)

let species key =
  let*? t = fetch (Gbif.species ~key) Gbif.species_of_json in
  accepted t

let species_rank (t : Taxon.t) =
  match t.rank with None -> true | Some r -> List.mem r species_ranks

let by_name name =
  match Gbif.match_name ~name with
  | None -> no_species
  | Some request -> (
      let*? m = fetch request Gbif.match_of_json in
      match m with
      | Gbif.Matched {taxon; _} when species_rank taxon -> accepted taxon
      | Gbif.Matched _ | Gbif.Higher_rank _ | Gbif.No_match -> no_species)

let by_entity qid =
  let*? entity = fetch (Wikidata.entity qid) Wikidata.entity_of_json in
  match Option.bind entity (fun (e : Wikidata.Entity.t) -> e.gbif_key) with
  | None -> no_species
  | Some key -> species key

let by_property property value =
  match Wikidata.search ~property ~value with
  | None -> no_species
  | Some request -> (
      let*? qids = fetch request Wikidata.search_of_json in
      match qids with [] -> no_species | qid :: _ -> by_entity qid)

let by_wikipedia ~lang ~title =
  match Wikipedia.summary ~lang ~title with
  | None -> no_species
  | Some request -> (
      let*? (s : Wikipedia.t) = fetch request Wikipedia.summary_of_json in
      match (s.kind, s.wikibase_item) with
      | Wikipedia.Disambiguation, _ | _, None -> no_species
      | (Wikipedia.Standard | Wikipedia.Other _), Some qid -> by_entity qid)

(* For a search, "no such page" is a failure too: GBIF answers [] when
   nothing matches. *)
let taxa request decode =
  let open Step.Syntax in
  let+ response = Step.get request in
  match response with
  | Step.Body json ->
      Result.map_error
        (fun e -> Unavailable (Decode.error_to_string e))
        (decode json)
  | Step.Absent -> Error (Unavailable "not found")
  | Step.Failed msg -> Error (Unavailable msg)

module Candidate = struct
  type t = {taxon : Taxon.t; french : string list}

  let equal (a : t) b = a = b
end

(* The pieces of the French rows, first spelling of each kept: TAXREF joins
   several names in one row. *)
let french (names : Gbif.Vernacular.t list) =
  let pieces =
    List.concat_map
      (fun (v : Gbif.Vernacular.t) ->
        match v.language with
        | Some "fra" ->
            List.filter_map
              (fun piece -> Decode.non_blank (String.trim piece))
              (String.split_on_char ',' v.name)
        | Some _ | None -> [])
      names
  in
  List.rev
    (List.fold_left
       (fun acc name ->
         let lower = String.lowercase_ascii name in
         match List.exists (fun n -> String.lowercase_ascii n = lower) acc with
         | true -> acc
         | false -> name :: acc)
       [] pieces)

(* [extra] in order, without the keys of [listed] nor its own repeats. *)
let distinct ~listed extra =
  let has (t : Taxon.t) = List.exists (fun (u : Taxon.t) -> u.key = t.key) in
  List.rev
    (List.fold_left
       (fun acc t ->
         match has t listed || has t acc with true -> acc | false -> t :: acc)
       [] extra)

(* Both calls whatever [q]: {!search} adds the blank check, {!candidates}
   has none. *)
let searched ~q =
  let open Step.Syntax in
  let* suggested = taxa (Gbif.suggest ~q) Gbif.suggest_of_json in
  let+ vernacular =
    taxa (Gbif.vernacular_search ~q) (fun json ->
        Result.map
          (fun (page : _ Gbif.page) -> page.results)
          (Gbif.vernacular_search_of_json json))
  in
  let names (t : Taxon.t) =
    match vernacular with
    | Error _ -> []
    | Ok results -> (
        match
          List.find_opt (fun ((u : Taxon.t), _) -> u.key = t.key) results
        with
        | None -> []
        | Some (_, names) -> french names)
  in
  let candidate taxon = {Candidate.taxon; french = names taxon} in
  let taxa = Result.map (List.map fst) vernacular in
  Result.map (List.map candidate)
    (match (suggested, taxa) with
    | Ok s, Ok v -> Ok (s @ distinct ~listed:s v)
    (* An empty answer next to a failure is not "nothing found". *)
    | Ok [], Error e | Error e, Ok [] -> Error e
    | Ok s, Error _ -> Ok s
    | Error _, Ok v -> Ok (distinct ~listed:[] v)
    | Error e, Error _ -> Error e)

let search ~q =
  match Decode.non_blank q with
  | None -> Step.return (Ok [])
  | Some _ -> searched ~q

let named (taxon : Taxon.t) =
  let open Step.Syntax in
  let+ response = Step.get (Gbif.vernacular_names ~key:taxon.key) in
  let french, failure =
    match response with
    | Step.Body json -> (
        match Gbif.vernacular_names_of_json json with
        | Ok page -> (french page.results, None)
        | Error e -> ([], Some (Decode.error_to_string e)))
    | Step.Absent -> ([], None)
    | Step.Failed msg -> ([], Some msg)
  in
  ({Candidate.taxon; french}, failure)

let candidates ~q =
  Step.map
    (Result.map (List.map (fun (c : Candidate.t) -> c.taxon)))
    (searched ~q)

let chosen (t : Taxon.t) =
  match t.status with
  | Some Gbif.Status.Synonym -> species t.key
  | Some (Gbif.Status.Accepted | Doubtful | Other _) | None ->
      Step.return (Ok t)

let outcome ~query result =
  Step.map
    (function Ok t -> Taxon t | Error why -> Unresolved {query; why})
    result

let resolve = function
  | Link.Gbif key -> outcome ~query:"" (species key)
  | Link.Plantnet name | Link.Plantuse name ->
      outcome ~query:name (by_name name)
  | Link.Wikipedia {lang; title} ->
      outcome ~query:title (by_wikipedia ~lang ~title)
  | Link.Inpn cd -> outcome ~query:"" (by_property Taxref (string_of_int cd))
  | Link.Tela nn -> outcome ~query:"" (by_property Tela (string_of_int nn))
  | Link.Powo id -> outcome ~query:"" (by_property Powo id)
  | Link.Inat id -> outcome ~query:"" (by_property Inat (string_of_int id))
  | Link.Plantnet_observation _ ->
      Step.return (Unresolved {query = ""; why = Observation_link})
  | Link.Text s -> (
      match Decode.non_blank s with
      | None -> Step.return (Candidates [])
      | Some _ ->
          Step.map
            (function
              | Ok taxa -> Candidates taxa
              | Error why -> Unresolved {query = s; why})
            (candidates ~q:s))
