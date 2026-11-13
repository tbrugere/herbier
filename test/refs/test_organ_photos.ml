module Ids = Herbier_domain.Ids
module Reference = Herbier_domain.Reference
module Source = Herbier_domain.Reference.Source
module Organ = Herbier_domain.Reference.Organ
module Payload = Herbier_refs.Payload
module Projection = Herbier_refs.Projection
module Gbif = Herbier_refs.Sources.Gbif
module Organ_photos = Herbier_refs.Organ_photos
module Fixture = Herbier_test_support.Fixture
module Testable = Herbier_test_support.Testable

(* ---------- fixtures ---------- *)

let plant =
  match Ids.Plant_id.of_string "00000000-0000-4000-8000-000000000001" with
  | Some x -> x
  | None -> invalid_arg "plant id"

let other_plant =
  match Ids.Plant_id.of_string "00000000-0000-4000-8000-000000000002" with
  | Some x -> x
  | None -> invalid_arg "other plant id"

let t0 =
  match Ptime.of_rfc3339 "2026-11-01T10:00:00Z" with
  | Ok (t, _, _) -> t
  | Error _ -> invalid_arg "fixture time"

(* The recorded Pl@ntNet media, projected the way [Projection.project] reads
   it: one [Plantnet] reference row, nothing else. *)
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

let organ_photos_of_fixture name =
  match (projection_of_media (Check.json name)).organ_photos with
  | Some {value; _} -> value
  | None -> Alcotest.failf "%s: organ_photos is None" name

let digitalis_images () =
  organ_photos_of_fixture "gbif_plantnet_media_5414995.json"

let arnica_images () =
  organ_photos_of_fixture "gbif_plantnet_media_5405976.json"

(* ---------- builders ---------- *)

let gbif_image ?(occurrence_key = "1") ?organ ?organ_label
    ?(licence = "cc-by-sa") ?(attribution = "Someone") ?(observation_url = None)
    ~url () : Gbif.Image.t =
  {
    occurrence_key;
    url;
    organ;
    organ_label;
    licence;
    attribution;
    observation_url;
  }

let image ?(plant_id = plant) ?(source = Source.Plantnet) ~organ ~remote_url
    ?(licence = "cc-by-sa") ?(attribution = "Someone") ?(thumb_path = None) () :
    Reference.Image.t =
  {plant_id; source; organ; remote_url; licence; attribution; thumb_path}

(* ---------- testables ---------- *)

