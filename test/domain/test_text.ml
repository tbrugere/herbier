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
