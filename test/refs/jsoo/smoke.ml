(* Smoke run of herbier_refs compiled by js_of_ocaml, under node:
   - plantnet_media_of_json keeps every image of both recorded occurrence
     pages under jsoo's 32-bit int, same count as the native decoder;
   - the occurrence key above 2^31 comes out as its digit string, not
     dropped or wrapped;
   - species_of_json decodes a plain species payload;
   - a Payload.plantnet round trip (prune then Payload.get) keeps the same
     occurrence keys as decoding the raw body, above 2^31 included.
   Silent on success; prints the failing checks to stderr and exits 1. *)

module Decode = Herbier_refs.Decode
module Gbif = Herbier_refs.Sources.Gbif
module Payload = Herbier_refs.Payload

let check what ok = if ok then None else Some what

let decode_json what body =
  match Decode.json_of_string body with
  | Ok j -> j
  | Error e -> failwith (what ^ ": " ^ Decode.error_to_string e)

let plantnet_media_failures what body expected_count =
  match Gbif.plantnet_media_of_json (decode_json what body) with
  | Error e ->
      [Printf.sprintf "%s: decode failed: %s" what (Decode.error_to_string e)]
  | Ok page ->
      List.filter_map Fun.id
        [
          check
            (Printf.sprintf "%s: image count is %d" what expected_count)
            (List.length page.results = expected_count);
        ]

let digitalis_occurrence_key_failures () =
  match
    Gbif.plantnet_media_of_json
      (decode_json "plantnet_digitalis" Fixtures.plantnet_digitalis)
  with
  | Error e ->
      [
        Printf.sprintf "plantnet_digitalis: decode failed: %s"
          (Decode.error_to_string e);
      ]
  | Ok {results = first :: _; _} ->
      List.filter_map Fun.id
        [
          check
            "plantnet_digitalis: first occurrence_key is the digit string \
             5110295086 (above 2^31)"
            (String.equal first.occurrence_key "5110295086");
        ]
  | Ok {results = []; _} -> ["plantnet_digitalis: no images decoded"]

let occurrence_keys (p : Gbif.Image.t Gbif.page) =
  List.map (fun (i : Gbif.Image.t) -> i.occurrence_key) p.results

let same_keys a b =
  List.length a = List.length b && List.for_all2 String.equal a b

let payload_round_trip_failures () =
  let what = "plantnet_digitalis (Payload round trip)" in
  let body = decode_json what Fixtures.plantnet_digitalis in
  match Gbif.plantnet_media_of_json body with
  | Error e ->
      [
        Printf.sprintf "%s: raw decode failed: %s" what
          (Decode.error_to_string e);
      ]
  | Ok raw_page -> (
      let payload = Payload.plantnet ~media:(Some body) in
      match Payload.get Plantnet_media payload with
      | None -> [Printf.sprintf "%s: Payload.get Plantnet_media gave None" what]
      | Some pruned -> (
          match Gbif.plantnet_media_of_json pruned with
          | Error e ->
              [
                Printf.sprintf "%s: pruned decode failed: %s" what
                  (Decode.error_to_string e);
              ]
          | Ok pruned_page ->
              List.filter_map Fun.id
                [
                  check
                    (Printf.sprintf
                       "%s: occurrence keys survive the round trip, above 2^31 \
                        included"
                       what)
                    (same_keys (occurrence_keys raw_page)
                       (occurrence_keys pruned_page));
                ]))

let species_failures () =
  match
    Gbif.species_of_json
      (decode_json "species_digitalis" Fixtures.species_digitalis)
  with
  | Error e ->
      [
        Printf.sprintf "species_digitalis: decode failed: %s"
          (Decode.error_to_string e);
      ]
  | Ok t ->
      List.filter_map Fun.id
        [check "species_digitalis: key is 5414995" (t.key = 5414995)]

let () =
  let failures =
    List.concat
      [
        plantnet_media_failures "plantnet_digitalis" Fixtures.plantnet_digitalis
          53;
        plantnet_media_failures "plantnet_arnica" Fixtures.plantnet_arnica 64;
        digitalis_occurrence_key_failures ();
        species_failures ();
        payload_round_trip_failures ();
      ]
  in
  match failures with
  | [] -> ()
  | fs ->
      List.iter prerr_endline fs;
      exit 1
