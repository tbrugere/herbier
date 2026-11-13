(* The reference payloads are inlined from scripts/record-sync-fixtures.sh
   (sent) and test/fixtures/sync_select_reference_200.json (jsonb's
   reorder). *)

module Merge = Herbier_domain.Merge
module Ids = Herbier_domain.Ids
module Plant = Herbier_domain.Plant
module Observation = Herbier_domain.Observation
module Photo = Herbier_domain.Photo
module Tag = Herbier_domain.Tag
module Reference = Herbier_domain.Reference
module Source = Reference.Source
module Status = Reference.Status

(* ---------- time and id helpers (as test/store's fixtures) ---------- *)

let time s =
  match Ptime.of_rfc3339 s with
  | Ok (t, _, _) -> t
  | Error _ -> invalid_arg ("fixture time " ^ s)

let shift secs t =
  match Ptime.add_span t (Ptime.Span.of_int_s secs) with
  | Some t -> t
  | None -> Alcotest.failf "shift %d overflowed Ptime" secs

let t1 = time "2026-11-01T10:00:00Z"
let t2 = time "2026-11-02T11:00:00Z"
let uuid n = Printf.sprintf "01965d4e-0000-7000-8000-%012x" n

let id_of what of_string n =
  match of_string (uuid n) with
  | Some x -> x
  | None -> invalid_arg ("fixture " ^ what)

let plant_id = id_of "plant id" Ids.Plant_id.of_string
let observation_id = id_of "observation id" Ids.Observation_id.of_string
let photo_id = id_of "photo id" Ids.Photo_id.of_string
let tag_id = id_of "tag id" Ids.Tag_id.of_string
let plant_tag_id = id_of "plant tag id" Ids.Plant_tag_id.of_string
let reference_id = id_of "reference id" Ids.Reference_id.of_string
let plant_ref_id = id_of "plant ref id" Ids.Plant_ref_id.of_string

(* ---------- decision testable ---------- *)

let decision = Alcotest.testable Merge.pp_decision Merge.equal_decision

(* ---------- base fixtures, every optional field set ---------- *)

let plant_base : Plant.t =
  {
    id = plant_id 1;
    display_name = "Digitale";
    aliases = ["Digitale"; "Gant de Notre-Dame"];
    scientific_name = Some "Digitalis purpurea";
    authorship = Some "L.";
    gbif_key = Some 5414995;
    notes = "Vue au bord du chemin";
    notes_updated_at = Some t1;
    cover_photo_id = Some (photo_id 9);
    created_at = t1;
    updated_at = t1;
    deleted_at = None;
  }

let observation_base : Observation.t =
  {
    id = observation_id 1;
    plant_id = Some (plant_id 1);
    at = t1;
    position =
      Some {Observation.lat = 48.0625; lon = 7.0625; accuracy_m = Some 12.5};
    place_label = Some "Bord du chemin";
    place_derived = Some "Vosges";
    note = Some "Belle floraison";
    created_at = t1;
    updated_at = t1;
    deleted_at = None;
  }

let photo_base : Photo.t =
  {
    id = photo_id 1;
    observation_id = observation_id 1;
    taken_at = t1;
    width = 1024;
    height = 768;
    sha256 = String.make 64 'a';
    preview_path = "previews/1.webp";
    preview_bucket_key = Some "bucket/1";
    original_target = Photo.Original_target.Drive;
    drive_file_id = Some "drive-1";
    upload_state = Photo.Upload_state.Uploaded;
    created_at = t1;
    updated_at = t1;
    deleted_at = None;
  }

let tag_base : Tag.t =
  {
    id = tag_id 1;
    name = "Vivace";
    created_at = t1;
    updated_at = t1;
    deleted_at = None;
  }

let plant_tag_base : Tag.Plant_tag.t =
  {
    id = plant_tag_id 1;
    plant_id = plant_id 1;
    tag_id = tag_id 1;
    created_at = t1;
    updated_at = t1;
    deleted_at = None;
  }

let reference_base : Reference.t =
  {
    id = reference_id 1;
    plant_id = plant_id 1;
    source = Source.Gbif;
    fetched_at = t1;
    payload = `Assoc [("a", `Int 1)];
    status = Status.Complete;
    created_at = t1;
    updated_at = t1;
    deleted_at = None;
  }

let plant_ref_base : Reference.Plant_ref.t =
  {
    id = plant_ref_id 1;
    plant_id = plant_id 1;
    source = Source.Gbif;
    external_id = "5414995";
    url = "https://www.gbif.org/species/5414995";
    created_at = t1;
    updated_at = t1;
    deleted_at = None;
  }

