let yojson =
  Alcotest.testable
    (fun f j -> Format.pp_print_string f (Yojson.Safe.pretty_to_string j))
    Yojson.Safe.equal
