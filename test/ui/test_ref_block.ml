(* Native checks of app/ui_model/ref_block.ml: which rows appear for a hand-built
   projection, their order and payloads, and the rows of the two spike species
   over the recorded test/fixtures/ (read, never written). *)

module Ref_block = Herbier_ui_model.Ref_block
module Ref_text = Herbier_ui_model.Ref_text
module Ids = Herbier_domain.Ids
module Reference = Herbier_domain.Reference
module Source = Herbier_domain.Reference.Source
module Organ = Herbier_domain.Reference.Organ
module Decode = Herbier_refs.Decode
module Payload = Herbier_refs.Payload
module Projection = Herbier_refs.Projection
module Gbif = Herbier_refs.Sources.Gbif
module Fixture = Herbier_test_support.Fixture
module Value = Herbier_test_support.Value
module Text = Herbier_test_support.Text

let json name =
  match Decode.json_of_string (Fixture.read name) with
  | Ok j -> j
  | Error e -> failwith (name ^ ": " ^ Decode.error_to_string e)

(* ---------- the two spike species, projected ---------- *)

let plant =
  match Ids.Plant_id.of_string "00000000-0000-4000-8000-000000000001" with
  | Some x -> x
  | None -> invalid_arg "plant id"

let time = Value.time
let t_gbif = time "2026-11-01T10:00:00Z"
let t_other = time "2026-11-01T11:00:00Z"

let reference_row ~source ~fetched_at payload : Reference.t =
  {
    id = Reference.id_of_key ~plant ~source;
    plant_id = plant;
    source;
    fetched_at;
    payload;
    status = Reference.Status.Complete;
    created_at = fetched_at;
    updated_at = fetched_at;
    deleted_at = None;
  }

type species = {
  species_body : Yojson.Safe.t;
  vernacular_names : Yojson.Safe.t;
  distributions : Yojson.Safe.t;
  occurrence_count : Yojson.Safe.t;
  plantnet_media : Yojson.Safe.t;
  search_p846 : Yojson.Safe.t;
  entity : Yojson.Safe.t;
  summary_fr : Yojson.Safe.t;
}

let digitalis =
  {
    species_body = json "gbif_species_5414995.json";
    vernacular_names = json "gbif_vernacular_names_5414995.json";
    distributions = json "gbif_distributions_5414995.json";
    occurrence_count = json "gbif_occurrence_count_5414995.json";
    plantnet_media = json "gbif_plantnet_media_5414995.json";
    search_p846 = json "wikidata_search_p846_5414995.json";
    entity = json "wikidata_entity_Q157555.json";
    summary_fr = json "wikipedia_summary_fr_Digitalis_purpurea.json";
  }

let arnica =
  {
    species_body = json "gbif_species_5405976.json";
    vernacular_names = json "gbif_vernacular_names_5405976.json";
    distributions = json "gbif_distributions_5405976.json";
    occurrence_count = json "gbif_occurrence_count_5405976.json";
    plantnet_media = json "gbif_plantnet_media_5405976.json";
    search_p846 = json "wikidata_search_p846_5405976.json";
    entity = json "wikidata_entity_Q207848.json";
    summary_fr = json "wikipedia_summary_fr_Arnica_montana.json";
  }

let rows_of s =
  [
    reference_row ~source:Source.Gbif ~fetched_at:t_gbif
      (Payload.gbif ~species:(Some s.species_body)
         ~vernacular_names:(Some s.vernacular_names)
         ~distributions:(Some s.distributions)
         ~occurrence_count:(Some s.occurrence_count));
    reference_row ~source:Source.Plantnet ~fetched_at:t_other
      (Payload.plantnet ~media:(Some s.plantnet_media));
    reference_row ~source:Source.Wikidata ~fetched_at:t_other
      (Payload.wikidata ~search:(Some s.search_p846) ~entity:(Some s.entity));
    reference_row ~source:Source.Wikipedia ~fetched_at:t_other
      (Payload.wikipedia ~summary:(Some s.summary_fr) ~uses:None);
  ]

let project_species s =
  Projection.project ~references:(rows_of s) ~plant_refs:[]

(* ---------- the regional layer, over the recorded Tela/INPN fixtures
   ---------- *)

type regional = {
  tela_names : Yojson.Safe.t;
  tela_taxon : Yojson.Safe.t;
  tela_baseflor : Yojson.Safe.t;
  inpn_name : Yojson.Safe.t;
  inpn_status : Yojson.Safe.t;
  inpn_red_list : Yojson.Safe.t;
  inpn_protections : Yojson.Safe.t;
}

let digitalis_regional =
  {
    tela_names = json "tela_names_digitalis_purpurea.json";
    tela_taxon = json "tela_taxon_22437.json";
    tela_baseflor = json "tela_baseflor_22437.json";
    inpn_name = json "inpn_name_94959.json";
    inpn_status = json "inpn_status_94959.json";
    inpn_red_list = json "inpn_red_list_94959.json";
    inpn_protections = json "inpn_protections_94959.json";
  }

let arnica_regional =
  {
    tela_names = json "tela_names_arnica_montana.json";
    tela_taxon = json "tela_taxon_6646.json";
    tela_baseflor = json "tela_baseflor_6646.json";
    inpn_name = json "inpn_name_83874.json";
    inpn_status = json "inpn_status_83874.json";
    inpn_red_list = json "inpn_red_list_83874.json";
    inpn_protections = json "inpn_protections_83874.json";
  }

