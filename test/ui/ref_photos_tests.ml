(* Herbier_ui_model.Ref_photos: the slides of 5e's read-only organ-photo
   viewer over 4f's "Photos par organe". Pure: no Brr. *)

module Ref_photos = Herbier_ui_model.Ref_photos
module Ids = Herbier_domain.Ids
module Reference = Herbier_domain.Reference
module Source = Herbier_domain.Reference.Source
module Organ = Herbier_domain.Reference.Organ
module Payload = Herbier_refs.Payload
module Projection = Herbier_refs.Projection
module Fixture = Herbier_test_support.Fixture
module Decode = Herbier_refs.Decode

let plant =
  match Ids.Plant_id.of_string "00000000-0000-4000-8000-000000000001" with
  | Some x -> x
  | None -> invalid_arg "plant id"

let t0 =
  match Ptime.of_rfc3339 "2026-11-01T10:00:00Z" with
  | Ok (t, _, _) -> t
  | Error _ -> invalid_arg "fixture time"

let json name =
  match Decode.json_of_string (Fixture.read name) with
  | Ok j -> j
  | Error e -> Alcotest.failf "%s: %s" name (Decode.error_to_string e)

(* The recorded Pl@ntNet media, projected the way [Projection.project] reads
   it: one [Plantnet] reference row, nothing else (as test_organ_photos.ml's
   projection_of_media). *)
let projection_of_media media =
  let row : Reference.t =
    {
      id = Reference.id_of_key ~plant ~source:Source.Plantnet;
      plant_id = plant;
      source = Source.Plantnet;
      fetched_at = t0;
      payload = Payload.plantnet ~media:(Some media);
      status = Reference.Status.Complete;
      created_at = t0;
      updated_at = t0;
      deleted_at = None;
    }
  in
  Projection.project ~references:[row] ~plant_refs:[]

let digitalis_media = json "gbif_plantnet_media_5414995.json"
let digitalis_proj () = projection_of_media digitalis_media

(* The wanted urls of the Digitalis fixture, pinned the same way
   test_organ_photos.ml's wanted_digitalis does. *)
let flower_url =
  "https://bs.plantnet.org/image/o/2fba888595d4c46b22e95bc31a63442828b16a7f"

let leaf_url =
  "https://bs.plantnet.org/image/o/b1d46b31e711e4acd2c9dbf2cda5365e1458b589"

let habit_url =
  "https://bs.plantnet.org/image/o/56930d916e7f13c56a4521bfef51beb655b8a3b1"

let image ?(plant_id = plant) ?(source = Source.Plantnet) ~organ ~remote_url
    ~thumb_path ~attribution ~licence () : Reference.Image.t =
  {plant_id; source; organ; remote_url; licence; attribution; thumb_path}

(* ---------- slides over the Digitalis fixture ---------- *)

let digitalis_two_slides_flower_then_leaf () =
  let stored =
    [
      image ~organ:Organ.Flower ~remote_url:flower_url
        ~thumb_path:(Some "refthumbs/flower.jpg") ~attribution:"A"
        ~licence:"cc-by-sa" ();
      image ~organ:Organ.Leaf ~remote_url:leaf_url
        ~thumb_path:(Some "refthumbs/leaf.jpg") ~attribution:"B"
        ~licence:"cc-by" ();
      (* habit's row is stored (Pl@ntNet wants it) but not downloaded yet: no
         slide for it, same rule as Organ_photos.shown. *)
      image ~organ:Organ.Habit ~remote_url:habit_url ~thumb_path:None
        ~attribution:"C" ~licence:"cc-by-sa" ();
    ]
  in
  let slides = Ref_photos.slides (digitalis_proj ()) ~stored in
  Alcotest.(check (list string))
    "organs, flower then leaf" ["flower"; "leaf"]
    (List.map (fun (s : Ref_photos.slide) -> Organ.to_string s.organ) slides);
  (match slides with
  | [flower; leaf] ->
      Alcotest.(check string)
        "flower thumb_path" "refthumbs/flower.jpg" flower.thumb_path;
      Alcotest.(check string)
        "flower full_url is the stored remote_url" flower_url flower.full_url;
      Alcotest.(check string) "flower label" "fleur" flower.label;
      Alcotest.(check string)
        "flower credit" "A · cc-by-sa · Pl@ntNet" flower.credit;
      Alcotest.(check string) "flower alt" "Photo Pl@ntNet : fleur" flower.alt;
      Alcotest.(check string) "leaf label" "feuille" leaf.label;
      Alcotest.(check string)
        "leaf full_url is the stored remote_url" leaf_url leaf.full_url
  | got -> Alcotest.failf "expected 2 slides, got %d" (List.length got));
  Alcotest.(check bool)
    "every slide's full_url is downloadable (shown only matches wanted urls)"
    true
    (List.for_all
       (fun (s : Ref_photos.slide) ->
         Herbier_refs.Organ_photos.downloadable s.full_url)
       slides)

let stored_remote_url_mismatch_gives_no_slide () =
  let stored =
    [
      image ~organ:Organ.Flower
        ~remote_url:"https://bs.plantnet.org/image/o/stale"
        ~thumb_path:(Some "refthumbs/flower.jpg") ~attribution:"A"
        ~licence:"cc-by-sa" ();
    ]
  in
  Alcotest.(check (list string))
    "no slide for the stale flower row" []
    (List.map
       (fun (s : Ref_photos.slide) -> Organ.to_string s.organ)
       (Ref_photos.slides (digitalis_proj ()) ~stored))

(* ---------- credit ---------- *)

let credit_cases () =
  let case what expected ~attribution ~licence =
    let img =
      image ~organ:Organ.Flower ~remote_url:flower_url ~thumb_path:None
        ~attribution ~licence ()
    in
    Alcotest.(check string) what expected (Ref_photos.credit img)
  in
  case "attribution and licence" "A · cc-by-sa · Pl@ntNet" ~attribution:"A"
    ~licence:"cc-by-sa";
  case "empty attribution: left out with its separator" "cc-by-sa · Pl@ntNet"
    ~attribution:"" ~licence:"cc-by-sa";
  case "empty licence: left out with its separator" "A · Pl@ntNet"
    ~attribution:"A" ~licence:"";
  case "both empty" "Pl@ntNet" ~attribution:"" ~licence:"";
  case "attribution and licence are trimmed" "A · cc-by-sa · Pl@ntNet"
    ~attribution:"  A  " ~licence:"  cc-by-sa  "

(* ---------- start ---------- *)

let start_cases () =
  let stored =
    [
      image ~organ:Organ.Flower ~remote_url:flower_url
        ~thumb_path:(Some "refthumbs/flower.jpg") ~attribution:"A"
        ~licence:"cc-by-sa" ();
      image ~organ:Organ.Leaf ~remote_url:leaf_url
        ~thumb_path:(Some "refthumbs/leaf.jpg") ~attribution:"B"
        ~licence:"cc-by" ();
    ]
  in
  let slides = Ref_photos.slides (digitalis_proj ()) ~stored in
  Alcotest.(check int)
    "flower is first" 0
    (Ref_photos.start slides Organ.Flower);
  Alcotest.(check int) "leaf is second" 1 (Ref_photos.start slides Organ.Leaf);
  Alcotest.(check int)
    "an absent organ (no habit slide here)" 0
    (Ref_photos.start slides Organ.Habit);
  Alcotest.(check int) "[] gives 0" 0 (Ref_photos.start [] Organ.Flower)

(* ---------- run ---------- *)

let case name f = Alcotest.test_case name `Quick f

let ref_photos =
  [
    case
      "Digitalis fixture: flower and leaf slides, in organ order, full_url and \
       credit from the stored row, label from Ref_text.organ_label"
      digitalis_two_slides_flower_then_leaf;
    case "a stored row whose remote_url differs from the wanted image: no slide"
      stored_remote_url_mismatch_gives_no_slide;
    case
      "credit: attribution/licence trimmed, an empty one dropped with its \
       separator, both empty gives \"Pl@ntNet\""
      credit_cases;
    case "start: a present organ's index, an absent organ, [] gives 0"
      start_cases;
  ]
