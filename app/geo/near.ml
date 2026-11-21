let apostrophe = "’"

(* How a preposition contracts with each article, and its form before a vowel
   and before anything else. *)
type preposition = {
  le : string;
  les : string;
  la : string;
  l : string;
  vowel : string;
  other : string;
}

let pres =
  {
    le = "Près du ";
    les = "Près des ";
    la = "Près de la ";
    l = "Près de l" ^ apostrophe;
    vowel = "Près d" ^ apostrophe;
    other = "Près de ";
  }

let a =
  {
    le = "Au ";
    les = "Aux ";
    la = "À la ";
    l = "À l" ^ apostrophe;
    vowel = "À ";
    other = "À ";
  }

(* The contracted article and the rest of the name, when [name] starts with
   an article (ASCII, case-insensitive) followed by its separator. *)
let article prep name =
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
      ("le ", prep.le);
      ("les ", prep.les);
      ("la ", prep.la);
      ("l'", prep.l);
      ("l" ^ apostrophe, prep.l);
    ]

let vowels =
  String.split_on_char ' '
    "A E I O U Y a e i o u y À Â Ä É È Ê Ë Î Ï Ô Ö Ù Û Ü Œ Æ à â ä é è ê ë î ï \
     ô ö ù û ü œ æ"

let with_preposition prep name =
  match String.trim name with
  | "" -> None
  | name -> (
      match article prep name with
      | Some phrase -> Some phrase
      | None -> (
          match
            List.exists (fun prefix -> String.starts_with ~prefix name) vowels
          with
          | true -> Some (prep.vowel ^ name)
          | false -> Some (prep.other ^ name)))

let phrase = with_preposition pres
let inside = with_preposition a
