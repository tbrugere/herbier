(* A byte of a term: ASCII letters and digits, and the bytes of UTF-8
   sequences. Non-ASCII punctuation is turned into spaces first ([blank]). *)
let is_term_byte = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '\x80' .. '\xff' -> true
  | _ -> false

(* Replaces by spaces the UTF-8 sequences of the separators a phone keyboard or
   a paste brings: U+0080–U+00BF but ª µ º (NBSP, « », ·, ¿, …) and
   U+2000–U+207F (’ ‘ “ ” … – —, the narrow NBSP of French typography,
   superscripts). *)
let blank text =
  let n = String.length text in
  let b = Bytes.of_string text in
  let space i len = Bytes.fill b i len ' ' in
  let rec go i =
    match i < n with
    | false -> Bytes.to_string b
    | true -> (
        match text.[i] with
        | '\xc2' when i + 1 < n -> (
            match text.[i + 1] with
            | '\xaa' | '\xb5' | '\xba' -> go (i + 2)
            | '\x80' .. '\xbf' ->
                space i 2;
                go (i + 2)
            | _ -> go (i + 1))
        | '\xe2' when i + 2 < n -> (
            match (text.[i + 1], text.[i + 2]) with
            | ('\x80' | '\x81'), '\x80' .. '\xbf' ->
                space i 3;
                go (i + 3)
            | _ -> go (i + 1))
        | _ -> go (i + 1))
  in
  go 0

(* A term worth sending: it has an ASCII letter or digit, or the lead byte of a
   two-byte letter (U+00C0–U+07FF) or of a three-byte sequence outside
   U+2000–U+2FFF (punctuation, arrows, symbols). Terms of emoji, symbols or
   stray continuation bytes would be phrases of no token, which match
   nothing. *)
let has_letter term =
  String.exists
    (function
      | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> true
      | '\xc3' .. '\xdf' | '\xe0' .. '\xe1' | '\xe3' .. '\xef' -> true
      | _ -> false)
    term

let terms text =
  String.split_on_char ' '
    (String.map
       (fun c -> match is_term_byte c with true -> c | false -> ' ')
       (blank text))
  |> List.filter has_letter

(* The base letter of a Latin-1 letter U+00C0–U+00FF, given the second byte of
   its UTF-8 encoding (the first is 0xC3). Capitals are 0x20 below their small
   letter in this block, except ß (0x9F), which has none. *)
let latin1_base = function
  | '\x9f' -> None
  | second -> (
      match Char.chr (Char.code second lor 0x20) with
      | '\xa0' .. '\xa5' -> Some 'a'
      | '\xa7' -> Some 'c'
      | '\xa8' .. '\xab' -> Some 'e'
      | '\xac' .. '\xaf' -> Some 'i'
      | '\xb1' -> Some 'n'
      | '\xb2' .. '\xb6' -> Some 'o'
      | '\xb9' .. '\xbc' -> Some 'u'
      | '\xbd' | '\xbf' -> Some 'y'
      | _ -> None)

let fold term =
  let n = String.length term in
  let b = Buffer.create n in
  let rec go i =
    match i < n with
    | false -> Buffer.contents b
    | true -> (
        match term.[i] with
        | ('\xc3' | '\xc5') as first when i + 1 < n -> (
            let second = term.[i + 1] in
            let base =
              match (first, second) with
              | '\xc3', _ -> latin1_base second
              | '\xc5', '\xb8' -> Some 'y' (* Ÿ, U+0178 *)
              | _ -> None
            in
            match base with
            | Some c ->
                Buffer.add_char b c;
                go (i + 2)
            | None ->
                Buffer.add_char b first;
                go (i + 1))
        | c ->
            Buffer.add_char b (Char.lowercase_ascii c);
            go (i + 1))
  in
  go 0

(* Strips a French or Latin ending so that "digitale" and "digitalis" meet at
   "digital" (architecture §3): prefix matching alone cannot get there. *)
let strip_ending term =
  let n = String.length term in
  let strippable e =
    String.ends_with ~suffix:e term && n - String.length e >= 4
  in
  let first endings = List.find_opt strippable endings in
  match first ["es"; "is"; "us"; "um"; "ae"] with
  | Some e -> String.sub term 0 (n - String.length e)
  | None -> (
      match first ["e"; "s"; "a"; "i"] with
      | Some e -> String.sub term 0 (n - String.length e)
      | None -> term)

let match_expression text =
  match terms text with
  | [] -> None
  | terms ->
      Some
        (String.concat " "
           (List.map (fun t -> "\"" ^ strip_ending (fold t) ^ "\"*") terms))

let matches ~query text =
  match terms query with
  | [] -> false
  | query_terms ->
      let words = List.map fold (terms text) in
      List.for_all
        (fun q ->
          let prefix = strip_ending (fold q) in
          List.exists (String.starts_with ~prefix) words)
        query_terms

let matching expression =
  Plants.query
    ("select p.* from plants p where p.deleted_at is null and p.id in (select \
      plant_id from plant_search where plant_search match ?) order by "
    ^ Plants.order_by)
    [Codec.Text expression]

let plants text = Option.map matching (match_expression text)

let plants_by_name text =
  Option.map
    (fun expression -> matching ("{names tags} : (" ^ expression ^ ")"))
    (match_expression text)

let plants_or_all text = Option.value (plants text) ~default:Plants.list
