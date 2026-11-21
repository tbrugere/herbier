module Ids = Herbier_domain.Ids
module Plant = Herbier_domain.Plant
module Tag = Herbier_domain.Tag
module Observation = Herbier_domain.Observation

(* The constants below are this file's own: a parse failure is a typo here,
   caught by test/store, not bad data. *)
let id of_string kind n =
  let text = Printf.sprintf "5eed%04d-0000-4000-8000-%012d" kind n in
  match of_string text with
  | Some id -> id
  | None -> invalid_arg ("Dev_seed.id " ^ text)

let plant_id = id Ids.Plant_id.of_string 1
let tag_id = id Ids.Tag_id.of_string 2
let observation_id = id Ids.Observation_id.of_string 3

let time text =
  match Ptime.of_rfc3339 text with
  | Ok (t, _, _) -> t
  | Error _ -> invalid_arg ("Dev_seed.time " ^ text)

let created = time "2026-04-01T08:00:00Z"

let plant n ?scientific ?authorship ?gbif_key ?(aliases = []) ?(notes = "")
    display_name =
  let notes_updated_at =
    match notes with "" -> None | _ -> Some (time "2026-06-14T18:20:00Z")
  in
  {
    Plant.id = plant_id n;
    display_name;
    aliases;
    scientific_name = scientific;
    authorship;
    gbif_key;
    notes;
    notes_updated_at;
    cover_photo_id = None;
    created_at = created;
    updated_at = Option.value notes_updated_at ~default:created;
    deleted_at = None;
  }

let plants =
  [
    plant 1 "Digitale pourpre" ~scientific:"Digitalis purpurea" ~authorship:"L."
      ~gbif_key:5414995
      ~aliases:["Gantelée"; "Gant de Notre-Dame"]
      ~notes:"Toxique. Talus ombragé, fleurs en juin.";
    plant 2 "Digitalis";
    plant 3 "Épervière piloselle" ~scientific:"Pilosella officinarum"
      ~authorship:"F.W.Schultz & Sch.Bip." ~aliases:["Piloselle"];
    plant 4 "Chêne pédonculé" ~scientific:"Quercus robur" ~authorship:"L.";
    plant 5 "Mâche" ~scientific:"Valerianella locusta"
      ~authorship:"(L.) Laterr." ~aliases:["Doucette"];
    plant 6 "Ortie dioïque" ~scientific:"Urtica dioica" ~authorship:"L.";
    plant 7 "Fougère aigle" ~scientific:"Pteridium aquilinum"
      ~authorship:"(L.) Kuhn";
    plant 8 "Pâquerette" ~scientific:"Bellis perennis" ~authorship:"L.";
    plant 9 "Églantier" ~scientific:"Rosa canina" ~authorship:"L."
      ~aliases:["Rosier des chiens"];
    plant 10 "Bouillon-blanc" ~scientific:"Verbascum thapsus" ~authorship:"L.";
    plant 11 "Maïanthème" ~scientific:"Maianthemum bifolium"
      ~authorship:"(L.) F.W.Schmidt";
    plant 12 "Menthe du ruisseau" ~notes:"Odeur forte, à identifier.";
  ]

let tag n name =
  {
    Tag.id = tag_id n;
    name;
    created_at = created;
    updated_at = created;
    deleted_at = None;
  }

let tags =
  [
    tag 1 "Comestible";
    tag 2 "Toxique";
    tag 3 "Médicinale";
    tag 4 "Jardin";
    tag 5 "Forêt";
  ]

let link (plant, tag) =
  let plant = plant_id plant and tag = tag_id tag in
  {
    Tag.Plant_tag.id = Ids.Plant_tag_id.of_key ~plant ~tag;
    plant_id = plant;
    tag_id = tag;
    created_at = created;
    updated_at = created;
    deleted_at = None;
  }

(* (plant, tag) numbers. *)
let plant_tags =
  List.map link
    [
      (1, 2);
      (1, 3);
      (1, 5);
      (2, 2);
      (4, 5);
      (5, 1);
      (5, 4);
      (6, 1);
      (6, 3);
      (7, 2);
      (7, 5);
      (8, 4);
      (9, 1);
      (10, 3);
      (11, 5);
      (12, 1);
    ]

let observation n ?plant ?position ?label ?derived ?note at =
  let at = time at in
  {
    Observation.id = observation_id n;
    plant_id = Option.map plant_id plant;
    at;
    position =
      Option.map
        (fun (lat, lon, accuracy_m) -> {Observation.lat; lon; accuracy_m})
        position;
    place_label = label;
    place_derived = derived;
    place_detail = None;
    note;
    created_at = at;
    updated_at = at;
    deleted_at = None;
  }

let lisiere = (45.7712, 3.0823, Some 6.)
let jardin = (45.7650, 3.0901, Some 12.5)
let ruisseau = (45.7801, 3.0711, None)

let observations =
  [
    observation 1 ~plant:8 ~position:jardin ~label:"Jardin"
      "2026-04-03T10:15:00Z";
    observation 2 ~plant:5 ~position:jardin ~label:"Jardin"
      "2026-04-03T10:22:30Z";
    observation 3 ~plant:6 ~position:lisiere ~derived:"Près du Moulin"
      "2026-04-18T15:40:00Z";
    observation 4 ~plant:4 ~position:lisiere ~label:"Lisière du bois"
      ~derived:"Près du Moulin" "2026-04-18T16:05:12.5Z";
    observation 5 ~position:ruisseau ~note:"Petite ombellifère, feuilles fines"
      "2026-05-02T09:00:00Z";
    observation 6 ~plant:9 ~position:lisiere ~label:"Lisière du bois"
      "2026-05-02T09:45:00Z";
    observation 7 ~plant:12 ~position:ruisseau ~label:"Bord du ruisseau"
      "2026-05-16T11:30:00Z";
    observation 8 ~plant:3 ~label:"Talus de la route" "2026-05-16T13:10:00Z";
    observation 9 ~plant:1 ~position:lisiere ~label:"Lisière du bois"
      ~note:"Premières fleurs" "2026-06-06T14:00:00Z";
    observation 10 ~plant:2 ~position:lisiere ~label:"Lisière du bois"
      "2026-06-06T14:12:00Z";
    observation 11 ~plant:7 ~position:lisiere ~derived:"Près du Moulin"
      "2026-06-06T14:30:00Z";
    observation 12 ~plant:11 ~position:ruisseau ~label:"Bord du ruisseau"
      "2026-06-14T17:55:00Z";
    observation 13 ~plant:10 ~label:"Talus de la route" "2026-06-21T08:40:00Z";
    observation 14 ~note:"Graminée inconnue" "2026-06-21T08:52:00Z";
    observation 15 ~plant:1 ~position:jardin ~label:"Jardin"
      ~note:"Semis spontané" "2026-07-04T19:05:00Z";
    observation 16 ~plant:8 ~position:jardin "2026-07-04T19:10:00Z";
  ]

let statements =
  List.concat
    [
      List.map (fun p -> Outbox.without_entry (Plants.upsert p)) plants;
      List.map (fun t -> Outbox.without_entry (Tags.upsert t)) tags;
      List.map Tags.upsert_plant_tag plant_tags;
      List.map
        (fun o -> Outbox.without_entry (Observations.upsert o))
        observations;
    ]
