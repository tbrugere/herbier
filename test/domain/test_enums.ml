(* The wire strings are pinned literally: they are the stored column values.
   Constructor order is pinned too, independently of to_string, so a swap of
   two wire strings cannot pass as a swap of two constructors. *)

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

let tests =
  List.concat
    [
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
