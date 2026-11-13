let apostrophe = "’"

(* The contracted article and the rest of the name, when [name] starts with
   an article (ASCII, case-insensitive) followed by its separator. *)
let article name =
  let lower = String.lowercase_ascii name in
  let after prefix =
    match String.starts_with ~prefix lower with
    | false -> None
    | true -> (
        let len = String.length prefix in
        match String.trim (String.sub name len (String.length name - len)) with
        | "" -> None
        | rest -> Some rest)
  in
  List.find_map
    (fun (prefix, contracted) ->
      Option.map (fun rest -> contracted ^ rest) (after prefix))
    [
      ("le ", "Près du ");
      ("les ", "Près des ");
      ("la ", "Près de la ");
      ("l'", "Près de l" ^ apostrophe);
      ("l" ^ apostrophe, "Près de l" ^ apostrophe);
    ]

let vowels =
  String.split_on_char ' '
    "A E I O U Y a e i o u y À Â Ä É È Ê Ë Î Ï Ô Ö Ù Û Ü Œ Æ à â ä é è ê ë î ï \
     ô ö ù û ü œ æ"

let phrase name =
  match String.trim name with
  | "" -> None
  | name -> (
      match article name with
      | Some phrase -> Some phrase
      | None -> (
          match
            List.exists (fun prefix -> String.starts_with ~prefix name) vowels
          with
          | true -> Some ("Près d" ^ apostrophe ^ name)
          | false -> Some ("Près de " ^ name)))