let image_json (i : Reference.Image.t) =
  `Assoc
    [
      ("plant_id", `String (Ids.Plant_id.to_string i.plant_id));
      ("source", `String (Source.to_string i.source));
      ("organ", `String (Organ.to_string i.organ));
      ("remote_url", `String i.remote_url);
      ("licence", `String i.licence);
      ("attribution", `String i.attribution);
      ( "thumb_path",
        match i.thumb_path with None -> `Null | Some p -> `String p );
    ]

let images_json l = `List (List.map image_json l)

let check_images what expected actual =
  Alcotest.(check Testable.yojson)
    what (images_json expected) (images_json actual)

(* ---------- downloadable ---------- *)

let downloadable () =
  Alcotest.(check string) "host" "bs.plantnet.org" Organ_photos.host;
  let case expected url =
    Alcotest.(check bool)
      (Printf.sprintf "downloadable %S" url)
      expected
      (Organ_photos.downloadable url)
  in
  case true
    "https://bs.plantnet.org/image/o/b1d46b31e711e4acd2c9dbf2cda5365e1458b589";
  case false "http://bs.plantnet.org/image/o/x";
  case false "https://bs.plantnet.org/";
  case false "https://bs.plantnet.org";
  case false "https://bs.plantnet.org.evil.com/x";
  case false "https://evil.com/bs.plantnet.org/x";
  case false "https://u@bs.plantnet.org/x";
  case false "https://bs.plantnet.org:8443/x";
  case false "https://bs.plantnet.org/a b";
  case false "https://bs.plantnet.org/a\"b";
  case false "https://bs.plantnet.org/a\tb";
  case false "https://bs.plantnet.org/a\nb";
  case false "https://bs.plantnet.org/a<b";
  case false "https://bs.plantnet.org/a>b";
  case false "https://bs.plantnet.org/a\\b";
  case false "https://bs.plantnet.org/a\x00b";
  case false "https://bs.plantnet.org/a\x7fb";
  case true "https://bs.plantnet.org/\xc3\xa9";
  case false ""

(* ---------- wanted ---------- *)

let check_wanted what images expected =
  let got = Organ_photos.wanted images in
  Alcotest.(check (list string))
    (what ^ ": organs, in Organ.all order")
    (List.map fst expected)
    (List.map (fun (o, _) -> Organ.to_string o) got);
  List.iter2
    (fun (organ, url) (o, (img : Gbif.Image.t)) ->
      Alcotest.(check string)
        (what ^ ": " ^ organ ^ " organ")
        organ (Organ.to_string o);
      Alcotest.(check string) (what ^ ": " ^ organ ^ " url") url img.url)
    expected got

let wanted_digitalis () =
  check_wanted "digitalis" (digitalis_images ())
    [
      ( "flower",
        "https://bs.plantnet.org/image/o/2fba888595d4c46b22e95bc31a63442828b16a7f"
      );
      ( "leaf",
        "https://bs.plantnet.org/image/o/b1d46b31e711e4acd2c9dbf2cda5365e1458b589"
      );
      ( "habit",
        "https://bs.plantnet.org/image/o/56930d916e7f13c56a4521bfef51beb655b8a3b1"
      );
    ]

let wanted_arnica () =
  check_wanted "arnica" (arnica_images ())
    [
      ( "flower",
        "https://bs.plantnet.org/image/o/0e1b43fdc604a4e161ce1efc4a13fb130d4bf55c"
      );
      ( "leaf",
        "https://bs.plantnet.org/image/o/f4354e37eb704ea20f3b2cc85ec93a90bf6de07c"
      );
      ( "fruit",
        "https://bs.plantnet.org/image/o/b67d8c0ce6826b41b201a2fbcabe914099c1177d"
      );
      ( "habit",
        "https://bs.plantnet.org/image/o/df71dbad9411d013b7bef5ca18afc06ab03acaf8"
      );
    ]

let wanted_rules () =
  Alcotest.(check int)
    "an image with organ = None is skipped" 0
    (List.length
       (Organ_photos.wanted
          [gbif_image ~url:"https://bs.plantnet.org/image/o/x" ()]));
  let other_host =
    gbif_image ~organ:Organ.Flower ~url:"https://other.org/image/o/first" ()
  in
  let on_host =
    gbif_image ~organ:Organ.Flower ~url:"https://bs.plantnet.org/image/o/second"
      ()
  in
  (match Organ_photos.wanted [other_host; on_host] with
  | [(Organ.Flower, img)] ->
      Alcotest.(check string)
        "the first image on another host is skipped, the second (on the host) \
         is taken"
        "https://bs.plantnet.org/image/o/second" img.url
  | got ->
      Alcotest.failf "expected one Flower image, got %d entries"
        (List.length got));
  let flower =
    gbif_image ~organ:Organ.Flower ~url:"https://bs.plantnet.org/image/o/f" ()
  in
  let leaf =
    gbif_image ~organ:Organ.Leaf ~url:"https://bs.plantnet.org/image/o/l" ()
  in
  let fruit =
    gbif_image ~organ:Organ.Fruit ~url:"https://bs.plantnet.org/image/o/fr" ()
  in
  let habit =
    gbif_image ~organ:Organ.Habit ~url:"https://bs.plantnet.org/image/o/h" ()
  in
  Alcotest.(check (list string))
    "order is Organ.all whatever the input order"
    ["flower"; "leaf"; "fruit"; "habit"]
    (List.map
       (fun (o, _) -> Organ.to_string o)
       (Organ_photos.wanted [habit; fruit; leaf; flower]))

(* Every occurrence of [sub] in [s] replaced by [by]. *)
let replace ~sub ~by s =
  let n = String.length sub in
  let b = Buffer.create (String.length s) in
  let rec go i =
    match i + n <= String.length s with
    | false -> Buffer.add_string b (String.sub s i (String.length s - i))
    | true when String.sub s i n = sub ->
        Buffer.add_string b by;
        go (i + n)
    | true ->
        Buffer.add_char b s.[i];
        go (i + 1)
  in
  go 0;
  Buffer.contents b

let projection_skips_a_refused_first_image () =
  let first =
    "https://bs.plantnet.org/image/o/2fba888595d4c46b22e95bc31a63442828b16a7f"
  in
  let text =
    replace ~sub:first ~by:"https://other.org/image/o/2fba"
      (Fixture.read "gbif_plantnet_media_5414995.json")
  in
  let media =
    match Herbier_refs.Decode.json_of_string text with
    | Ok j -> j
    | Error _ -> Alcotest.fail "edited fixture does not parse"
  in
  match
    List.assoc_opt Organ.Flower
      (Projection.organ_photos_wanted (projection_of_media media))
  with
  | Some img ->
      Alcotest.(check string)
        "the next flower image, on the host"
        "https://bs.plantnet.org/image/o/7ddae0cfd2f4195f57b2d0d71cdd92154374cc8f"
        img.url
  | None -> Alcotest.fail "no flower: the refused first image hid the second"

(* ---------- plan ---------- *)

let u_flower = "https://bs.plantnet.org/image/o/flower1"
let u_leaf = "https://bs.plantnet.org/image/o/leaf1"
let u_flower_new = "https://bs.plantnet.org/image/o/flower2"

let plan_no_stored () =
  let wanted =
    [
      (Organ.Flower, gbif_image ~organ:Organ.Flower ~url:u_flower ());
      (Organ.Leaf, gbif_image ~organ:Organ.Leaf ~url:u_leaf ());
    ]
  in
  let p = Organ_photos.plan ~plant ~wanted ~stored:[] in
  check_images "put: every wanted image, thumb_path = None"
    [
      image ~organ:Organ.Flower ~remote_url:u_flower ~thumb_path:None ();
      image ~organ:Organ.Leaf ~remote_url:u_leaf ~thumb_path:None ();
    ]
    p.put;
  check_images "remove: []" [] p.remove

let plan_stored_equal_is_in_neither_list () =
  let wanted =
    [(Organ.Flower, gbif_image ~organ:Organ.Flower ~url:u_flower ())]
  in
  let stored =
    [image ~organ:Organ.Flower ~remote_url:u_flower ~thumb_path:(Some "p") ()]
  in
  let p = Organ_photos.plan ~plant ~wanted ~stored in
  check_images "put: []" [] p.put;
  check_images "remove: []" [] p.remove

let plan_other_url_drops_the_thumb () =
  let wanted =
    [(Organ.Flower, gbif_image ~organ:Organ.Flower ~url:u_flower_new ())]
  in
  let stored =
    [image ~organ:Organ.Flower ~remote_url:u_flower ~thumb_path:(Some "p") ()]
  in
  let p = Organ_photos.plan ~plant ~wanted ~stored in
  check_images "put: the new url, thumb_path = None"
    [image ~organ:Organ.Flower ~remote_url:u_flower_new ~thumb_path:None ()]
    p.put;
  check_images "remove: []" [] p.remove

let plan_same_url_other_licence_keeps_the_thumb () =
  let wanted =
    [
      ( Organ.Flower,
        gbif_image ~organ:Organ.Flower ~url:u_flower ~licence:"cc-by-sa" () );
    ]
  in
  let stored =
    [
      image ~organ:Organ.Flower ~remote_url:u_flower ~licence:"cc-by"
        ~thumb_path:(Some "p") ();
    ]
  in
  let p = Organ_photos.plan ~plant ~wanted ~stored in
  check_images "put: licence updated, thumb_path kept (url unchanged)"
    [
      image ~organ:Organ.Flower ~remote_url:u_flower ~licence:"cc-by-sa"
        ~thumb_path:(Some "p") ();
    ]
    p.put;
  check_images "remove: []" [] p.remove

let plan_same_url_other_attribution_keeps_the_thumb () =
  let wanted =
    [
      ( Organ.Flower,
        gbif_image ~organ:Organ.Flower ~url:u_flower ~attribution:"New" () );
    ]
  in
  let stored =
    [
      image ~organ:Organ.Flower ~remote_url:u_flower ~attribution:"Old"
        ~thumb_path:(Some "p") ();
    ]
  in
  let p = Organ_photos.plan ~plant ~wanted ~stored in
  check_images "put: attribution updated, thumb_path kept"
    [
      image ~organ:Organ.Flower ~remote_url:u_flower ~attribution:"New"
        ~thumb_path:(Some "p") ();
    ]
    p.put;
  check_images "remove: []" [] p.remove

let plan_ignores_rows_of_another_plant_or_source () =
  let wanted =
    [(Organ.Flower, gbif_image ~organ:Organ.Flower ~url:u_flower ())]
  in
  let stored =
    [
      image ~plant_id:other_plant ~organ:Organ.Flower ~remote_url:u_flower
        ~thumb_path:(Some "other") ();
      image ~source:Source.Gbif ~organ:Organ.Flower ~remote_url:u_flower
        ~thumb_path:(Some "gbif") ();
    ]
  in
  let p = Organ_photos.plan ~plant ~wanted ~stored in
  check_images "put: as if nothing were stored"
    [image ~organ:Organ.Flower ~remote_url:u_flower ~thumb_path:None ()]
    p.put;
  check_images "remove: []" [] p.remove

let plan_organ_not_wanted_is_removed () =
  let wanted =
    [(Organ.Flower, gbif_image ~organ:Organ.Flower ~url:u_flower ())]
  in
  let stored_habit =
    image ~organ:Organ.Habit ~remote_url:"https://bs.plantnet.org/image/o/h"
      ~thumb_path:(Some "ph") ()
  in
  let stored_flower =
    image ~organ:Organ.Flower ~remote_url:u_flower ~thumb_path:(Some "pf") ()
  in
  let another_plant_habit = {stored_habit with plant_id = other_plant} in
  let gbif_habit = {stored_habit with source = Source.Gbif} in
  let p =
    Organ_photos.plan ~plant ~wanted
      ~stored:[stored_flower; stored_habit; another_plant_habit; gbif_habit]
  in
  check_images "put: []" [] p.put;
  check_images "remove: only this plant's unwanted Plantnet row" [stored_habit]
    p.remove

let plan_empty_wanted_removes_every_stored_plantnet_row () =
  let stored_flower =
    image ~organ:Organ.Flower ~remote_url:u_flower ~thumb_path:(Some "pf") ()
  in
  let stored_leaf =
    image ~organ:Organ.Leaf ~remote_url:u_leaf ~thumb_path:(Some "pl") ()
  in
  let other_plant_row = {stored_flower with plant_id = other_plant} in
  let gbif_row = {stored_flower with source = Source.Gbif} in
  let p =
    Organ_photos.plan ~plant ~wanted:[]
      ~stored:[stored_flower; stored_leaf; other_plant_row; gbif_row]
  in
  check_images "put: []" [] p.put;
  check_images "remove: both of the plant's Plantnet rows, organ order"
    [stored_flower; stored_leaf]
    p.remove

(* ---------- to_download ---------- *)

let to_download () =
  let with_thumb =
    image ~organ:Organ.Flower ~remote_url:u_flower ~thumb_path:(Some "p") ()
  in
  let no_thumb_leaf =
    image ~organ:Organ.Leaf ~remote_url:u_leaf ~thumb_path:None ()
  in
  let no_thumb_habit =
    image ~organ:Organ.Habit ~remote_url:"https://bs.plantnet.org/image/o/h"
      ~thumb_path:None ()
  in
  check_images "only None thumbs, organ order whatever the input order"
    [no_thumb_leaf; no_thumb_habit]
    (Organ_photos.to_download [no_thumb_habit; with_thumb; no_thumb_leaf])

(* ---------- shown ---------- *)

let shown () =
  let flower_img = gbif_image ~organ:Organ.Flower ~url:u_flower () in
  let leaf_img = gbif_image ~organ:Organ.Leaf ~url:u_leaf () in
  let habit_url = "https://bs.plantnet.org/image/o/h" in
  let habit_img = gbif_image ~organ:Organ.Habit ~url:habit_url () in
  let stored_flower =
    image ~organ:Organ.Flower ~remote_url:u_flower ~thumb_path:(Some "pf") ()
  in
  let stored_leaf_no_thumb =
    image ~organ:Organ.Leaf ~remote_url:u_leaf ~thumb_path:None ()
  in
  let stored_habit_stale =
    image ~organ:Organ.Habit ~remote_url:"https://bs.plantnet.org/image/o/old"
      ~thumb_path:(Some "ph") ()
  in
  let wanted =
    [
      (Organ.Flower, flower_img);
      (Organ.Leaf, leaf_img);
      (Organ.Habit, habit_img);
    ]
  in
  let stored = [stored_flower; stored_leaf_no_thumb; stored_habit_stale] in
  let got = Organ_photos.shown ~wanted ~stored in
  (match got with
  | [(img, path)] ->
      check_images "the matching, downloaded image is shown" [stored_flower]
        [img];
      Alcotest.(check string) "with its path" "pf" path
  | got ->
      Alcotest.failf
        "expected exactly 1 shown image (leaf has no thumb, habit's url is \
         stale), got %d"
        (List.length got));
  (* order follows [wanted] *)
  let stored_flower2 =
    image ~organ:Organ.Flower ~remote_url:u_flower ~thumb_path:(Some "pf") ()
  in
  let stored_habit2 =
    image ~organ:Organ.Habit ~remote_url:habit_url ~thumb_path:(Some "ph") ()
  in
  match
    Organ_photos.shown
      ~wanted:[(Organ.Habit, habit_img); (Organ.Flower, flower_img)]
      ~stored:[stored_flower2; stored_habit2]
  with
  | [(a, _); (b, _)] ->
      Alcotest.(check string)
        "first, habit (wanted order)" "habit" (Organ.to_string a.organ);
      Alcotest.(check string)
        "second, flower" "flower" (Organ.to_string b.organ)
  | got -> Alcotest.failf "expected 2 shown images, got %d" (List.length got)

let shown_only_plantnet_rows () =
  let flower_img = gbif_image ~organ:Organ.Flower ~url:u_flower () in
  let gbif_row =
    image ~source:Source.Gbif ~organ:Organ.Flower ~remote_url:u_flower
      ~thumb_path:(Some "gbif") ()
  in
  Alcotest.(check int)
    "a Gbif row alone is not shown" 0
    (List.length
       (Organ_photos.shown
          ~wanted:[(Organ.Flower, flower_img)]
          ~stored:[gbif_row]));
  let plantnet_row =
    image ~organ:Organ.Flower ~remote_url:u_flower ~thumb_path:(Some "pn") ()
  in
  match
    Organ_photos.shown
      ~wanted:[(Organ.Flower, flower_img)]
      ~stored:[gbif_row; plantnet_row]
  with
  | [(_, path)] -> Alcotest.(check string) "the Plantnet row's thumb" "pn" path
  | got -> Alcotest.failf "expected 1 shown image, got %d" (List.length got)

(* ---------- a second sync ---------- *)

(* The first sync puts every wanted row and downloads each thumbnail; the
   second plans over those rows: nothing to do, every organ shown. *)
let second_sync_is_a_noop what images organs =
  let wanted = Organ_photos.wanted images in
  let p1 = Organ_photos.plan ~plant ~wanted ~stored:[] in
  let stored =
    List.map
      (fun (r : Reference.Image.t) ->
        {r with thumb_path = Some (Organ.to_string r.organ)})
      p1.put
  in
  let p2 = Organ_photos.plan ~plant ~wanted ~stored in
  check_images (what ^ ": put") [] p2.put;
  check_images (what ^ ": remove") [] p2.remove;
  Alcotest.(check (list string))
    (what ^ ": shown") organs
    (List.map
       (fun ((r : Reference.Image.t), _) -> Organ.to_string r.organ)
       (Organ_photos.shown ~wanted ~stored))

let second_sync_digitalis () =
  second_sync_is_a_noop "digitalis" (digitalis_images ())
    ["flower"; "leaf"; "habit"]

let second_sync_arnica () =
  second_sync_is_a_noop "arnica" (arnica_images ())
    ["flower"; "leaf"; "fruit"; "habit"]

(* ---------- report ---------- *)

let outcome_name : string Organ_photos.outcome -> string = function
  | Present -> "present"
  | Updated -> "updated"
  | Downloaded -> "downloaded"
  | Removed -> "removed"
  | Failed why -> "failed " ^ why

let report () =
  let flower = gbif_image ~organ:Organ.Flower ~url:u_flower () in
  let leaf = gbif_image ~organ:Organ.Leaf ~url:u_leaf () in
  let habit_url = "https://bs.plantnet.org/image/o/h" in
  let habit = gbif_image ~organ:Organ.Habit ~url:habit_url () in
  let row organ remote_url = image ~organ ~remote_url () in
  let plan : Organ_photos.plan =
    {
      put = [row Organ.Leaf u_leaf; row Organ.Habit habit_url];
      remove = [row Organ.Fruit "https://bs.plantnet.org/image/o/fr"];
    }
  in
  let downloads =
    [
      (row Organ.Habit habit_url, Organ_photos.Failed "HTTP 404");
      (* A row both removed and downloaded counts as removed. *)
      (row Organ.Fruit "https://bs.plantnet.org/image/o/fr", Downloaded);
    ]
  in
  Alcotest.(check (list (pair string string)))
    "Removed first, then the download, then Updated, then Present; an organ \
     neither wanted nor touched is left out"
    [
      ("flower", "present");
      ("leaf", "updated");
      ("fruit", "removed");
      ("habit", "failed HTTP 404");
    ]
    (List.map
       (fun (o, x) -> (Organ.to_string o, outcome_name x))
       (Organ_photos.report
          ~wanted:
            [(Organ.Flower, flower); (Organ.Leaf, leaf); (Organ.Habit, habit)]
          ~plan downloads));
  Alcotest.(check (list (pair string string)))
    "nothing wanted, nothing touched: []" []
    (List.map
       (fun (o, x) -> (Organ.to_string o, outcome_name x))
       (Organ_photos.report ~wanted:[] ~plan:{put = []; remove = []} []))

let changed () =
  let case expected (o : string Organ_photos.outcome) =
    Alcotest.(check bool)
      (outcome_name o) expected
      (Organ_photos.changed
         [(Organ.Flower, Organ_photos.Present); (Organ.Leaf, o)])
  in
  case false Present;
  case true Updated;
  case true Downloaded;
  case true Removed;
  case false (Failed "x");
  Alcotest.(check bool) "[]" false (Organ_photos.changed [])

(* ---------- fit ---------- *)

let fit () =
  let case what ~width ~height expected =
    Alcotest.(check (pair int int))
      what expected
      (Organ_photos.fit ~width ~height)
  in
  Alcotest.(check int) "max_side" 300 Organ_photos.max_side;
  Alcotest.(check (float 0.)) "quality" 0.8 Organ_photos.quality;
  case "landscape 4:3" ~width:4000 ~height:3000 (400, 300);
  case "portrait 3:4" ~width:3000 ~height:4000 (300, 400);
  case "already small, square" ~width:300 ~height:300 (300, 300);
  case "smaller than max_side: no upscale" ~width:200 ~height:100 (200, 100);
  case "very thin" ~width:1000 ~height:1 (1000, 1);
  case "zero height" ~width:0 ~height:10 (1, 1);
  case "negative" ~width:(-5) ~height:(-5) (1, 1);
  case "shorter side 999 → 300, longer 300.3 → 300" ~width:1000 ~height:999
    (300, 300);
  case "rounded to nearest, not truncated: 398.67 → 399" ~width:400 ~height:301
    (399, 300);
  case "a half rounds up: 500.5 → 501" ~width:1001 ~height:600 (501, 300)

(* ---------- run ---------- *)

let case name f = (name, `Quick, f)

let suite =
  ( "organ_photos",
    [
      case
        "downloadable: host, scheme, host suffix, userinfo, port, whitespace, \
         control characters, quote, angle brackets, backslash, non-ASCII"
        downloadable;
      case
        "projection: a refused first image of an organ gives way to the next \
         one on the host"
        projection_skips_a_refused_first_image;
      case "wanted over the recorded Pl@ntNet payload: Digitalis (no fruit)"
        wanted_digitalis;
      case "wanted over the recorded Pl@ntNet payload: Arnica (all four organs)"
        wanted_arnica;
      case "wanted: organ = None skipped, another host skipped, Organ.all order"
        wanted_rules;
      case "plan: no stored rows puts every wanted image" plan_no_stored;
      case
        "plan: a stored row equal on url/licence/attribution is in neither list"
        plan_stored_equal_is_in_neither_list;
      case "plan: another url is put with thumb_path = None"
        plan_other_url_drops_the_thumb;
      case "plan: same url, other licence, keeps the stored thumb_path"
        plan_same_url_other_licence_keeps_the_thumb;
      case "plan: same url, other attribution, keeps the stored thumb_path"
        plan_same_url_other_attribution_keeps_the_thumb;
      case "plan: rows of another plant or of source Gbif are not this organ's"
        plan_ignores_rows_of_another_plant_or_source;
      case
        "plan: a stored organ not wanted is removed; another plant or source \
         Gbif is never removed"
        plan_organ_not_wanted_is_removed;
      case "plan: wanted = [] removes every stored Plantnet row of the plant"
        plan_empty_wanted_removes_every_stored_plantnet_row;
      case "to_download: only None thumbs, organ order" to_download;
      case
        "shown: matching url + thumb shown; no thumb or stale url not shown; \
         order follows wanted"
        shown;
      case "shown: only Plantnet rows" shown_only_plantnet_rows;
      case "a second sync over Digitalis plans nothing and shows every organ"
        second_sync_digitalis;
      case "a second sync over Arnica plans nothing and shows every organ"
        second_sync_arnica;
      case "report: precedence and Organ.all order" report;
      case "changed: Updated, Downloaded or Removed" changed;
      case
        "fit: shorter side at most max_side, no upscale, rounding, degenerate \
         inputs"
        fit;
    ] )
