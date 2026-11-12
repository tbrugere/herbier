module Plant = Herbier_domain.Plant
module Taxon = Herbier_refs.Sources.Gbif.Taxon

let apply ~at (p : Plant.t) (t : Taxon.t) =
  {
    p with
    gbif_key = Some t.key;
    scientific_name =
      Some (Option.value t.canonical_name ~default:t.scientific_name);
    authorship = t.authorship;
    updated_at = at;
  }

let retires_references (p : Plant.t) (t : Taxon.t) =
  match p.gbif_key with None -> false | Some k -> k <> t.key