let full_rows_of s r =
  rows_of s
  @ [
      reference_row ~source:Source.Tela ~fetched_at:t_other
        (Payload.tela ~names:(Some r.tela_names) ~taxon:(Some r.tela_taxon)
           ~baseflor:(Some r.tela_baseflor));
      reference_row ~source:Source.Taxref ~fetched_at:t_other
        (Payload.taxref ~name:(Some r.inpn_name) ~status:(Some r.inpn_status)
           ~red_list:(Some r.inpn_red_list)
           ~protections:(Some r.inpn_protections));
    ]

let project_species_full s r =
  Projection.project ~references:(full_rows_of s r) ~plant_refs:[]

(* One fake thumb path per wanted organ, derived directly from the
   projection's [organ_photos] (not through [Organ_photos.wanted]/[shown]: the
   host-filtering rules are [test_organ_photos.ml]'s job, not this pure UI
   module's). *)
let fake_organ_photos (proj : Projection.t) : (Reference.Image.t * string) list
    =
  match proj.organ_photos with
  | None -> []
  | Some {value; _} ->
      List.filter_map
        (fun (img : Gbif.Image.t) ->
          Option.map
            (fun organ ->
              let path = "refthumbs/fake/" ^ Organ.to_string organ ^ ".jpg" in
              let image : Reference.Image.t =
                {
                  plant_id = plant;
                  source = Source.Plantnet;
                  organ;
                  remote_url = img.url;
                  licence = img.licence;
                  attribution = img.attribution;
                  thumb_path = Some path;
                }
              in
              (image, path))
            img.organ)
        value

(* ---------- testables ---------- *)

let show_row = function
  | Ref_block.Names {french; others; sources} ->
      Printf.sprintf "Names french=[%s] others=[%s] / %s"
        (String.concat "," french)
        (String.concat "; "
           (List.map
              (fun (v : Projection.vernacular) ->
                Projection.Lang.to_string v.lang
                ^ ":"
                ^ String.concat "," v.names)
              others))
        sources
  | Ref_block.Life_form {text; sources} ->
      Printf.sprintf "Life_form %s / %s" text sources
  | Ref_block.Origin {native; introduced; sources} ->
      Printf.sprintf "Origin %s | %s / %s"
        (Option.value ~default:"-" native)
        (Option.value ~default:"-" introduced)
        sources
  | Ref_block.En_france {chips; places; sources} ->
      Printf.sprintf "En_france [%s] %s / %s" (String.concat "," chips)
        (Option.value ~default:"-" places)
        sources
  | Ref_block.Red_list {label; chip; sources} ->
      Printf.sprintf "Red_list (%s) %s / %s" label chip sources
  | Ref_block.Flowering {months; text; sources} ->
      Printf.sprintf "Flowering %s %s / %s"
        (String.concat "," (List.map string_of_int months))
        text sources
  | Ref_block.Habitat {phrase; chips; sources} ->
      Printf.sprintf "Habitat %s [%s] / %s"
        (Option.value ~default:"-" phrase)
        (String.concat "," chips) sources
  | Ref_block.Toxicity {text; sources} ->
      Printf.sprintf "Toxicity %s / %s" text sources
  | Ref_block.Organ_photos {photos; credits; sources} ->
      Printf.sprintf "Organ_photos [%s] %s / %s"
        (String.concat ","
           (List.map (fun (o, p) -> Organ.to_string o ^ "=" ^ p) photos))
        credits sources
  | Ref_block.Uses uses ->
      let plantuse, wikipedia = Ref_block.uses_parts uses in
      let plantuse_s =
        match plantuse with
        | None -> "-"
        | Some {chips; line; url} ->
            Printf.sprintf "[%s] %s / %s" (String.concat "," chips)
              (Option.value ~default:"-" line)
              url
      in
      let wikipedia_s =
        match wikipedia with
        | None -> "-"
        | Some {paragraph; url} -> Printf.sprintf "%s / %s" paragraph url
      in
      Printf.sprintf "Uses plantuse=(%s) wikipedia=(%s)" plantuse_s wikipedia_s

let ctor_name = function
  | Ref_block.Names _ -> "Names"
  | Ref_block.Life_form _ -> "Life_form"
  | Ref_block.Origin _ -> "Origin"
  | Ref_block.En_france _ -> "En_france"
  | Ref_block.Red_list _ -> "Red_list"
  | Ref_block.Flowering _ -> "Flowering"
  | Ref_block.Habitat _ -> "Habitat"
  | Ref_block.Toxicity _ -> "Toxicity"
  | Ref_block.Organ_photos _ -> "Organ_photos"
  | Ref_block.Uses _ -> "Uses"

let ctors rows = List.map ctor_name rows

let sources_of name rows =
  match List.find_opt (fun r -> String.equal (ctor_name r) name) rows with
  | Some
      ( Ref_block.Names {sources; _}
      | Life_form {sources; _}
      | Origin {sources; _}
      | En_france {sources; _}
      | Red_list {sources; _}
      | Flowering {sources; _}
      | Habitat {sources; _}
      | Toxicity {sources; _}
      | Organ_photos {sources; _} ) ->
      sources
  | Some (Uses _) -> Alcotest.failf "a Uses row has no single sources line"
  | None -> Alcotest.failf "no %s row" name

(* ---------- both spike species, rendered ---------- *)

let digitalis_renders () =
  let proj = project_species digitalis in
  let photos = fake_organ_photos proj in
  Alcotest.(check int) "3 organ photos (no fruit)" 3 (List.length photos);
  let rows = Ref_block.rows proj ~organ_photos:photos in
  Alcotest.(check (list string))
    "Names, Origin, Toxicity, Organ_photos; no Life_form, Red_list, Flowering, \
     Habitat"
    ["Names"; "Origin"; "Toxicity"; "Organ_photos"]
    (ctors rows);
  (match
     List.find_opt
       (function Ref_block.Organ_photos _ -> true | _ -> false)
       rows
   with
  | Some (Ref_block.Organ_photos {photos; credits; sources}) ->
      Alcotest.(check int)
        "3 tiles (fleur, feuille, port)" 3 (List.length photos);
      Alcotest.(check (list string))
        "organs"
        ["flower"; "leaf"; "habit"]
        (List.map (fun (o, _) -> Organ.to_string o) photos);
      Alcotest.(check (list string))
        "tile paths are the shown thumbnails"
        [
          "refthumbs/fake/flower.jpg";
          "refthumbs/fake/leaf.jpg";
          "refthumbs/fake/habit.jpg";
        ]
        (List.map snd photos);
      Alcotest.(check string)
        "sources line (no \"hors-ligne\" mention)" "Pl@ntNet" sources;
      Alcotest.(check string)
        "credits: the three shown images' holders and licences, in tile order"
        "Photos : laurencechabalier (cc-by-sa), Iris Selcho (cc-by-sa), Else \
         Nolden (cc-by-sa)"
        credits
  | _ -> Alcotest.fail "no Organ_photos row");
  List.iter
    (fun (name, expected) ->
      Alcotest.(check string)
        (name ^ " sources") expected (sources_of name rows))
    [
      ("Names", "Plantaginaceae · GBIF, Wikidata");
      ("Origin", "GBIF");
      ("Toxicity", "Wikipédia");
    ];
  match Ref_block.footer proj ~organ_photos:photos with
  | Some {sources; _} ->
      Alcotest.(check bool)
        "the footer's GBIF line links to the species page" true
        (List.exists
           (fun (s : Ref_block.source) ->
             s.name = "GBIF"
             && s.url = Some "https://www.gbif.org/species/5414995")
           sources)
  | None -> Alcotest.fail "no footer"

let arnica_renders () =
  let proj = project_species arnica in
  let photos = fake_organ_photos proj in
  Alcotest.(check int) "4 organ photos" 4 (List.length photos);
  let rows = Ref_block.rows proj ~organ_photos:photos in
  Alcotest.(check (list string))
    "Names, Origin, Red_list, Organ_photos; no Toxicity"
    ["Names"; "Origin"; "Red_list"; "Organ_photos"]
    (ctors rows);
  (match
     List.find_opt (function Ref_block.Red_list _ -> true | _ -> false) rows
   with
  | Some (Ref_block.Red_list {label; chip; _}) ->
      Alcotest.(check string)
        "label without an En France row" "Liste rouge" label;
      Alcotest.(check string) "chip" "LC · préoccupation mineure" chip
  | _ -> Alcotest.fail "no Red_list row");
  match
    List.find_opt
      (function Ref_block.Organ_photos _ -> true | _ -> false)
      rows
  with
  | Some (Ref_block.Organ_photos {photos; _}) ->
      Alcotest.(check int) "4 tiles" 4 (List.length photos)
  | _ -> Alcotest.fail "no Organ_photos row"

let digitalis_origin_in_french () =
  let proj = project_species digitalis in
  let rows = Ref_block.rows proj ~organ_photos:(fake_organ_photos proj) in
  (match
     List.find_opt (function Ref_block.Origin _ -> true | _ -> false) rows
   with
  | Some (Ref_block.Origin {native; introduced}) ->
      Alcotest.(check (option string))
        "native: the first five in French order, then the count"
        (Some "Allemagne, Belgique, Corse, Espagne, France et 7 autres") native;
      Alcotest.(check (option string))
        "introduced: in French, in French order"
        (Some
           "Açores, Argentine du Nord-Est, Argentine du Nord-Ouest, Argentine \
            du Sud, Arkansas et 75 autres")
        introduced
  | _ -> Alcotest.fail "no Origin row");
  Alcotest.(check bool)
    "no row's text mentions « hors-ligne »" false
    (List.exists (fun r -> Text.contains ~sub:"hors-ligne" (show_row r)) rows)

let digitalis_offline_before_any_download () =
  let proj = project_species digitalis in
  let rows = Ref_block.rows proj ~organ_photos:[] in
  Alcotest.(check (list string))
    "no Organ_photos row; the other rows are unchanged"
    ["Names"; "Origin"; "Toxicity"]
    (ctors rows)

(* ---------- the regional layer adds En_france, Life_form, Flowering,
   Habitat ---------- *)

let digitalis_full_renders () =
  let proj = project_species_full digitalis digitalis_regional in
  let rows = Ref_block.rows proj ~organ_photos:(fake_organ_photos proj) in
  Alcotest.(check (list string))
    "Names, Life_form, Origin, En_france, Flowering, Habitat, Toxicity, \
     Organ_photos (no Red_list: no global IUCN row)"
    [
      "Names";
      "Life_form";
      "Origin";
      "En_france";
      "Flowering";
      "Habitat";
      "Toxicity";
      "Organ_photos";
    ]
    (ctors rows);
  List.iter
    (fun (expected, actual) -> Alcotest.(check string) expected expected actual)
    [
      ( "Life_form Hémicryptophytes (>= 1m) bisannuels / Tela Botanica",
        show_row
          (List.find
             (function Ref_block.Life_form _ -> true | _ -> false)
             rows) );
      ( "En_france [Indigène,Non protégée,Liste rouge : LC · préoccupation \
         mineure] - / INPN",
        show_row
          (List.find
             (function Ref_block.En_france _ -> true | _ -> false)
             rows) );
      ( "Flowering 5,6,7,8,9 mai – septembre / Tela Botanica",
        show_row
          (List.find
             (function Ref_block.Flowering _ -> true | _ -> false)
             rows) );
    ];
  match
    List.find (function Ref_block.Habitat _ -> true | _ -> false) rows
  with
  | Ref_block.Habitat {phrase; chips; sources} ->
      Alcotest.(check (option string))
        "phrase (the recorded carac_ecolo)"
        (Some
           "mégaphorbiaies pionnières de clairières acidophiles \
            planitiaires-collinéennes")
        phrase;
      Alcotest.(check (list string))
        "chips: the four ve_* labels cut before \" (\""
        ["hémihéliophiles"; "mésohydriques"; "acidophiles"; "méso-eutrophiles"]
        chips;
      Alcotest.(check string) "sources" "Tela Botanica" sources
  | _ -> Alcotest.fail "no Habitat row"

let arnica_full_renders () =
  let proj = project_species_full arnica arnica_regional in
  let rows = Ref_block.rows proj ~organ_photos:(fake_organ_photos proj) in
  Alcotest.(check (list string))
    "Names, Life_form, Origin, En_france, Red_list, Flowering, Habitat, \
     Organ_photos (no Toxicity)"
    [
      "Names";
      "Life_form";
      "Origin";
      "En_france";
      "Red_list";
      "Flowering";
      "Habitat";
      "Organ_photos";
    ]
    (ctors rows);
  (match
     List.find (function Ref_block.En_france _ -> true | _ -> false) rows
   with
  | Ref_block.En_france {chips; places; sources} ->
      Alcotest.(check (list string))
        "chips"
        [
          "Indigène";
          "Protégée localement";
          "Liste rouge : LC · préoccupation mineure";
        ]
        chips;
      Alcotest.(check (option string))
        "places (5 shown, et 2 autres)"
        (Some
           "Protection : Centre-Val de Loire, Bourgogne, Aquitaine, Le Cher, \
            Le Lot et 2 autres")
        places;
      Alcotest.(check string) "sources" "INPN" sources
  | _ -> Alcotest.fail "no En_france row");
  (match
     List.find (function Ref_block.Red_list _ -> true | _ -> false) rows
   with
  | Ref_block.Red_list {label; _} ->
      Alcotest.(check string)
        "label next to the French red list" "Liste rouge mondiale" label
  | _ -> Alcotest.fail "no Red_list row");
  match
    List.find (function Ref_block.Flowering _ -> true | _ -> false) rows
  with
  | Ref_block.Flowering {months; text; _} ->
      Alcotest.(check (list int)) "months" [6; 7] months;
      Alcotest.(check string) "text" "juin – juillet" text
  | _ -> Alcotest.fail "no Flowering row"

(* A projection built from only the four global rows (no Taxref/Tela row)
   gives exactly the rows the global-only tests above expect: the regional
   layer disappears cleanly when it has nothing (renders as before). *)
let projection_without_regional_rows_renders_as_before () =
  Alcotest.(check (list string))
    "Digitalis, four rows only"
    ["Names"; "Origin"; "Toxicity"; "Organ_photos"]
    (ctors
       (Ref_block.rows
          (project_species digitalis)
          ~organ_photos:(fake_organ_photos (project_species digitalis))));
  Alcotest.(check (list string))
    "Arnica, four rows only"
    ["Names"; "Origin"; "Red_list"; "Organ_photos"]
    (ctors
       (Ref_block.rows (project_species arnica)
          ~organ_photos:(fake_organ_photos (project_species arnica))))

(* ---------- rows: condition and order, hand-built ---------- *)

let empty_t = Projection.project ~references:[] ~plant_refs:[]
let cited value : _ Projection.cited = {value; sources = []}
let area code name : Projection.area = {code; name}

let no_rows_no_photos () =
  Alcotest.(check (list string))
    "[]" []
    (ctors (Ref_block.rows empty_t ~organ_photos:[]))

let names_from_family_alone () =
  let t =
    {
      empty_t with
      Projection.taxon =
        Some
          (cited
             {
               Gbif.Taxon.key = 1;
               scientific_name = "X y";
               canonical_name = None;
               authorship = None;
               rank = None;
               status = None;
               accepted_key = None;
               family = Some "Plantaginaceae";
               vernacular_name = None;
             });
    }
  in
  Alcotest.(check (list string))
    "Names, from the family alone" ["Names"]
    (ctors (Ref_block.rows t ~organ_photos:[]))

let origin_only_introduced_has_no_native () =
  let t =
    {
      empty_t with
      Projection.origin =
        Some (cited {Projection.native = []; introduced = [area None "Chile"]});
    }
  in
  match Ref_block.rows t ~organ_photos:[] with
  | [Ref_block.Origin {native; introduced; _}] ->
      Alcotest.(check (option string)) "native is None" None native;
      Alcotest.(check (option string))
        "introduced is set" (Some "Chile") introduced
  | rows ->
      Alcotest.failf "expected one Origin row, got %s"
        (String.concat ", " (ctors rows))

let red_list_not_evaluated_gives_no_row () =
  let t = {empty_t with Projection.red_list = Some (cited "NOT_EVALUATED")} in
  Alcotest.(check (list string))
    "[]" []
    (ctors (Ref_block.rows t ~organ_photos:[]))

let cited_by sources value : _ Projection.cited = {value; sources}

let en_france_rows ?status ?protection ?red_list () =
  let taxref value = cited_by [Source.Taxref] value in
  List.map show_row
    (Ref_block.rows
       {
         empty_t with
         fr_status = Option.map taxref status;
         fr_protection = Option.map taxref protection;
         fr_red_list = Option.map taxref red_list;
       }
       ~organ_photos:[])

let en_france_lone_not_protected_no_row () =
  Alcotest.(check (list string))
    "INPN knows the taxon, nothing about France: no row" []
    (en_france_rows ~protection:Projection.Not_protected ())

let en_france_no_chip_no_row () =
  Alcotest.(check (list string))
    "unknown status, red list NA: no row" []
    (en_france_rows ~status:"FOO"
       ~red_list:{Projection.category = "NA"; description = None}
       ())

let en_france_national_alone () =
  Alcotest.(check (list string))
    "one chip"
    ["En_france [Protégée en France] - / INPN"]
    (en_france_rows ~protection:Projection.National ())

let en_france_not_protected_with_red_list () =
  Alcotest.(check (list string))
    "« Non protégée » kept next to a red-list chip"
    ["En_france [Non protégée,Liste rouge : VU · vulnérable] - / INPN"]
    (en_france_rows ~protection:Projection.Not_protected
       ~red_list:{Projection.category = "VU"; description = None}
       ())

let every_constructor_present_and_in_order () =
  let t =
    {
      Projection.fetched_at = None;
      taxon =
        Some
          (cited_by [Source.Gbif]
             {
               Gbif.Taxon.key = 1;
               scientific_name = "X y";
               canonical_name = None;
               authorship = None;
               rank = None;
               status = None;
               accepted_key = None;
               family = Some "Plantaginaceae";
               vernacular_name = None;
             });
      vernacular = None;
      life_form = Some (cited_by [Source.Wikipedia] "Herbacée");
      fr_status = Some (cited_by [Source.Taxref] "PRESENT");
      fr_protection =
        Some (cited_by [Source.Taxref] (Projection.Local ["Alsace"; "Le Cher"]));
      fr_red_list =
        Some
          (cited_by [Source.Taxref]
             {Projection.category = "LC"; description = None});
      origin =
        Some
          (cited_by [Source.Gbif]
             {
               Projection.native = [area None "France"];
               introduced = [area None "Chile"];
             });
      red_list = Some (cited_by [Source.Gbif] "LEAST_CONCERN");
      flowering_months = Some (cited_by [Source.Tela] [6; 7; 8]);
      habitat =
        Some
          (cited_by [Source.Tela]
             {Projection.phrase = Some "Prairies"; chips = ["mi-ombre"]});
      toxicity = Some (cited_by [Source.Wikipedia] "Toxique.");
      plantuse_uses =
        Some
          (cited_by [Source.Plantuse]
             {
               Projection.Uses.summary = ["médicinal"];
               text = None;
               title = "X y";
               url = "https://plantuse.plantnet.org/fr/X_y";
             });
      wikipedia_uses =
        Some
          (cited_by [Source.Wikipedia]
             {
               Projection.Uses.paragraph = "Utilisée en phytothérapie.";
               section = "Usages";
               lang = "fr";
               title = "X y";
               url = "https://fr.wikipedia.org/wiki/X_y";
             });
      organ_photos = None;
      links =
        [
          {
            Projection.source = Source.Gbif;
            url = "https://www.gbif.org/species/1";
          };
        ];
      problems = [];
    }
  in
  let fake_photos =
    [
      ( ({
           Reference.Image.plant_id = plant;
           source = Source.Plantnet;
           organ = Organ.Flower;
           remote_url = "https://bs.plantnet.org/image/o/x";
           licence = "cc-by-sa";
           attribution = "A";
           thumb_path = Some "p";
         }
          : Reference.Image.t),
        "p" );
    ]
  in
  Alcotest.(check (list string))
    "every constructor appears, in the fixed order"
    [
      "Names";
      "Life_form";
      "Origin";
      "En_france";
      "Red_list";
      "Flowering";
      "Habitat";
      "Toxicity";
      "Uses";
      "Organ_photos";
    ]
    (ctors (Ref_block.rows t ~organ_photos:fake_photos));
  Alcotest.(check (list string))
    "every payload, sources lines included"
    [
      "Names french=[] others=[] / Plantaginaceae · GBIF";
      "Life_form Herbacée / Wikipédia";
      "Origin France | Chile / GBIF";
      "En_france [Indigène,Protégée localement,Liste rouge : LC · \
       préoccupation mineure] Protection : Alsace, Le Cher / INPN";
      "Red_list (Liste rouge mondiale) LC · préoccupation mineure / GBIF";
      "Flowering 6,7,8 juin – août / Tela Botanica";
      "Habitat Prairies [mi-ombre] / Tela Botanica";
      "Toxicity Toxique. / Wikipédia";
      "Uses plantuse=([médicinal] - / https://plantuse.plantnet.org/fr/X_y) \
       wikipedia=(Utilisée en phytothérapie. / \
       https://fr.wikipedia.org/wiki/X_y)";
      "Organ_photos [flower=p] Photos : A (cc-by-sa) / Pl@ntNet";
    ]
    (List.map show_row (Ref_block.rows t ~organ_photos:fake_photos))

let habitat_chips_alone () =
  let t =
    {
      empty_t with
      Projection.habitat =
        Some (cited {Projection.phrase = None; chips = ["mi-ombre"; "humide"]});
    }
  in
  Alcotest.(check (list string))
    "a Habitat row with no phrase"
    ["Habitat - [mi-ombre,humide] / "]
    (List.map show_row (Ref_block.rows t ~organ_photos:[]))

let digitalis_names_french_and_others () =
  let proj = project_species digitalis in
  let rows = Ref_block.rows proj ~organ_photos:(fake_organ_photos proj) in
  match
    List.find_opt (function Ref_block.Names _ -> true | _ -> false) rows
  with
  | Some (Ref_block.Names {french; others; _}) ->
      Alcotest.(check (list string))
        "french: the fr vernacular names"
        ["Digitale pourpre"; "Digitale pourprée"; "grande digitale"]
        french;
      Alcotest.(check (list string))
        "others: en, de, it in order, no fr entry" ["en"; "de"; "it"]
        (List.map
           (fun (v : Projection.vernacular) -> Projection.Lang.to_string v.lang)
           others)
  | _ -> Alcotest.fail "no Names row"

let names_only_en_has_no_french_others_holds_it () =
  let t =
    {
      empty_t with
      Projection.vernacular =
        Some
          (cited [{Projection.lang = Projection.Lang.En; names = ["Foxglove"]}]);
    }
  in
  match Ref_block.rows t ~organ_photos:[] with
  | [Ref_block.Names {french; others; _}] ->
      Alcotest.(check (list string)) "french is []" [] french;
      Alcotest.(check (list string))
        "others holds en, shown directly (no fr to hide it behind)" ["en"]
        (List.map
           (fun (v : Projection.vernacular) -> Projection.Lang.to_string v.lang)
           others)
  | rows ->
      Alcotest.failf "expected one Names row, got %s"
        (String.concat ", " (ctors rows))

let names_only_fr_has_no_others () =
  let t =
    {
      empty_t with
      Projection.vernacular =
        Some
          (cited [{Projection.lang = Projection.Lang.Fr; names = ["Digitale"]}]);
    }
  in
  match Ref_block.rows t ~organ_photos:[] with
  | [Ref_block.Names {french; others; _}] ->
      Alcotest.(check (list string))
        "french holds the fr names" ["Digitale"] french;
      Alcotest.(check int) "others is []" 0 (List.length others)
  | rows ->
      Alcotest.failf "expected one Names row, got %s"
        (String.concat ", " (ctors rows))

let names_sources_deduplicated_in_source_order () =
  let t =
    {
      empty_t with
      Projection.taxon =
        Some
          (cited_by [Source.Gbif]
             {
               Gbif.Taxon.key = 1;
               scientific_name = "X y";
               canonical_name = None;
               authorship = None;
               rank = None;
               status = None;
               accepted_key = None;
               family = Some "F";
               vernacular_name = None;
             });
      vernacular =
        Some
          (cited_by
             [Source.Wikidata; Source.Gbif]
             [{Projection.lang = Projection.Lang.Fr; names = ["Digitale"]}]);
    }
  in
  Alcotest.(check (list string))
    "GBIF once, before Wikidata; the fr vernacular goes to french, not others"
    ["Names french=[Digitale] others=[] / F · GBIF, Wikidata"]
    (List.map show_row (Ref_block.rows t ~organ_photos:[]))

(* ---------- run ---------- *)

(* ---------- Uses row over the recorded fixtures ---------- *)

let find_uses rows =
  List.find_map
    (function
      | Ref_block.Uses uses -> Some (Ref_block.uses_parts uses) | _ -> None)
    rows

(* [rows_of s] without its Wikipedia row (its uses member is added back
   separately, next to the summary it builds on). *)
let without_wikipedia s =
  List.filter
    (fun (r : Reference.t) ->
      not (String.equal (Source.to_string r.source) "wikipedia"))
    (rows_of s)

let wikipedia_row_with_uses s uses_file =
  reference_row ~source:Source.Wikipedia ~fetched_at:t_other
    (Payload.wikipedia ~summary:(Some s.summary_fr)
       ~uses:(Some (json uses_file)))

let plantuse_row page_file =
  reference_row ~source:Source.Plantuse ~fetched_at:t_other
    (Payload.plantuse ~page:(Some (json page_file)))

let digitalis_uses_row () =
  (* Digitalis's fr extract has no uses section; the en one does,
     so the stored uses member is the en extract. *)
  let rows_with_uses =
    without_wikipedia digitalis
    @ [
        wikipedia_row_with_uses digitalis
          "wikipedia_extract_en_Digitalis_purpurea.json";
        plantuse_row "plantuse_page_digitalis_purpurea.json";
      ]
  in
  let proj = Projection.project ~references:rows_with_uses ~plant_refs:[] in
  let rows = Ref_block.rows proj ~organ_photos:(fake_organ_photos proj) in
  (* Toxicity, then Uses, then Organ_photos: the texts stay together, photos
     close the block. *)
  Alcotest.(check (list string))
    "Names, Origin, Toxicity, Uses, Organ_photos"
    ["Names"; "Origin"; "Toxicity"; "Uses"; "Organ_photos"]
    (ctors rows);
  match find_uses rows with
  | None -> Alcotest.fail "no Uses row"
  | Some (plantuse, wikipedia) -> (
      (match plantuse with
      | Some {chips; line; url} ->
          Alcotest.(check (list string)) "chips" ["médicinal"] chips;
          Alcotest.(check bool) "line is None" true (Option.is_none line);
          Alcotest.(check string)
            "url" "https://plantuse.plantnet.org/fr/Digitalis_purpurea" url
      | None -> Alcotest.fail "plantuse is None");
      match wikipedia with
      | Some {paragraph; _} ->
          (match
             Ref_block.footer proj ~organ_photos:(fake_organ_photos proj)
           with
          | Some {sources; _} ->
              Alcotest.(check bool)
                "the footer's extract line (en: the (en) marker)" true
                (List.exists
                   (fun (l : Ref_block.source) ->
                     l.name = "Wikipédia (en) · « Medicinal use »"
                     && l.licence = Some "CC BY-SA"
                     && l.note = Some "extrait automatique")
                   sources)
          | None -> Alcotest.fail "no footer");
          Alcotest.(check bool)
            "paragraph starts with Extracted from the leaves" true
            (String.starts_with ~prefix:"Extracted from the leaves" paragraph)
      | None -> Alcotest.fail "wikipedia is None")

let arnica_uses_row () =
  (* Arnica's fr extract has a uses section:
     the stored uses member is the fr extract. Its plantuse page has no box
     nor prose. *)
  let rows_with_uses =
    without_wikipedia arnica
    @ [
        wikipedia_row_with_uses arnica
          "wikipedia_extract_fr_Arnica_des_montagnes.json";
        plantuse_row "plantuse_page_arnica_montana.json";
      ]
  in
  let proj = Projection.project ~references:rows_with_uses ~plant_refs:[] in
  let rows = Ref_block.rows proj ~organ_photos:(fake_organ_photos proj) in
  match find_uses rows with
  | None -> Alcotest.fail "no Uses row"
  | Some (plantuse, wikipedia) -> (
      Alcotest.(check bool)
        "no box nor prose on the plantuse page: plantuse is None" true
        (Option.is_none plantuse);
      match wikipedia with
      | Some _ -> ()
      | None -> Alcotest.fail "wikipedia is None")

let neither_has_no_uses_row () =
  (* fr extract with no usable section (Digitalis's), no plantuse row at
     all: neither source has uses data. *)
  let rows_with_uses =
    without_wikipedia digitalis
    @ [
        wikipedia_row_with_uses digitalis
          "wikipedia_extract_fr_Digitalis_purpurea.json";
      ]
  in
  let proj = Projection.project ~references:rows_with_uses ~plant_refs:[] in
  let rows = Ref_block.rows proj ~organ_photos:(fake_organ_photos proj) in
  Alcotest.(check bool) "no Uses row" true (Option.is_none (find_uses rows))

let source_name_plantuse () =
  Alcotest.(check string)
    "Pl@ntUse" "Pl@ntUse"
    (Ref_text.source_name Source.Plantuse)

(* ---------- the « Sources » footer (M8.86) ---------- *)

let link source url : Projection.link = {source; url}

let show_source (l : Ref_block.source) =
  String.concat " | "
    [
      l.name;
      Option.value ~default:"-" l.url;
      Option.value ~default:"-" l.licence;
      Option.value ~default:"-" l.note;
    ]

let footer_sources t ~photos =
  match Ref_block.footer t ~organ_photos:photos with
  | Some f -> List.map show_source f.sources
  | None -> Alcotest.fail "no footer"

let footer_links t ~photos =
  match Ref_block.footer t ~organ_photos:photos with
  | Some f -> List.map (fun (l : Ref_block.link) -> l.label) f.links
  | None -> Alcotest.fail "no footer"

let footer_dedup_and_order () =
  let t =
    {
      empty_t with
      vernacular =
        Some
          (cited_by
             [Source.Gbif; Source.Wikidata]
             [{Projection.lang = Projection.Lang.Fr; names = ["Digitale"]}]);
      life_form = Some (cited_by [Source.Tela] "Herbacée");
      flowering_months = Some (cited_by [Source.Tela] [6]);
      habitat =
        Some
          (cited_by [Source.Tela] {Projection.phrase = Some "Bois"; chips = []});
      origin =
        Some
          (cited_by [Source.Gbif]
             {Projection.native = [area None "France"]; introduced = []});
      toxicity = Some (cited_by [Source.Wikipedia] "Toxique.");
      links =
        [
          link Source.Gbif "https://www.gbif.org/species/1";
          link Source.Wikipedia "https://fr.wikipedia.org/wiki/X_y";
          link Source.Powo "https://powo.science.kew.org/taxon/1";
          link Source.Tela "https://www.tela-botanica.org/bdtfx-nn-1";
        ];
    }
  in
  Alcotest.(check (list string))
    "each source once, in Projection.link_order, with its link and licence"
    [
      "GBIF | https://www.gbif.org/species/1 | - | -";
      "Wikipédia | https://fr.wikipedia.org/wiki/X_y | CC BY-SA | -";
      "Tela Botanica | https://www.tela-botanica.org/bdtfx-nn-1 | - | -";
      "Wikidata | - | - | -";
    ]
    (footer_sources t ~photos:[]);
  Alcotest.(check (list string))
    "the links of sources no row cites stay, as links" ["POWO ↗"]
    (footer_links t ~photos:[])

let footer_only_shown_rows () =
  let t =
    {
      empty_t with
      life_form = Some (cited_by [Source.Tela] "Herbacée");
      (* No row: « NOT_EVALUATED » and a lone « Non protégée ». *)
      red_list = Some (cited_by [Source.Eppo] "NOT_EVALUATED");
      fr_protection = Some (cited_by [Source.Taxref] Projection.Not_protected);
    }
  in
  Alcotest.(check (list string))
    "only the sources of the rows shown"
    ["Tela Botanica | - | - | -"]
    (footer_sources t ~photos:[])

let photo organ licence : Reference.Image.t * string =
  ( {
      Reference.Image.plant_id = plant;
      source = Source.Plantnet;
      organ;
      remote_url = "https://bs.plantnet.org/image/o/" ^ Organ.to_string organ;
      licence;
      attribution = "A";
      thumb_path = Some "p";
    },
    "p" )

let footer_licences () =
  let t =
    {
      empty_t with
      toxicity = Some (cited_by [Source.Wikipedia] "Toxique.");
      plantuse_uses =
        Some
          (cited_by [Source.Plantuse]
             {
               Projection.Uses.summary = ["médicinal"];
               text = None;
               title = "X y";
               url = "https://plantuse.plantnet.org/fr/X_y";
             });
      wikipedia_uses =
        Some
          (cited_by [Source.Wikipedia]
             {
               Projection.Uses.paragraph = "Utilisée en phytothérapie.";
               section = "Usages et vertus";
               lang = "fr";
               title = "X y";
               url = "https://fr.wikipedia.org/wiki/X_y";
             });
      links = [link Source.Wikipedia "https://fr.wikipedia.org/wiki/X_y"];
    }
  in
  let photos =
    [
      photo Organ.Flower "cc-by-sa";
      photo Organ.Leaf "cc-by";
      photo Organ.Fruit "cc-by-sa";
      photo Organ.Habit " ";
    ]
  in
  Alcotest.(check (list string))
    "Pl@ntNet: the photos' distinct licences; Wikipedia's extract after the \
     article, its section in the link, « extrait automatique »; Pl@ntUse's \
     page"
    [
      "Pl@ntNet | - | CC BY-SA, CC BY | -";
      "Wikipédia | https://fr.wikipedia.org/wiki/X_y | CC BY-SA | -";
      "Wikipédia · « Usages et vertus » | \
       https://fr.wikipedia.org/wiki/X_y#Usages_et_vertus | CC BY-SA | extrait \
       automatique";
      "Pl@ntUse | https://plantuse.plantnet.org/fr/X_y | CC BY-SA | -";
    ]
    (footer_sources t ~photos);
  Alcotest.(check (list string))
    "no link left: every link's source has a line" [] (footer_links t ~photos)

let footer_extract_en () =
  let t =
    {
      empty_t with
      wikipedia_uses =
        Some
          (cited_by [Source.Wikipedia]
             {
               Projection.Uses.paragraph = "Used.";
               section = "Uses";
               lang = "en";
               title = "X y";
               url = "https://en.wikipedia.org/wiki/X_y";
             });
    }
  in
  Alcotest.(check (list string))
    "the extract alone, (en) marked, no plain Wikipédia line"
    [
      "Wikipédia (en) · « Uses » | https://en.wikipedia.org/wiki/X_y#Uses | CC \
       BY-SA | extrait automatique";
    ]
    (footer_sources t ~photos:[])

let footer_none_or_links_only () =
  Alcotest.(check bool)
    "nothing: no footer" true
    (Option.is_none (Ref_block.footer empty_t ~organ_photos:[]));
  let t =
    {empty_t with links = [link Source.Gbif "https://www.gbif.org/species/1"]}
  in
  Alcotest.(check (list string))
    "links alone: no line" []
    (footer_sources t ~photos:[]);
  Alcotest.(check (list string))
    "links alone: kept" ["GBIF ↗"]
    (footer_links t ~photos:[])

let case name f = Alcotest.test_case name `Quick f

let () =
  Alcotest.run "ref_block"
    [
      ( "both spike species render over the fixtures",
        [
          case "Digitalis: Names, Origin, Toxicity, Organ_photos (3 tiles)"
            digitalis_renders;
          case
            "Arnica: Names, Origin, Red_list (LC chip), Organ_photos (4 tiles)"
            arnica_renders;
          case "offline before any download: no Organ_photos row, others kept"
            digitalis_offline_before_any_download;
        ] );
      ( "the regional layer (Tela + INPN) over the fixtures",
        [
          case
            "Digitalis: Life_form, En_france (Indigène, Non protégée, LC), \
             Flowering (mai – septembre), Habitat; no Red_list"
            digitalis_full_renders;
          case
            "Arnica: En_france (Protégée localement + the Protection line), \
             Flowering (juin – juillet)"
            arnica_full_renders;
          case
            "no Taxref/Tela row: renders exactly as the global-only tests \
             expect"
            projection_without_regional_rows_renders_as_before;
        ] );
      ( "rows: condition and order",
        [
          case "a projection with no rows and no photos gives []"
            no_rows_no_photos;
          case "Names appears from the taxon's family alone (no vernacular)"
            names_from_family_alone;
          case
            "Origin: only introduced set gives native = None, introduced = \
             Some _"
            origin_only_introduced_has_no_native;
          case "red_list = Some \"NOT_EVALUATED\" alone gives []"
            red_list_not_evaluated_gives_no_row;
          case "every constructor appears exactly once, in the fixed order"
            every_constructor_present_and_in_order;
          case "a habitat of chips alone" habitat_chips_alone;
          case "En_france: a lone « Non protégée » is no row"
            en_france_lone_not_protected_no_row;
          case "En_france: no chip is no row" en_france_no_chip_no_row;
          case "En_france: National alone is one chip" en_france_national_alone;
          case "En_france: « Non protégée » with a red-list chip is kept"
            en_france_not_protected_with_red_list;
          case "Names sources: deduplicated, in Source.all order"
            names_sources_deduplicated_in_source_order;
        ] );
      ( "Names: french first, other languages behind a tap",
        [
          case
            "Digitalis fixture: french holds the fr vernacular names, others \
             holds en/de/it, no fr entry among others"
            digitalis_names_french_and_others;
          case
            "no French name: the other languages (en here) are shown directly, \
             french = []"
            names_only_en_has_no_french_others_holds_it;
          case "only a French name: others = []" names_only_fr_has_no_others;
          case
            "Digitalis fixture: Origin's lines in French, in French order; no \
             row mentions « hors-ligne »"
            digitalis_origin_in_french;
        ] );
      ( "Uses row",
        [
          case
            "Digitalis: chip médicinal, no plantuse line, the en « Medicinal \
             use » paragraph, placed after Toxicity before Organ_photos"
            digitalis_uses_row;
          case
            "Arnica: no plantuse part (page without box nor prose), the fr « \
             Phytothérapie » paragraph"
            arnica_uses_row;
          case
            "neither source has uses data (no section, no plantuse row): no \
             Uses row"
            neither_has_no_uses_row;
          case "Ref_text.source_name Plantuse = \"Pl@ntUse\""
            source_name_plantuse;
        ] );
      ( "the « Sources » footer",
        [
          case "dedup, order, links and the remaining links"
            footer_dedup_and_order;
          case "only the sources of the rows shown" footer_only_shown_rows;
          case "licences, the Wikipedia extract, Pl@ntUse's page"
            footer_licences;
          case "an English extract alone" footer_extract_en;
          case "empty: None; links alone: links only" footer_none_or_links_only;
        ] );
    ]
