(* Plant_link: the plant record after linking to a GBIF taxon. *)

module Plant_link = Herbier_ui_model.Plant_link
module Plant_id = Herbier_domain.Ids.Plant_id
module Plant = Herbier_domain.Plant
module Gbif = Herbier_refs.Sources.Gbif

let utc = Fixtures.utc
let base_plant = Fixtures.base_plant
let digitalis_taxon = Fixtures.digitalis_taxon
let link_at = utc 2026 11 12 10 0

let plant_link =
  [
    Alcotest.test_case "apply: a free-name plant linked to a taxon" `Quick
      (fun () ->
        let p = Plant_link.apply ~at:link_at base_plant digitalis_taxon in
        Alcotest.(check (option int)) "gbif_key" (Some 5414995) p.gbif_key;
        Alcotest.(check (option string))
          "scientific_name (canonical)" (Some "Digitalis purpurea")
          p.scientific_name;
        Alcotest.(check (option string)) "authorship" (Some "L.") p.authorship;
        Alcotest.(check bool)
          "updated_at = at" true
          (Ptime.equal p.updated_at link_at);
        Alcotest.(check string)
          "display_name unchanged" base_plant.display_name p.display_name;
        Alcotest.(check (list string))
          "aliases unchanged" base_plant.aliases p.aliases;
        Alcotest.(check string) "notes unchanged" base_plant.notes p.notes;
        Alcotest.(check bool)
          "notes_updated_at unchanged" true
          (Option.equal Ptime.equal base_plant.notes_updated_at
             p.notes_updated_at);
        Alcotest.(check (option string))
          "cover_photo_id unchanged"
          (Option.map Herbier_domain.Ids.Photo_id.to_string
             base_plant.cover_photo_id)
          (Option.map Herbier_domain.Ids.Photo_id.to_string p.cover_photo_id);
        Alcotest.(check bool)
          "created_at unchanged" true
          (Ptime.equal p.created_at base_plant.created_at));
    Alcotest.test_case "apply: no canonical_name falls back to scientific_name"
      `Quick (fun () ->
        let taxon = {digitalis_taxon with Gbif.Taxon.canonical_name = None} in
        let p = Plant_link.apply ~at:link_at base_plant taxon in
        Alcotest.(check (option string))
          "scientific_name" (Some taxon.scientific_name) p.scientific_name);
    Alcotest.test_case "apply: no authorship replaces an old one with None"
      `Quick (fun () ->
        let taxon = {digitalis_taxon with Gbif.Taxon.authorship = None} in
        let old_plant = {base_plant with Plant.authorship = Some "Old"} in
        let p = Plant_link.apply ~at:link_at old_plant taxon in
        Alcotest.(check (option string)) "authorship" None p.authorship);
    Alcotest.test_case "retires_references" `Quick (fun () ->
        Alcotest.(check bool)
          "no gbif_key: false" false
          (Plant_link.retires_references base_plant digitalis_taxon);
        Alcotest.(check bool)
          "same key: false" false
          (Plant_link.retires_references
             {base_plant with Plant.gbif_key = Some 5414995}
             digitalis_taxon);
        Alcotest.(check bool)
          "other key: true" true
          (Plant_link.retires_references
             {base_plant with Plant.gbif_key = Some 1}
             digitalis_taxon));
    (* apply ?name (free name -> alias), display_name, create. *)
    Alcotest.test_case
      "apply ~name: a free-name plant is renamed, its old name becomes an \
       alias (Done criterion)"
      `Quick (fun () ->
        let free : Plant.t =
          {
            base_plant with
            display_name = "Fleur violette";
            aliases = ["violette"];
          }
        in
        let p =
          Plant_link.apply ~at:link_at ~name:"Digitale pourpre" free
            digitalis_taxon
        in
        Alcotest.(check string) "display_name" "Digitale pourpre" p.display_name;
        Alcotest.(check (list string))
          "aliases: old name prepended, order kept"
          ["Fleur violette"; "violette"]
          p.aliases;
        Alcotest.(check (option int)) "gbif_key" (Some 5414995) p.gbif_key;
        Alcotest.(check (option string))
          "scientific_name" (Some "Digitalis purpurea") p.scientific_name);
    Alcotest.test_case
      "apply ~name equal (trimmed, case-insensitive) to the old name: no alias \
       added, the trimmed spelling is kept"
      `Quick (fun () ->
        let free : Plant.t =
          {
            base_plant with
            display_name = "Fleur Violette";
            aliases = ["violette"];
          }
        in
        let p =
          Plant_link.apply ~at:link_at ~name:" fleur violette " free
            digitalis_taxon
        in
        Alcotest.(check string) "display_name" "fleur violette" p.display_name;
        Alcotest.(check (list string))
          "aliases unchanged" ["violette"] p.aliases);
    Alcotest.test_case
      "apply ~name: the old name already an alias is not duplicated; an alias \
       equal to the new name is removed"
      `Quick (fun () ->
        let free : Plant.t =
          {
            base_plant with
            display_name = "Fleur violette";
            aliases = ["fleur violette"; "violette"];
          }
        in
        let p =
          Plant_link.apply ~at:link_at ~name:"Digitale pourpre" free
            digitalis_taxon
        in
        Alcotest.(check (list string))
          "old name not added twice (already an alias)"
          ["fleur violette"; "violette"]
          p.aliases;
        let free2 : Plant.t =
          {
            base_plant with
            display_name = "Fleur violette";
            aliases = ["digitale pourpre"; "violette"];
          }
        in
        let p2 =
          Plant_link.apply ~at:link_at ~name:"Digitale pourpre" free2
            digitalis_taxon
        in
        Alcotest.(check (list string))
          "an alias equal to the new name is removed, old name prepended"
          ["Fleur violette"; "violette"]
          p2.aliases);
    Alcotest.test_case "apply ~name:\"  \" (blank): name and aliases unchanged"
      `Quick (fun () ->
        let free : Plant.t =
          {
            base_plant with
            display_name = "Fleur violette";
            aliases = ["violette"];
          }
        in
        let p = Plant_link.apply ~at:link_at ~name:"  " free digitalis_taxon in
        Alcotest.(check string) "display_name" "Fleur violette" p.display_name;
        Alcotest.(check (list string)) "aliases" ["violette"] p.aliases);
    Alcotest.test_case
      "apply ~name on an already-linked plant (relink): display name and \
       aliases are untouched"
      `Quick (fun () ->
        let linked : Plant.t =
          {
            base_plant with
            display_name = "Digitalis purpurea";
            aliases = ["violette"];
            scientific_name = Some "Digitalis purpurea L.";
            gbif_key = Some 999;
          }
        in
        let p =
          Plant_link.apply ~at:link_at ~name:"Nouveau nom" linked
            digitalis_taxon
        in
        Alcotest.(check string)
          "display_name unchanged" "Digitalis purpurea" p.display_name;
        Alcotest.(check (list string))
          "aliases unchanged" ["violette"] p.aliases;
        Alcotest.(check (option int))
          "gbif_key updated" (Some 5414995) p.gbif_key);
    Alcotest.test_case
      "display_name: first french, else canonical_name, else scientific_name"
      `Quick (fun () ->
        let cand french taxon : Herbier_refs.Resolve.Candidate.t =
          {taxon; french}
        in
        Alcotest.(check string)
          "first french" "Digitale pourpre"
          (Plant_link.display_name
             (cand ["Digitale pourpre"; "Gantelée"] digitalis_taxon));
        Alcotest.(check string)
          "no french: canonical_name" "Digitalis purpurea"
          (Plant_link.display_name (cand [] digitalis_taxon));
        let no_canonical =
          {digitalis_taxon with Gbif.Taxon.canonical_name = None}
        in
        Alcotest.(check string)
          "no canonical: scientific_name" "Digitalis purpurea L."
          (Plant_link.display_name (cand [] no_canonical)));
    Alcotest.test_case
      "create: a new linked plant, no alias, created_at = updated_at = at"
      `Quick (fun () ->
        let id = Plant_id.fresh () in
        let p =
          Plant_link.create ~id ~at:link_at ~name:"Digitale pourpre"
            digitalis_taxon
        in
        Alcotest.(check bool) "id" true (Plant_id.equal id p.id);
        Alcotest.(check string) "display_name" "Digitale pourpre" p.display_name;
        Alcotest.(check (list string)) "no alias" [] p.aliases;
        Alcotest.(check (option int)) "gbif_key" (Some 5414995) p.gbif_key;
        Alcotest.(check (option string))
          "scientific_name" (Some "Digitalis purpurea") p.scientific_name;
        Alcotest.(check (option string)) "authorship" (Some "L.") p.authorship;
        Alcotest.(check bool)
          "created_at = at" true
          (Ptime.equal p.created_at link_at);
        Alcotest.(check bool)
          "updated_at = at" true
          (Ptime.equal p.updated_at link_at);
        Alcotest.(check bool)
          "deleted_at = None" true
          (Option.is_none p.deleted_at));
  ]
