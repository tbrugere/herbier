(* Text.non_blank: trimmed with String.trim's ASCII whitespace, None when
   nothing is left. *)

module Text = Herbier_domain.Text

let case name input expected =
  ( name,
    `Quick,
    fun () ->
      Alcotest.(check (option string))
        (Printf.sprintf "non_blank %S" input)
        expected (Text.non_blank input) )

let nbsp = "\xc2\xa0"

let tests =
  [
    case "empty" "" None;
    case "spaces only" "   " None;
    case "tab, newline, return, form feed" "\t\n\r\012" None;
    case "trimmed both sides" " a " (Some "a");
    case "inner spaces kept" "  a b  " (Some "a b");
    case "already trimmed" "a" (Some "a");
    case "a non-breaking space is not whitespace" nbsp (Some nbsp);
    case "non-breaking spaces around are kept"
      (nbsp ^ "a" ^ nbsp)
      (Some (nbsp ^ "a" ^ nbsp));
  ]

let same_email name a b expected =
  ( name,
    `Quick,
    fun () ->
      Alcotest.(check bool)
        (Printf.sprintf "same_email %S %S" a b)
        expected (Text.same_email a b) )

let same_email_tests =
  [
    same_email "identical" "a@x.fr" "a@x.fr" true;
    same_email "ASCII case ignored" "Anne@X.fr" "anne@x.FR" true;
    same_email "trimmed" "  a@x.fr\n" "a@x.fr" true;
    same_email "another address" "a@x.fr" "b@x.fr" false;
    same_email "both blank" "" " " true;
  ]
