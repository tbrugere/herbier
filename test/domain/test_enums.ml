(* The wire strings are pinned literally: they are the stored column values.
   Constructor order is pinned too, independently of to_string, so a swap of
   two wire strings cannot pass as a swap of two constructors. The Postgres
   lookup tables hold the same values in the same order: test_schema_dump.ml
   compares the rows the migrations insert with the to_string of [all]
   pinned here. *)

module Testable = Herbier_test_support.Testable
module Photo = Herbier_domain.Photo
module Reference = Herbier_domain.Reference

let cases (type a) name ~(all : a list) ~(to_string : a -> string)
    ~(of_string : string -> a option) ~(constructors : a list) ~expected =
  let value =
    Alcotest.testable (fun f x -> Format.pp_print_string f (to_string x)) ( = )
  in
  let length () =
    Alcotest.(check int)
      "all has one element per constructor" (List.length expected)
      (List.length all)
  in
  let distinct () =
    Alcotest.(check int)
      "all has no duplicate" (List.length all)
      (List.length (List.sort_uniq Stdlib.compare all))
  in
  let order () =
    Alcotest.(check (list value)) "all in declaration order" constructors all
  in
  let wire () =
    Alcotest.(check (list string))
      "to_string of all, in declaration order" expected (List.map to_string all)
  in
  let round_trip () =
    List.iter
      (fun x ->
        Alcotest.(check (option value))
          (Printf.sprintf "of_string %S gives it back" (to_string x))
          (Some x)
          (of_string (to_string x)))
      all
  in
  let of_expected () =
    List.iter2
      (fun s x ->
        Alcotest.(check (option value))
          (Printf.sprintf "of_string %S is the matching constructor" s)
          (Some x) (of_string s))
      expected all
  in
  let rejects () =
    let none what s =
      Alcotest.(check (option value)) (what ^ " is rejected") None (of_string s)
    in
    none "empty string" "";
    none "unknown" "unknown";
    List.iter
      (fun s ->
        none (Printf.sprintf "uppercase %S" s) (String.uppercase_ascii s);
        none (Printf.sprintf "%S with a leading space" s) (" " ^ s);
        none (Printf.sprintf "%S with a trailing space" s) (s ^ " "))
      expected
  in
  List.map
    (fun (fact, f) -> (name ^ ": " ^ fact, `Quick, f))
    [
      ("all lists every constructor", length);
      ("all has no duplicate", distinct);
      ("all is in declaration order", order);
      ("to_string gives the pinned wire strings", wire);
      ("of_string inverts to_string", round_trip);
      ("of_string of each wire string is its constructor", of_expected);
      ("of_string rejects any other string", rejects);
    ]

(* The JSON codecs that tables.ml passes to Postgrest.Col.custom: the wire
   string as a JSON string, checked against to_string, which [cases] pins. *)
let json_cases (type a) name ~(all : a list) ~(to_string : a -> string)
    ~(to_json : a -> Yojson.Safe.t) ~(of_json : Yojson.Safe.t -> a option) =
  let value =
    Alcotest.testable (fun f x -> Format.pp_print_string f (to_string x)) ( = )
  in
  let json = Testable.yojson in
  let wire () =
    List.iter
      (fun x ->
        Alcotest.(check json)
          (Printf.sprintf "to_json of %S" (to_string x))
          (`String (to_string x))
          (to_json x))
      all
  in
  let round_trip () =
    List.iter
      (fun x ->
        Alcotest.(check (option value))
          (Printf.sprintf "of_json (to_json %S) gives it back" (to_string x))
          (Some x)
          (of_json (to_json x)))
      all
  in
  let rejects () =
    let none what j =
      Alcotest.(check (option value)) (what ^ " is rejected") None (of_json j)
    in
    none "unknown string" (`String "unknown");
    none "null" `Null;
    none "int" (`Int 0);
    List.iter
      (fun x ->
        none
          (Printf.sprintf "list holding %S" (to_string x))
          (`List [to_json x]))
      all
  in
  List.map
    (fun (fact, f) -> (name ^ ": " ^ fact, `Quick, f))
    [
      ("to_json is the JSON string of to_string", wire);
      ("of_json inverts to_json", round_trip);
      ("of_json rejects any other JSON value", rejects);
    ]

(* [equal] against the index in [all]: true on the diagonal only. *)
let equal_cases (type a) name ~(all : a list) ~(to_string : a -> string)
    ~(equal : a -> a -> bool) =
  let diagonal () =
    List.iteri
      (fun i x ->
        List.iteri
          (fun j y ->
            Alcotest.(check bool)
              (Printf.sprintf "equal %s %s" (to_string x) (to_string y))
              (Int.equal i j) (equal x y))
          all)
      all
  in
  [(name ^ ": equal holds for the same constructor only", `Quick, diagonal)]

