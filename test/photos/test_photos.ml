(* Exif.of_json over exifr output recorded by scripts/exifr-fixture.mjs
   (test/fixtures/exifr_*.json) and over hand-written objects for the edge
   cases. *)

let fixture name =
  let path = Filename.concat "../fixtures" ("exifr_" ^ name ^ ".json") in
  In_channel.with_open_bin path In_channel.input_all

let time s =
  match Ptime.of_rfc3339 s with
  | Ok (t, _, _) -> t
  | Error _ -> Alcotest.failf "bad RFC 3339 literal %S" s

let pp_time ppf t = Ptime.pp_rfc3339 ~frac_s:6 () ppf t
let instant = Alcotest.testable pp_time Ptime.equal

let pp_position ppf (p : Herbier_domain.Observation.position) =
  Format.fprintf ppf "%.6f,%.6f ±%s" p.lat p.lon
    (match p.accuracy_m with Some a -> Printf.sprintf "%g" a | None -> "?")

let position = Alcotest.testable pp_position ( = )

let check_time msg expected (e : Exif.t) =
  Alcotest.(check (option instant)) msg expected e.taken_at

let check_position msg expected (e : Exif.t) =
  Alcotest.(check (option position)) msg expected e.position

let pos ?accuracy_m lat lon : Herbier_domain.Observation.position =
  {lat; lon; accuracy_m}

let fixed offset_s (_ : Ptime.date) (_ : int * int * int) = offset_s

let of_fields ?(tz_offset_s = 0) fields =
  Exif.of_json ~tz_offset_at:(fixed tz_offset_s) (`Assoc fields)

let refs = [("GPSLatitudeRef", `String "N"); ("GPSLongitudeRef", `String "E")]
let date = ("DateTimeOriginal", `String "2026:05:12 14:03:22")

let fixture_tests =
  [
    ( "offset, sub-seconds and GPS accuracy",
      `Quick,
      fun () ->
        let e =
          Exif.of_string ~tz_offset_at:(fixed (-3600))
            (fixture "pil_offset_gps")
        in
        check_time "OffsetTimeOriginal wins over the device offset"
          (Some (time "2026-05-12T12:03:22.417Z"))
          e;
        check_position "decimal position with GPSHPositioningError"
          (Some (pos ~accuracy_m:12.5 45.17516666666666 5.72))
          e );
    ( "no offset reads the wall clock at the device offset",
      `Quick,
      fun () ->
        let text = fixture "pil_no_offset_south_west" in
        check_time "at +01:00"
          (Some (time "2025-11-30T07:15:00Z"))
          (Exif.of_string ~tz_offset_at:(fixed 3600) text);
        check_time "at -03:00"
          (Some (time "2025-11-30T11:15:00Z"))
          (Exif.of_string ~tz_offset_at:(fixed (-10800)) text) );
    ( "south and west are negative, no accuracy",
      `Quick,
      fun () ->
        check_position "position"
          (Some (pos (-33.865) (-70.65)))
          (Exif.of_string ~tz_offset_at:(fixed 0)
             (fixture "pil_no_offset_south_west")) );
    ( "unset clock and 0,0 give nothing",
      `Quick,
      fun () ->
        let e =
          Exif.of_string ~tz_offset_at:(fixed 0)
            (fixture "pil_unset_clock_no_fix")
        in
        check_time "taken_at" None e;
        check_position "position" None e );
    ( "the system picker's copy keeps the date, not the position",
      `Quick,
      fun () ->
        let e =
          Exif.of_string ~tz_offset_at:(fixed 0)
            (fixture "picker_pil_offset_gps")
        in
        check_time "date, offset and sub-seconds survive"
          (Some (time "2026-05-12T12:03:22.417Z"))
          e;
        check_position "GPS tags emptied, accuracy alone" None e );
    ( "the emulator camera writes no offset and no GPS",
      `Quick,
      fun () ->
        let e =
          Exif.of_string ~tz_offset_at:(fixed 3600) (fixture "emulator_camera")
        in
        check_time "wall clock at the device offset"
          (Some (time "2026-11-10T20:29:32.118Z"))
          e;
        check_position "position" None e );
  ]

