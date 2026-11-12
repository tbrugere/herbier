(* Compile-time property, not tested here: the [t] types are pairwise
   distinct and abstract (each [t] is abstract in ids.mli), so a
   Plant_id.t passed where an Observation_id.t is expected is a type error. *)

let v = "123e4567-e89b-42d3-a456-426614174000"
let nil = "00000000-0000-0000-0000-000000000000"
let version_1 = "123e4567-e89b-12d3-a456-426614174000"
let is_lower_hex = function '0' .. '9' | 'a' .. 'f' -> true | _ -> false
let sign n = Int.compare n 0

module Cases (I : Herbier_domain.Ids.S) = struct
  let id = Alcotest.testable I.pp I.equal

  let parse s =
    match I.of_string s with
    | Some x -> x
    | None -> Alcotest.failf "of_string %S gave None" s

  let fresh_round_trips () =
    let x = I.fresh () in
    Alcotest.(check (option id))
      "of_string (to_string fresh) is the same id" (Some x)
      (I.of_string (I.to_string x))

  let fresh_is_canonical_v7 () =
    let s = I.to_string (I.fresh ()) in
    Alcotest.(check int) "length is 36" 36 (String.length s);
    List.iter
      (fun i ->
        Alcotest.(check char) (Printf.sprintf "hyphen at %d" i) '-' s.[i])
      [8; 13; 18; 23];
    String.iteri
      (fun i c ->
        match i with
        | 8 | 13 | 18 | 23 -> ()
        | _ ->
            Alcotest.(check bool)
              (Printf.sprintf "char %d (%C) is lowercase hex" i c)
              true (is_lower_hex c))
      s;
    Alcotest.(check char) "version nibble is 7" '7' s.[14];
    Alcotest.(check bool)
      (Printf.sprintf "variant nibble %C is one of 8 9 a b" s.[19])
      true
      (String.contains "89ab" s.[19])

  (* Milliseconds since the epoch, computed the same way as in ids.ml. *)
  let now_ms () =
    let d, ps = Ptime.Span.to_d_ps (Ptime.to_span (Ptime_clock.now ())) in
    Int64.(add (mul (of_int d) 86_400_000L) (div ps 1_000_000_000L))

  (* The first 48 bits of a v7 UUID, read back from its text. *)
  let time_ms_of_string s =
    Int64.of_string ("0x" ^ String.sub s 0 8 ^ String.sub s 9 4)

  let fresh_carries_the_clock () =
    let before = now_ms () in
    let t = time_ms_of_string (I.to_string (I.fresh ())) in
    let after = now_ms () in
    Alcotest.(check bool)
      (Printf.sprintf "timestamp %Ld lies in [%Ld, %Ld]" t before after)
      true
      (Int64.compare before t <= 0 && Int64.compare t after <= 0)

  let fresh_is_time_ordered () =
    (* Start on a fresh millisecond so the per-millisecond counter is empty. *)
    let t0 = now_ms () in
    let rec spin () =
      match Int64.equal (now_ms ()) t0 with true -> spin () | false -> ()
    in
    spin ();
    let ids = List.init 100 (fun _ -> I.fresh ()) in
    Alcotest.(check (list string))
      "100 ids minted in a row sort in minting order" (List.map I.to_string ids)
      (List.map I.to_string (List.sort I.compare ids))

  let fresh_is_unique () =
    let n = 10_000 in
    let strings = List.init n (fun _ -> I.to_string (I.fresh ())) in
    Alcotest.(check int)
      "10 000 fresh ids are pairwise distinct" n
      (List.length (List.sort_uniq String.compare strings))

  let equal_distinguishes () =
    let a = parse v in
    let b = parse "923e4567-e89b-42d3-a456-426614174000" in
    Alcotest.(check bool) "an id equals itself" true (I.equal a a);
    Alcotest.(check bool) "distinct ids are not equal" false (I.equal a b);
    Alcotest.(check bool)
      "two fresh ids are not equal" false
      (I.equal (I.fresh ()) (I.fresh ()))

  let parses_canonical () =
    Alcotest.(check (option string))
      "to_string of the parsed id is the input" (Some v)
      (Option.map I.to_string (I.of_string v))

  let parses_uppercase () =
    let lower = parse v in
    let upper = parse (String.uppercase_ascii v) in
    Alcotest.(check string)
      "uppercase input prints lowercase" v (I.to_string upper);
    Alcotest.(check id) "uppercase and lowercase ids are equal" lower upper;
    let mixed = parse "123E4567-e89b-42D3-a456-426614174000" in
    Alcotest.(check string)
      "mixed-case input prints lowercase" v (I.to_string mixed);
    Alcotest.(check id) "mixed-case and lowercase ids are equal" lower mixed

  let accepts_any_version () =
    Alcotest.(check (option string))
      "nil UUID is accepted" (Some nil)
      (Option.map I.to_string (I.of_string nil));
    Alcotest.(check (option string))
      "version 1 UUID is accepted" (Some version_1)
      (Option.map I.to_string (I.of_string version_1))

  let rejected =
    [
      ("empty string", "");
      ("not-a-uuid", "not-a-uuid");
      ("35 characters", String.sub v 0 35);
      ("37 characters", v ^ "0");
      ("leading space", " " ^ v);
      ("trailing newline", v ^ "\n");
      ("leading space, 36 chars", " " ^ String.sub v 1 35);
      ("trailing space, 36 chars", String.sub v 0 35 ^ " ");
      ("braces", "{" ^ v ^ "}");
      ( "32 hex digits without hyphens",
        String.concat "" (String.split_on_char '-' v) );
      ("non-hex digit g", "g" ^ String.sub v 1 35);
      ("hyphen moved, still 36 chars", "123e4567e-89b-42d3-a456-426614174000");
    ]

  let rejects () =
    List.iter
      (fun (what, s) ->
        Alcotest.(check (option string))
          (what ^ " is rejected") None
          (Option.map I.to_string (I.of_string s)))
      rejected

  let compare_orders_like_strings () =
    let a = parse v in
    let b = parse "923e4567-e89b-42d3-a456-426614174000" in
    Alcotest.(check int) "compare a a is 0" 0 (I.compare a a);
    Alcotest.(check int)
      "compare a b has the sign of String.compare on to_string"
      (sign (String.compare (I.to_string a) (I.to_string b)))
      (sign (I.compare a b));
    Alcotest.(check int)
      "compare b a has the sign of String.compare on to_string"
      (sign (String.compare (I.to_string b) (I.to_string a)))
      (sign (I.compare b a));
    Alcotest.(check int) "a sorts before b" (-1) (sign (I.compare a b));
    Alcotest.(check int)
      "compare with the uppercase-parsed twin is 0" 0
      (I.compare a (parse (String.uppercase_ascii v)))

  let pp_prints_to_string () =
    let x = parse v in
    Alcotest.(check string)
      "pp prints to_string" v
      (Format.asprintf "%a" I.pp x)

  let json = Alcotest.testable Yojson.Safe.pp Yojson.Safe.equal

  let json_round_trips () =
    let x = parse v in
    Alcotest.(check json)
      "to_json is the JSON string of to_string" (`String v) (I.to_json x);
    Alcotest.(check (option id))
      "of_json (to_json x) is x" (Some x)
      (I.of_json (I.to_json x));
    Alcotest.(check (option id))
      "of_json of an uppercase string is the id" (Some x)
      (I.of_json (`String (String.uppercase_ascii v)))

  let json_rejects () =
    List.iter
      (fun (what, j) ->
        Alcotest.(check (option id)) (what ^ " is rejected") None (I.of_json j))
      [
        ("a non-uuid string", `String "not-a-uuid");
        ("null", `Null);
        ("an int", `Int 1);
        ("a list holding the uuid", `List [`String v]);
      ]

  let tests name =
    List.map
      (fun (fact, f) -> (name ^ ": " ^ fact, `Quick, f))
      [
        ("fresh round-trips through to_string and of_string", fresh_round_trips);
        ( "fresh prints as a canonical lowercase version 7 UUID",
          fresh_is_canonical_v7 );
        ("fresh carries the current millisecond", fresh_carries_the_clock);
        ("fresh ids sort in minting order", fresh_is_time_ordered);
        ("10 000 fresh ids are distinct", fresh_is_unique);
        ("equal tells distinct ids apart", equal_distinguishes);
        ("of_string accepts the canonical form", parses_canonical);
        ( "of_string accepts upper and mixed case, normalised to lowercase",
          parses_uppercase );
        ("of_string accepts the nil and a version 1 UUID", accepts_any_version);
        ("of_string rejects every non-canonical form", rejects);
        ( "compare is the lexicographic order of to_string",
          compare_orders_like_strings );
        ("pp prints the canonical form", pp_prints_to_string);
        ("of_json inverts to_json, a JSON string", json_round_trips);
        ("of_json rejects other strings and non-strings", json_rejects);
      ]
end

module Plant = Cases (Herbier_domain.Ids.Plant_id)
module Observation = Cases (Herbier_domain.Ids.Observation_id)
module Photo = Cases (Herbier_domain.Ids.Photo_id)
module Tag = Cases (Herbier_domain.Ids.Tag_id)
module Plant_tag = Cases (Herbier_domain.Ids.Plant_tag_id)
module Plant_ref = Cases (Herbier_domain.Ids.Plant_ref_id)
module Reference = Cases (Herbier_domain.Ids.Reference_id)

(* Plant_tag_id.of_key: the vectors are Python's uuid.uuid5 under the
   Herbier namespace b85c6db9-9479-4fb1-af57-3ff6ad665b62,
   not values computed by the function under test. *)
module Key = struct
  module Ids = Herbier_domain.Ids

  let plant s =
    match Ids.Plant_id.of_string s with
    | Some x -> x
    | None -> Alcotest.failf "Plant_id.of_string %S gave None" s

  let tag s =
    match Ids.Tag_id.of_string s with
    | Some x -> x
    | None -> Alcotest.failf "Tag_id.of_string %S gave None" s

  let plant_a = "00000000-0000-4000-8000-00000000000a"
  let plant_b = "00000000-0000-4000-8000-00000000000b"
  let tag_c1 = "00000000-0000-4000-8000-0000000000c1"

  let key ~plant:p ~tag:t =
    Ids.Plant_tag_id.of_key ~plant:(plant p) ~tag:(tag t)

  let str ~plant ~tag = Ids.Plant_tag_id.to_string (key ~plant ~tag)

  let vectors () =
    Alcotest.(check string)
      "plant ...0a with tag ...c1 is the uuid5 vector"
      "643fde24-732d-5b5d-865c-8caca18b4fcb"
      (str ~plant:plant_a ~tag:tag_c1);
    Alcotest.(check string)
      "plant ...0b with tag ...c1 is the uuid5 vector"
      "a4c3cf73-7a45-5c95-b6fc-7c723c420ef6"
      (str ~plant:plant_b ~tag:tag_c1)

  let letter_case () =
    Alcotest.(check string)
      "uppercase inputs give the id of the lowercase ones"
      "643fde24-732d-5b5d-865c-8caca18b4fcb"
      (str
         ~plant:(String.uppercase_ascii plant_a)
         ~tag:(String.uppercase_ascii tag_c1))

  let deterministic () =
    Alcotest.(check string)
      "two calls with the same pair give the same id"
      (str ~plant:plant_a ~tag:tag_c1)
      (str ~plant:plant_a ~tag:tag_c1)

  let version_5 () =
    let s = str ~plant:plant_b ~tag:tag_c1 in
    Alcotest.(check char) "version nibble is 5" '5' s.[14];
    Alcotest.(check bool)
      (Printf.sprintf "variant nibble %C is one of 8 9 a b" s.[19])
      true
      (String.contains "89ab" s.[19])

  let swapped () =
    Alcotest.(check bool)
      "swapping the plant and tag uuids gives another id" false
      (String.equal
         (str ~plant:plant_a ~tag:tag_c1)
         (str ~plant:tag_c1 ~tag:plant_a))

  let distinct () =
    let plants =
      List.init 20 (Printf.sprintf "00000000-0000-4000-8000-%012x")
    in
    let tags = List.init 20 (Printf.sprintf "00000000-0000-4000-9000-%012x") in
    let ids =
      List.concat_map
        (fun p -> List.map (fun t -> str ~plant:p ~tag:t) tags)
        plants
    in
    Alcotest.(check int)
      "400 distinct pairs give 400 distinct ids" 400
      (List.length (List.sort_uniq String.compare ids))

  let tests =
    List.map
      (fun (fact, f) -> ("Plant_tag_id.of_key: " ^ fact, `Quick, f))
      [
        ("matches the uuid5 test vectors", vectors);
        ("ignores the letter case of its inputs", letter_case);
        ("is deterministic", deterministic);
        ("is a version 5 UUID", version_5);
        ("depends on the order of plant and tag", swapped);
        ("gives distinct ids to distinct pairs", distinct);
      ]
end

(* Reference_id.of_key / Plant_ref_id.of_key: same namespace and generator as
   Plant_tag_id.of_key, vectors from Python's uuid.uuid5(ns, name). *)
module Derived_key = struct
  module Ids = Herbier_domain.Ids

  let plant s =
    match Ids.Plant_id.of_string s with
    | Some x -> x
    | None -> Alcotest.failf "Plant_id.of_string %S gave None" s

  let plant_a = "00000000-0000-4000-8000-00000000000a"
  let plant_b = "00000000-0000-4000-8000-00000000000b"

  let reference_str ~plant:p ~source =
    Ids.Reference_id.to_string
      (Ids.Reference_id.of_key ~plant:(plant p) ~source)

  let plant_ref_str ~plant:p ~source =
    Ids.Plant_ref_id.to_string
      (Ids.Plant_ref_id.of_key ~plant:(plant p) ~source)

  let vectors () =
    Alcotest.(check string)
      "Reference_id.of_key plant ...0a source gbif is the uuid5 vector"
      "6dbeba6a-0c34-5e61-9d98-367c37ddeff8"
      (reference_str ~plant:plant_a ~source:"gbif");
    Alcotest.(check string)
      "Reference_id.of_key plant ...0a source wikipedia is the uuid5 vector"
      "516bce03-f23c-5e1c-b536-3331be61ba72"
      (reference_str ~plant:plant_a ~source:"wikipedia");
    Alcotest.(check string)
      "Reference_id.of_key plant ...0b source gbif is the uuid5 vector"
      "07aa50c5-90c9-583d-975d-317939e21bc8"
      (reference_str ~plant:plant_b ~source:"gbif");
    Alcotest.(check string)
      "Plant_ref_id.of_key plant ...0a source gbif is the uuid5 vector"
      "683c5eee-0829-53c9-be5e-a2ce094ef086"
      (plant_ref_str ~plant:plant_a ~source:"gbif");
    Alcotest.(check string)
      "Plant_ref_id.of_key plant ...0a source wikipedia is the uuid5 vector"
      "d5834cd6-3eb5-5d5e-af3e-cdd6b5d5fec6"
      (plant_ref_str ~plant:plant_a ~source:"wikipedia");
    Alcotest.(check string)
      "Plant_ref_id.of_key plant ...0b source gbif is the uuid5 vector"
      "2144c05e-bf9f-5c8a-9f54-f65b6abdc9c3"
      (plant_ref_str ~plant:plant_b ~source:"gbif")

  let deterministic () =
    Alcotest.(check string)
      "two calls with the same pair give the same Reference_id"
      (reference_str ~plant:plant_a ~source:"gbif")
      (reference_str ~plant:plant_a ~source:"gbif");
    Alcotest.(check string)
      "two calls with the same pair give the same Plant_ref_id"
      (plant_ref_str ~plant:plant_a ~source:"gbif")
      (plant_ref_str ~plant:plant_a ~source:"gbif")

  let version_5 () =
    List.iter
      (fun s ->
        Alcotest.(check char) (s ^ ": version nibble is 5") '5' s.[14];
        Alcotest.(check bool)
          (Printf.sprintf "%s: variant nibble %C is one of 8 9 a b" s s.[19])
          true
          (String.contains "89ab" s.[19]))
      [
        reference_str ~plant:plant_a ~source:"gbif";
        plant_ref_str ~plant:plant_a ~source:"gbif";
      ]

  let uppercase_plant_id_parses_the_same () =
    Alcotest.(check string)
      "an uppercase plant id string gives the same Reference_id"
      (reference_str ~plant:plant_a ~source:"gbif")
      (reference_str ~plant:(String.uppercase_ascii plant_a) ~source:"gbif");
    Alcotest.(check string)
      "an uppercase plant id string gives the same Plant_ref_id"
      (plant_ref_str ~plant:plant_a ~source:"gbif")
      (plant_ref_str ~plant:(String.uppercase_ascii plant_a) ~source:"gbif")

  let reference_and_plant_ref_differ () =
    Alcotest.(check bool)
      "Reference_id.of_key and Plant_ref_id.of_key of the same pair differ"
      false
      (String.equal
         (reference_str ~plant:plant_a ~source:"gbif")
         (plant_ref_str ~plant:plant_a ~source:"gbif"))

  let distinct_sources_differ () =
    Alcotest.(check bool)
      "distinct sources give distinct Reference_id" false
      (String.equal
         (reference_str ~plant:plant_a ~source:"gbif")
         (reference_str ~plant:plant_a ~source:"wikipedia"));
    Alcotest.(check bool)
      "distinct sources give distinct Plant_ref_id" false
      (String.equal
         (plant_ref_str ~plant:plant_a ~source:"gbif")
         (plant_ref_str ~plant:plant_a ~source:"wikipedia"))

  let tests =
    List.map
      (fun (fact, f) -> ("of_key: " ^ fact, `Quick, f))
      [
        ("matches the uuid5 test vectors", vectors);
        ("is deterministic", deterministic);
        ("is a version 5 UUID", version_5);
        ( "ignores the letter case of the plant id",
          uppercase_plant_id_parses_the_same );
        ( "Reference_id and Plant_ref_id of the same pair differ",
          reference_and_plant_ref_differ );
        ("gives distinct ids to distinct sources", distinct_sources_differ);
      ]
end

let tests =
  List.concat
    [
      Key.tests;
      Derived_key.tests;
      Plant.tests "Plant_id";
      Observation.tests "Observation_id";
      Photo.tests "Photo_id";
      Tag.tests "Tag_id";
      Plant_tag.tests "Plant_tag_id";
      Plant_ref.tests "Plant_ref_id";
      Reference.tests "Reference_id";
    ]