let tests =
  List.concat
    [
      equal_cases "Photo.Original_target" ~all:Photo.Original_target.all
        ~to_string:Photo.Original_target.to_string
        ~equal:Photo.Original_target.equal;
      equal_cases "Photo.Upload_state" ~all:Photo.Upload_state.all
        ~to_string:Photo.Upload_state.to_string ~equal:Photo.Upload_state.equal;
      equal_cases "Reference.Source" ~all:Reference.Source.all
        ~to_string:Reference.Source.to_string ~equal:Reference.Source.equal;
      equal_cases "Reference.Status" ~all:Reference.Status.all
        ~to_string:Reference.Status.to_string ~equal:Reference.Status.equal;
      json_cases "Photo.Original_target" ~all:Photo.Original_target.all
        ~to_string:Photo.Original_target.to_string
        ~to_json:Photo.Original_target.to_json
        ~of_json:Photo.Original_target.of_json;
      json_cases "Photo.Upload_state" ~all:Photo.Upload_state.all
        ~to_string:Photo.Upload_state.to_string
        ~to_json:Photo.Upload_state.to_json ~of_json:Photo.Upload_state.of_json;
      json_cases "Reference.Source" ~all:Reference.Source.all
        ~to_string:Reference.Source.to_string ~to_json:Reference.Source.to_json
        ~of_json:Reference.Source.of_json;
      json_cases "Reference.Status" ~all:Reference.Status.all
        ~to_string:Reference.Status.to_string ~to_json:Reference.Status.to_json
        ~of_json:Reference.Status.of_json;
      cases "Photo.Original_target" ~all:Photo.Original_target.all
        ~to_string:Photo.Original_target.to_string
        ~of_string:Photo.Original_target.of_string
        ~constructors:Photo.Original_target.[App_only; Drive]
        ~expected:["app_only"; "drive"];
      cases "Photo.Upload_state" ~all:Photo.Upload_state.all
        ~to_string:Photo.Upload_state.to_string
        ~of_string:Photo.Upload_state.of_string
        ~constructors:
          Photo.Upload_state.[Pending; Uploaded; Failed; Original_missing]
        ~expected:["pending"; "uploaded"; "failed"; "original_missing"];
      cases "Reference.Source" ~all:Reference.Source.all
        ~to_string:Reference.Source.to_string
        ~of_string:Reference.Source.of_string
        ~constructors:
          Reference.Source.
            [
              Gbif;
              Wikidata;
              Wikipedia;
              Powo;
              Ipni;
              Taxref;
              Tela;
              Eppo;
              Inat;
              Plantnet;
              Plantuse;
            ]
        ~expected:
          [
            "gbif";
            "wikidata";
            "wikipedia";
            "powo";
            "ipni";
            "taxref";
            "tela";
            "eppo";
            "inat";
            "plantnet";
            "plantuse";
          ];
      cases "Reference.Status" ~all:Reference.Status.all
        ~to_string:Reference.Status.to_string
        ~of_string:Reference.Status.of_string
        ~constructors:Reference.Status.[Complete; Partial; Missing; Failed]
        ~expected:["complete"; "partial"; "missing"; "failed"];
      cases "Reference.Organ" ~all:Reference.Organ.all
        ~to_string:Reference.Organ.to_string
        ~of_string:Reference.Organ.of_string
        ~constructors:Reference.Organ.[Flower; Leaf; Fruit; Habit]
        ~expected:["flower"; "leaf"; "fruit"; "habit"];
    ]
