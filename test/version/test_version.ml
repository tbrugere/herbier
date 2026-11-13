let git = Herbier_version.git
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

let () = Alcotest.run "version" [("version", version_tests)]