let time_tests =
  [
    ( "negative half-hour offset",
      `Quick,
      fun () ->
        check_time "-05:30"
          (Some (time "2026-05-12T19:33:22Z"))
          (of_fields [date; ("OffsetTimeOriginal", `String "-05:30")]) );
    ( "malformed offset falls back to the device offset",
      `Quick,
      fun () ->
        check_time "02:00 without sign"
          (Some (time "2026-05-12T12:03:22Z"))
          (of_fields ~tz_offset_s:7200
             [date; ("OffsetTimeOriginal", `String "02:00")]) );
    ( "sub-seconds truncated to microseconds",
      `Quick,
      fun () ->
        check_time "1234567"
          (Some (time "2026-05-12T14:03:22.123456Z"))
          (of_fields [date; ("SubSecTimeOriginal", `String "1234567")]) );
    ( "non-digit sub-seconds ignored",
      `Quick,
      fun () ->
        check_time "4a"
          (Some (time "2026-05-12T14:03:22Z"))
          (of_fields [date; ("SubSecTimeOriginal", `String "4a")]) );
    ( "invalid month",
      `Quick,
      fun () ->
        check_time "month 13" None
          (of_fields [("DateTimeOriginal", `String "2026:13:12 14:03:22")]) );
    ( "blank date",
      `Quick,
      fun () ->
        check_time "blanks" None
          (of_fields [("DateTimeOriginal", `String "    :  :     :  :  ")]) );
    ( "ISO date is not the EXIF form",
      `Quick,
      fun () ->
        check_time "revived value" None
          (of_fields [("DateTimeOriginal", `String "2026-05-12T14:03:22.000Z")])
    );
    ("no date", `Quick, fun () -> check_time "missing" None (of_fields []));
  ]

let position_tests =
  [
    ( "integer coordinates",
      `Quick,
      fun () ->
        check_position "ints"
          (Some (pos 45. 5.))
          (of_fields (refs @ [("latitude", `Int 45); ("longitude", `Int 5)])) );
    ( "latitude out of range",
      `Quick,
      fun () ->
        check_position "91" None
          (of_fields
             (refs @ [("latitude", `Float 91.); ("longitude", `Float 5.)])) );
    ( "longitude out of range",
      `Quick,
      fun () ->
        check_position "181" None
          (of_fields
             (refs @ [("latitude", `Float 45.); ("longitude", `Float 181.)])) );
    ( "the range bounds are included",
      `Quick,
      fun () ->
        check_position "90, -180"
          (Some (pos 90. (-180.)))
          (of_fields
             [
               ("GPSLatitudeRef", `String "N");
               ("GPSLongitudeRef", `String "W");
               ("latitude", `Float 90.);
               ("longitude", `Float (-180.));
             ]) );
    ( "negative accuracy is unknown",
      `Quick,
      fun () ->
        check_position "-3 m"
          (Some (pos 45. 5.))
          (of_fields
             (refs
             @ [
                 ("latitude", `Float 45.);
                 ("longitude", `Float 5.);
                 ("GPSHPositioningError", `Int (-3));
               ])) );
    ( "longitude without latitude",
      `Quick,
      fun () ->
        check_position "half" None (of_fields [("longitude", `Float 5.)]) );
    ( "zero accuracy is unknown",
      `Quick,
      fun () ->
        check_position "0 m"
          (Some (pos 45. 5.))
          (of_fields
             (refs
             @ [
                 ("latitude", `Float 45.);
                 ("longitude", `Float 5.);
                 ("GPSHPositioningError", `Int 0);
               ])) );
    ( "one zero coordinate is a real position",
      `Quick,
      fun () ->
        check_position "equator"
          (Some (pos 0. 5.))
          (of_fields
             (refs @ [("latitude", `Float 0.); ("longitude", `Float 5.)])) );
  ]

let coords = [("latitude", `Float 45.); ("longitude", `Float 5.)]

let missing_ref_tests =
  [
    ( "no hemisphere refs, no position",
      `Quick,
      fun () -> check_position "exifr assumed N/E" None (of_fields coords) );
    ( "latitude ref alone",
      `Quick,
      fun () ->
        check_position "no GPSLongitudeRef" None
          (of_fields (("GPSLatitudeRef", `String "N") :: coords)) );
    ( "longitude ref alone",
      `Quick,
      fun () ->
        check_position "no GPSLatitudeRef" None
          (of_fields (("GPSLongitudeRef", `String "E") :: coords)) );
    ( "a ref other than N/S/E/W",
      `Quick,
      fun () ->
        check_position "lowercase s, which exifr does not negate" None
          (of_fields
             (("GPSLatitudeRef", `String "s")
             :: ("GPSLongitudeRef", `String "E")
             :: coords)) );
  ]

let offset_tests =
  [
    ( "the fallback offset is the one at the photo's local time",
      `Quick,
      fun () ->
        let summer (date : Ptime.date) (time : int * int * int) =
          match (date, time) with
          | (2026, 7, 14), (9, 8, 7) -> 7200
          | _ -> Alcotest.fail "tz_offset_at got another date or time"
        in
        check_time "a July 09:08:07 photo at +02:00"
          (Some (time "2026-07-14T07:08:07Z"))
          (Exif.of_json ~tz_offset_at:summer
             (`Assoc [("DateTimeOriginal", `String "2026:07:14 09:08:07")])) );
    ( "an offset hour above 18 falls back to the device offset",
      `Quick,
      fun () ->
        check_time "+19:00"
          (Some (time "2026-05-12T12:03:22Z"))
          (of_fields ~tz_offset_s:7200
             [date; ("OffsetTimeOriginal", `String "+19:00")]) );
    ( "an offset minute of 60 falls back to the device offset",
      `Quick,
      fun () ->
        check_time "+02:60"
          (Some (time "2026-05-12T12:03:22Z"))
          (of_fields ~tz_offset_s:7200
             [date; ("OffsetTimeOriginal", `String "+02:60")]) );
    ( "a parsed offset does not ask for the device offset",
      `Quick,
      fun () ->
        let never (_ : Ptime.date) (_ : int * int * int) =
          Alcotest.fail "tz_offset_at called"
        in
        check_time "+02:00"
          (Some (time "2026-05-12T12:03:22Z"))
          (Exif.of_json ~tz_offset_at:never
             (`Assoc [date; ("OffsetTimeOriginal", `String "+02:00")])) );
  ]

let input_tests =
  [
    ( "not an object",
      `Quick,
      fun () ->
        let e = Exif.of_json ~tz_offset_at:(fixed 0) `Null in
        check_time "taken_at" None e;
        check_position "position" None e );
    ( "not JSON",
      `Quick,
      fun () ->
        let e = Exif.of_string ~tz_offset_at:(fixed 0) "{" in
        check_time "taken_at" None e;
        check_position "position" None e );
  ]

let tag_tests =
  [
    ( "the fixtures hold only picked tags",
      `Quick,
      fun () ->
        List.iter
          (fun name ->
            match Yojson.Safe.from_string (fixture name) with
            | `Assoc fields ->
                List.iter
                  (fun (key, _) ->
                    match
                      List.mem key ("latitude" :: "longitude" :: Exif.tags)
                    with
                    | true -> ()
                    | false ->
                        Alcotest.failf "%s: %s is not in Exif.tags" name key)
                  fields
            | _ -> Alcotest.failf "%s: not an object" name)
          [
            "pil_offset_gps";
            "pil_no_offset_south_west";
            "pil_unset_clock_no_fix";
          ] );
    ( "the fixture script picks Exif.tags",
      `Quick,
      fun () ->
        let script =
          In_channel.with_open_bin "../../scripts/exifr-fixture.mjs"
            In_channel.input_all
        in
        let rec after_pick = function
          | [] -> Alcotest.fail "no pick: [ line in the script"
          | line :: rest -> (
              match String.trim line with
              | "pick: [" -> rest
              | _ -> after_pick rest)
        in
        let rec until_close = function
          | [] -> []
          | line :: rest -> (
              match String.split_on_char '\'' line with
              | [_; tag; _] -> tag :: until_close rest
              | _ -> [])
        in
        let picked =
          until_close (after_pick (String.split_on_char '\n' script))
        in
        Alcotest.(check (list string)) "pick" Exif.tags picked );
  ]

let () =
  Alcotest.run "photos"
    [
      ("exif fixtures", fixture_tests);
      ("exif taken_at", time_tests);
      ("exif position", position_tests);
      ("exif missing refs", missing_ref_tests);
      ("exif fallback offset", offset_tests);
      ("exif input", input_tests);
      ("exif tags", tag_tests);
    ]