(* ---------- equal: reflexive, false on exactly one field ---------- *)

let field_cases (type a) name ~(equal : a -> a -> bool) ~(base : a)
    ~(variants : (string * a) list) =
  [
    ( name ^ ": equal is reflexive on a full record",
      `Quick,
      fun () -> Alcotest.(check bool) "equal base base" true (equal base base)
    );
    ( name ^ ": equal is false when exactly one field differs",
      `Quick,
      fun () ->
        List.iter
          (fun (field, other) ->
            Alcotest.(check bool)
              (Printf.sprintf "differs only in %s" field)
              false (equal base other))
          variants );
  ]

let plant_field_cases =
  field_cases "Plant" ~equal:Plant.equal ~base:plant_base
    ~variants:
      [
        ("id", {plant_base with id = plant_id 2});
        ("display_name", {plant_base with display_name = "Autre nom"});
        ("aliases", {plant_base with aliases = ["Autre"]});
        ("scientific_name", {plant_base with scientific_name = None});
        ("authorship", {plant_base with authorship = None});
        ("gbif_key", {plant_base with gbif_key = None});
        ("notes", {plant_base with notes = "Autre note"});
        ("notes_updated_at", {plant_base with notes_updated_at = None});
        ("cover_photo_id", {plant_base with cover_photo_id = None});
        ("created_at", {plant_base with created_at = t2});
        ("updated_at", {plant_base with updated_at = t2});
        ("deleted_at", {plant_base with deleted_at = Some t2});
      ]

let observation_field_cases =
  field_cases "Observation" ~equal:Observation.equal ~base:observation_base
    ~variants:
      [
        ("id", {observation_base with id = observation_id 2});
        ("plant_id", {observation_base with plant_id = None});
        ("at", {observation_base with at = t2});
        ("position", {observation_base with position = None});
        ("place_label", {observation_base with place_label = None});
        ("place_derived", {observation_base with place_derived = None});
        ("note", {observation_base with note = None});
        ("created_at", {observation_base with created_at = t2});
        ("updated_at", {observation_base with updated_at = t2});
        ("deleted_at", {observation_base with deleted_at = Some t2});
      ]

let photo_field_cases =
  field_cases "Photo" ~equal:Photo.equal ~base:photo_base
    ~variants:
      [
        ("id", {photo_base with id = photo_id 2});
        ("observation_id", {photo_base with observation_id = observation_id 2});
        ("taken_at", {photo_base with taken_at = t2});
        ("width", {photo_base with width = 2048});
        ("height", {photo_base with height = 2048});
        ("sha256", {photo_base with sha256 = String.make 64 'b'});
        ("preview_path", {photo_base with preview_path = "previews/2.webp"});
        ("preview_bucket_key", {photo_base with preview_bucket_key = None});
        ( "original_target",
          {photo_base with original_target = Photo.Original_target.App_only} );
        ("drive_file_id", {photo_base with drive_file_id = None});
        ( "upload_state",
          {photo_base with upload_state = Photo.Upload_state.Pending} );
        ("created_at", {photo_base with created_at = t2});
        ("updated_at", {photo_base with updated_at = t2});
        ("deleted_at", {photo_base with deleted_at = Some t2});
      ]

let tag_field_cases =
  field_cases "Tag" ~equal:Tag.equal ~base:tag_base
    ~variants:
      [
        ("id", {tag_base with id = tag_id 2});
        ("name", {tag_base with name = "Autre"});
        ("created_at", {tag_base with created_at = t2});
        ("updated_at", {tag_base with updated_at = t2});
        ("deleted_at", {tag_base with deleted_at = Some t2});
      ]

let plant_tag_field_cases =
  field_cases "Tag.Plant_tag" ~equal:Tag.Plant_tag.equal ~base:plant_tag_base
    ~variants:
      [
        ("id", {plant_tag_base with id = plant_tag_id 2});
        ("plant_id", {plant_tag_base with plant_id = plant_id 2});
        ("tag_id", {plant_tag_base with tag_id = tag_id 2});
        ("created_at", {plant_tag_base with created_at = t2});
        ("updated_at", {plant_tag_base with updated_at = t2});
        ("deleted_at", {plant_tag_base with deleted_at = Some t2});
      ]

