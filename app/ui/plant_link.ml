module Plant = Herbier_domain.Plant
module Taxon = Herbier_refs.Sources.Gbif.Taxon
module Candidate = Herbier_refs.Resolve.Candidate

let renamed name (p : Plant.t) =
  match (p.scientific_name, String.trim name) with
  | Some _, _ | None, "" -> p
  | None, name ->
      let old = String.trim p.display_name in
      let same = Plant_form.same_text in
      let kept = List.filter (fun a -> not (same a name)) p.aliases in
      let aliases =
        match same old name || List.exists (same old) p.aliases with
        | true -> kept
        | false -> old :: kept
      in
      {p with display_name = name; aliases}

let apply ~at ?name (p : Plant.t) (t : Taxon.t) =
  let p = match name with None -> p | Some name -> renamed name p in
  {
    p with
    gbif_key = Some t.key;
    scientific_name =
      Some (Option.value t.canonical_name ~default:t.scientific_name);
    authorship = t.authorship;
    updated_at = at;
  }

let display_name ({taxon; french} : Candidate.t) =
  match french with
  | name :: _ -> name
  | [] -> Option.value taxon.canonical_name ~default:taxon.scientific_name

let create ~id ~at ~name taxon = apply ~at (Plant.v ~id ~at name) taxon

let retires_references (p : Plant.t) (t : Taxon.t) =
  match p.gbif_key with None -> false | Some k -> k <> t.key
