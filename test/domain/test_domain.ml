let git = Herbier_domain.Version.git
let is_whitespace = function ' ' | '\t' | '\n' | '\r' -> true | _ -> false

let version_tests =
  [
    ( "git is non-empty",
      `Quick,
      fun () -> Alcotest.(check (neg string)) "Version.git" "" git );
    ( "git is a git describe output, not the fallback",
      `Quick,
      fun () -> Alcotest.(check (neg string)) "Version.git" "unknown" git );
    ( "git contains no whitespace or newline",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "Version.git without whitespace"
          (String.concat "" (String.split_on_char ' ' (String.trim git)))
          git;
        Alcotest.(check bool)
          "no whitespace character in Version.git" false
          (String.exists is_whitespace git) );
  ]

let () =
  Alcotest.run "domain"
    [
      ("version", version_tests);
      ("ids", Test_ids.tests);
      ("enums", Test_enums.tests);
      ("photo", Test_photo.tests);
      ("places", Test_places.tests);
      ("link", Test_link.tests);
      ("schema dump", Test_schema_dump.tests);
    ]