let reference_field_cases =
  field_cases "Reference" ~equal:Reference.equal ~base:reference_base
    ~variants:
      [
        ("id", {reference_base with id = reference_id 2});
        ("plant_id", {reference_base with plant_id = plant_id 2});
        ("source", {reference_base with source = Source.Wikidata});
        ("fetched_at", {reference_base with fetched_at = t2});
        ("payload", {reference_base with payload = `Assoc [("a", `Int 2)]});
        ("status", {reference_base with status = Status.Partial});
        ("created_at", {reference_base with created_at = t2});
        ("updated_at", {reference_base with updated_at = t2});
        ("deleted_at", {reference_base with deleted_at = Some t2});
      ]

let plant_ref_field_cases =
  field_cases "Reference.Plant_ref" ~equal:Reference.Plant_ref.equal
    ~base:plant_ref_base
    ~variants:
      [
        ("id", {plant_ref_base with id = plant_ref_id 2});
        ("plant_id", {plant_ref_base with plant_id = plant_id 2});
        ("source", {plant_ref_base with source = Source.Wikidata});
        ("external_id", {plant_ref_base with external_id = "999"});
        ( "url",
          {plant_ref_base with url = "https://www.wikidata.org/wiki/Q157555"} );
        ("created_at", {plant_ref_base with created_at = t2});
        ("updated_at", {plant_ref_base with updated_at = t2});
        ("deleted_at", {plant_ref_base with deleted_at = Some t2});
      ]

let observation_position_cases =
  let position =
    {Observation.lat = 48.0625; lon = 7.0625; accuracy_m = Some 12.5}
  in
  [
    ( "Observation.equal_position: lat, lon or accuracy_m differing is false",
      `Quick,
      fun () ->
        let p = position in
        Alcotest.(check bool)
          "lat differs" false
          (Observation.equal_position p {p with lat = Float.succ p.lat});
        Alcotest.(check bool)
          "lon differs" false
          (Observation.equal_position p {p with lon = Float.succ p.lon});
        Alcotest.(check bool)
          "accuracy_m differs" false
          (Observation.equal_position p {p with accuracy_m = None}) );
    (* Float.equal, not (=): with (=) nan differs from itself, so a row with
       a nan coordinate would be Replaced on every pull. *)
    ( "Observation.equal_position: nan equals nan",
      `Quick,
      fun () ->
        let p = {Observation.lat = nan; lon = nan; accuracy_m = Some nan} in
        Alcotest.(check bool)
          "nan position" true
          (Observation.equal_position p {p with lat = nan}) );
  ]

(* ---------- Merge.decide ---------- *)

module M_plant = struct
  let decide = Merge.decide ~equal:Plant.equal
end

module M_observation = struct
  let decide = Merge.decide ~equal:Observation.equal
end

module M_plant_tag = struct
  let decide = Merge.decide ~equal:Tag.Plant_tag.equal
end

module M_reference = struct
  let decide = Merge.decide ~equal:Reference.equal
end

let new_remote_row () =
  Alcotest.(check decision)
    "no local, not pending" Merge.Insert
    (M_plant.decide ~pending:false ~local:None plant_base);
  Alcotest.(check decision)
    "no local, pending" Merge.Insert
    (M_plant.decide ~pending:true ~local:None plant_base)

let outbox_wins () =
  let remote_different_later =
    {plant_base with notes = "Changed remotely"; updated_at = t2}
  in
  Alcotest.(check decision)
    "pending, remote different and later" Merge.Keep_local
    (M_plant.decide ~pending:true ~local:(Some plant_base)
       remote_different_later);
  Alcotest.(check decision)
    "pending, remote equal to local (pending checked before equality)"
    Merge.Keep_local
    (M_plant.decide ~pending:true ~local:(Some plant_base) plant_base)

let remote_newer_no_pending () =
  let remote = {plant_base with notes = "Changed remotely"; updated_at = t2} in
  Alcotest.(check decision)
    "not pending, remote differs" Merge.Replace
    (M_plant.decide ~pending:false ~local:(Some plant_base) remote)

let identical () =
  Alcotest.(check decision)
    "every field equal, updated_at included" Merge.Unchanged
    (M_plant.decide ~pending:false ~local:(Some plant_base) plant_base)

let own_push_comes_back () =
  let t_dev = t1 and t_srv = t2 in
  let local = {plant_base with updated_at = t_dev} in
  let remote = {plant_base with updated_at = t_srv} in
  Alcotest.(check decision)
    "same content, server's updated_at adopted" Merge.Replace
    (M_plant.decide ~pending:false ~local:(Some local) remote)

