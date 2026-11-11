(* Smoke run of herbier_refs compiled by js_of_ocaml, under node:
   - plantnet_media_of_json keeps every image of both recorded occurrence
     pages under jsoo's 32-bit int, same count as the native decoder;
   - the occurrence key above 2^31 comes out as its digit string, not
     dropped or wrapped;
   - species_of_json decodes a plain species payload.
   Silent on success; prints the failing checks to stderr and exits 1. *)

module Decode = Herbier_refs.Decode
module Gbif = Herbier_refs.Sources.Gbif

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
      ]
  in
  match failures with
  | [] -> ()
  | fs ->
      List.iter prerr_endline fs;
      exit 1
