(* Compile-time property, not tested here: the [t] types are pairwise
   distinct and abstract (each module is sealed with [: S] in ids.mli), so a
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
      ]
end

module Plant = Cases (Herbier_domain.Ids.Plant_id)
module Observation = Cases (Herbier_domain.Ids.Observation_id)
module Photo = Cases (Herbier_domain.Ids.Photo_id)
module Tag = Cases (Herbier_domain.Ids.Tag_id)
module Plant_tag = Cases (Herbier_domain.Ids.Plant_tag_id)
module Plant_ref = Cases (Herbier_domain.Ids.Plant_ref_id)
module Reference = Cases (Herbier_domain.Ids.Reference_id)

let tests =
  List.concat
    [
      Plant.tests "Plant_id";
      Observation.tests "Observation_id";
      Photo.tests "Photo_id";
      Tag.tests "Tag_id";
      Plant_tag.tests "Plant_tag_id";
      Plant_ref.tests "Plant_ref_id";
      Reference.tests "Reference_id";
    ]