let clock_skew () =
  let t_srv = t1 in
  let ahead = shift 3600 t_srv in
  let another_install_edit = shift 600 t_srv in
  let local_ahead = {plant_base with updated_at = ahead} in
  let remote =
    {
      plant_base with
      notes = "Another install's edit";
      updated_at = another_install_edit;
    }
  in
  Alcotest.(check decision)
    "device 1h ahead, remote older but real: not lost" Merge.Replace
    (M_plant.decide ~pending:false ~local:(Some local_ahead) remote);
  let behind = shift (-3600) t_srv in
  let local_behind = {plant_base with updated_at = behind} in
  Alcotest.(check decision)
    "device 1h behind, remote newer: Replace" Merge.Replace
    (M_plant.decide ~pending:false ~local:(Some local_behind) remote)

let soft_delete () =
  let live = plant_base in
  let deleted = {plant_base with deleted_at = Some t2} in
  Alcotest.(check decision)
    "remote newly deleted, local live, no pending" Merge.Replace
    (M_plant.decide ~pending:false ~local:(Some live) deleted);
  let remote_live_newer = {plant_base with updated_at = t2} in
  Alcotest.(check decision)
    "local deleted, pending, remote live and newer" Merge.Keep_local
    (M_plant.decide ~pending:true ~local:(Some deleted) remote_live_newer);
  Alcotest.(check decision)
    "local deleted, remote revived, no pending" Merge.Replace
    (M_plant.decide ~pending:false ~local:(Some deleted) live);
  Alcotest.(check decision)
    "both deleted, equal rows" Merge.Unchanged
    (M_plant.decide ~pending:false ~local:(Some deleted) deleted)

let truncated_timestamps () =
  let local =
    {plant_base with created_at = time "2026-11-01T10:00:00.123456Z"}
  in
  let remote = {plant_base with created_at = time "2026-11-01T10:00:00Z"} in
  Alcotest.(check decision)
    "microsecond local vs truncated remote created_at: not Unchanged"
    Merge.Replace
    (M_plant.decide ~pending:false ~local:(Some local) remote)

(* The payload sent, and jsonb's reorder of it as
   test/fixtures/sync_select_reference_200.json recorded it. *)
let sent_payload : Yojson.Safe.t =
  `Assoc
    [
      ( "vernacular",
        `List
          [
            `Assoc
              [("name", `String "Digitale pourpre"); ("lang", `String "fra")];
          ] );
      ( "species",
        `Assoc
          [
            ("rank", `String "SPECIES");
            ("key", `Int 5414995);
            ("canonicalName", `String "Digitalis purpurea");
          ] );
    ]

let reordered_payload : Yojson.Safe.t =
  `Assoc
    [
      ( "species",
        `Assoc
          [
            ("key", `Int 5414995);
            ("rank", `String "SPECIES");
            ("canonicalName", `String "Digitalis purpurea");
          ] );
      ( "vernacular",
        `List
          [
            `Assoc
              [("lang", `String "fra"); ("name", `String "Digitale pourpre")];
          ] );
    ]

let reference_payload_structural () =
  Alcotest.(check bool)
    "to_string of the two payloads differ (text compare would be wrong)" false
    (String.equal
       (Yojson.Safe.to_string sent_payload)
       (Yojson.Safe.to_string reordered_payload));
  let local = {reference_base with payload = sent_payload} in
  let remote = {reference_base with payload = reordered_payload} in
  Alcotest.(check decision)
    "reordered keys only: Unchanged" Merge.Unchanged
    (M_reference.decide ~pending:false ~local:(Some local) remote);
  (* Same keys and shape as [local]'s payload, one nested value changed: a
     shallow or key-set comparison would call it Unchanged. *)
  let with_payload payload = {remote with payload} in
  let species_key_changed =
    `Assoc
      [
        ( "species",
          `Assoc
            [
              ("key", `Int 5414996);
              ("rank", `String "SPECIES");
              ("canonicalName", `String "Digitalis purpurea");
            ] );
        ( "vernacular",
          `List
            [
              `Assoc
                [("lang", `String "fra"); ("name", `String "Digitale pourpre")];
            ] );
      ]
  in
  Alcotest.(check decision)
    "species.key changed: Replace" Merge.Replace
    (M_reference.decide ~pending:false ~local:(Some local)
       (with_payload species_key_changed));
  let list_element_changed =
    `Assoc
      [
        ( "species",
          `Assoc
            [
              ("key", `Int 5414995);
              ("rank", `String "SPECIES");
              ("canonicalName", `String "Digitalis purpurea");
            ] );
        ( "vernacular",
          `List
            [
              `Assoc
                [("lang", `String "eng"); ("name", `String "Digitale pourpre")];
            ] );
      ]
  in
  Alcotest.(check decision)
    "a vernacular element's lang changed: Replace" Merge.Replace
    (M_reference.decide ~pending:false ~local:(Some local)
       (with_payload list_element_changed))

let floats () =
  let local =
    {
      observation_base with
      position =
        Some {Observation.lat = 48.0625; lon = 7.0625; accuracy_m = Some 12.5};
    }
  in
  let same =
    {
      observation_base with
      position =
        Some {Observation.lat = 48.0625; lon = 7.0625; accuracy_m = Some 12.5};
    }
  in
  Alcotest.(check decision)
    "lat and lon equal" Merge.Unchanged
    (M_observation.decide ~pending:false ~local:(Some local) same);
  let differ_last_bit =
    {
      observation_base with
      position =
        Some
          {
            Observation.lat = Float.succ 48.0625;
            lon = 7.0625;
            accuracy_m = Some 12.5;
          };
    }
  in
  Alcotest.(check decision)
    "lat differs in the last bit" Merge.Replace
    (M_observation.decide ~pending:false ~local:(Some local) differ_last_bit)

let aliases_order () =
  let local = {plant_base with aliases = ["a"; "b"]} in
  let remote = {plant_base with aliases = ["b"; "a"]} in
  Alcotest.(check decision)
    "same elements, different order" Merge.Replace
    (M_plant.decide ~pending:false ~local:(Some local) remote)

(* The scenarios above use Plant; decide does not depend on the row type,
   and these check it with Observation's and Tag.Plant_tag's equal. *)
let decide_on_every_listed_module () =
  Alcotest.(check decision)
    "Observation: no local" Merge.Insert
    (M_observation.decide ~pending:false ~local:None observation_base);
  Alcotest.(check decision)
    "Observation: pending" Merge.Keep_local
    (M_observation.decide ~pending:true ~local:(Some observation_base)
       {observation_base with note = Some "other"});
  Alcotest.(check decision)
    "Observation: identical" Merge.Unchanged
    (M_observation.decide ~pending:false ~local:(Some observation_base)
       observation_base);
  Alcotest.(check decision)
    "Observation: differs, not pending" Merge.Replace
    (M_observation.decide ~pending:false ~local:(Some observation_base)
       {observation_base with note = Some "other"});
  Alcotest.(check decision)
    "Tag.Plant_tag: no local" Merge.Insert
    (M_plant_tag.decide ~pending:false ~local:None plant_tag_base);
  Alcotest.(check decision)
    "Tag.Plant_tag: identical" Merge.Unchanged
    (M_plant_tag.decide ~pending:false ~local:(Some plant_tag_base)
       plant_tag_base);
  Alcotest.(check decision)
    "Tag.Plant_tag: differs, not pending" Merge.Replace
    (M_plant_tag.decide ~pending:false ~local:(Some plant_tag_base)
       {plant_tag_base with updated_at = t2})

let decide_tests =
  [
    ("new remote row: Insert whatever pending", `Quick, new_remote_row);
    ("outbox wins: Keep_local before equality", `Quick, outbox_wins);
    ("remote newer, no pending: Replace", `Quick, remote_newer_no_pending);
    ("identical rows: Unchanged", `Quick, identical);
    ("own push comes back: Replace", `Quick, own_push_comes_back);
    ("clock skew, device ahead and behind: Replace", `Quick, clock_skew);
    ("soft delete: the four cases", `Quick, soft_delete);
    ( "truncated timestamps: Replace, not Unchanged",
      `Quick,
      truncated_timestamps );
    ( "reference payload, structural equality",
      `Quick,
      reference_payload_structural );
    ("floats: equal vs differ in the last bit", `Quick, floats);
    ("aliases order matters", `Quick, aliases_order);
    ( "decide over Observation and Tag.Plant_tag",
      `Quick,
      decide_on_every_listed_module );
  ]

let tests =
  List.concat
    [
      decide_tests;
      plant_field_cases;
      observation_field_cases;
      observation_position_cases;
      photo_field_cases;
      tag_field_cases;
      plant_tag_field_cases;
      reference_field_cases;
      plant_ref_field_cases;
    ]
