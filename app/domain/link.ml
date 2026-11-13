type t =
  | Gbif of int
  | Plantnet of string
  | Plantnet_observation of string
  | Plantuse of string
  | Wikipedia of {lang : string; title : string}
  | Inpn of int
  | Tela of int
  | Powo of string
  | Inat of int
  | Text of string
[@@deriving eq]

let to_string = function
  | Gbif k -> Printf.sprintf "gbif %d" k
  | Plantnet name -> Printf.sprintf "plantnet %S" name
  | Plantnet_observation id -> Printf.sprintf "plantnet observation %S" id
  | Plantuse name -> Printf.sprintf "plantuse %S" name
  | Wikipedia {lang; title} -> Printf.sprintf "wikipedia %s %S" lang title
  | Inpn n -> Printf.sprintf "inpn %d" n
  | Tela n -> Printf.sprintf "tela %d" n
  | Powo id -> Printf.sprintf "powo %S" id
  | Inat n -> Printf.sprintf "inat %d" n
  | Text s -> Printf.sprintf "text %S" s

let is_space = function ' ' | '\t' | '\n' | '\r' | '\012' -> true | _ -> false

let has_at ~sub s i =
  let n = String.length sub in
  i + n <= String.length s && String.sub s i n = sub

let starts_with_ci ~prefix s i =
  let n = String.length prefix in
  i + n <= String.length s && String.lowercase_ascii (String.sub s i n) = prefix

let url_start s from =
  let rec go i =
    match () with
    | () when i >= String.length s -> None
    | () when starts_with_ci ~prefix:"http://" s i -> Some i
    | () when starts_with_ci ~prefix:"https://" s i -> Some i
    | () -> go (i + 1)
  in
  go from

(* A no-break space (C2 A0) or narrow no-break space (E2 80 AF) ends a URL
   like a space: French typography puts them inside « » and before ! ? : ;,
   and a real URL percent-encodes them. "](" ends the text of a Markdown link
   whose text is itself a URL. *)
let ends_url s j =
  is_space s.[j]
  || has_at ~sub:"\xc2\xa0" s j
  || has_at ~sub:"\xe2\x80\xaf" s j
  || has_at ~sub:"](" s j

let count c s =
  String.fold_left
    (fun n x -> match x = c with true -> n + 1 | false -> n)
    0 s

(* », ” and ’ as UTF-8. *)
let closing_quotes = ["\xc2\xbb"; "\xe2\x80\x9d"; "\xe2\x80\x99"]

(* Punctuation that ends a sentence around a URL rather than belonging to it.
   A closing bracket goes only when it closes nothing inside the URL:
   "wiki/Ail_(plante)" keeps its ")". Opening brackets are never stripped, so
   their counts hold while the closing counts follow the shrinking prefix. *)
let strip_trailing u =
  let opening_parens = count '(' u and opening_brackets = count '[' u in
  let rec go n ~parens ~brackets =
    match
      List.find_opt
        (fun q ->
          let k = String.length q in
          n >= k && has_at ~sub:q u (n - k))
        closing_quotes
    with
    | Some q -> go (n - String.length q) ~parens ~brackets
    | None -> (
        match n with
        | 0 -> 0
        | _ -> (
            match u.[n - 1] with
            | '.' | ',' | ';' | ':' | '!' | '?' | '>' | '"' | '\'' ->
                go (n - 1) ~parens ~brackets
            | ')' when parens > opening_parens ->
                go (n - 1) ~parens:(parens - 1) ~brackets
            | ']' when brackets > opening_brackets ->
                go (n - 1) ~parens ~brackets:(brackets - 1)
            | _ -> n))
  in
  String.sub u 0
    (go (String.length u) ~parens:(count ')' u) ~brackets:(count ']' u))

type scanned = {url : string; stripped : string; next : int}

(* [stripped] is what [strip_trailing] removed; scanning resumes at [next]. *)
let scan_url s from =
  Option.map
    (fun i ->
      let rec stop j =
        match () with
        | () when j >= String.length s || ends_url s j -> j
        | () -> stop (j + 1)
      in
      let next = stop i in
      let raw = String.sub s i (next - i) in
      let url = strip_trailing raw in
      let n = String.length url in
      {url; stripped = String.sub raw n (String.length raw - n); next})
    (url_start s from)

let leading_dots s =
  let rec go i =
    match i < String.length s && s.[i] = '.' with
    | true -> go (i + 1)
    | false -> String.sub s 0 i
  in
  go 0

let hex_value = function
  | '0' .. '9' as c -> Some (Char.code c - Char.code '0')
  | 'a' .. 'f' as c -> Some (Char.code c - Char.code 'a' + 10)
  | 'A' .. 'F' as c -> Some (Char.code c - Char.code 'A' + 10)
  | _ -> None

(* A malformed escape is kept as written. *)
let percent_decode s =
  let n = String.length s in
  let b = Buffer.create n in
  let rec go i =
    match () with
    | () when i >= n -> Buffer.contents b
    | () when s.[i] = '%' && i + 2 < n -> (
        match (hex_value s.[i + 1], hex_value s.[i + 2]) with
        | Some h, Some l ->
            Buffer.add_char b (Char.chr ((h * 16) + l));
            go (i + 3)
        | _ ->
            Buffer.add_char b '%';
            go (i + 1))
    | () ->
        Buffer.add_char b s.[i];
        go (i + 1)
  in
  go 0

(* A segment that decodes to invalid UTF-8 (a Latin-1 "%E9") is kept as
   written. *)
let decode_segment seg =
  let decoded = percent_decode seg in
  match String.is_valid_utf_8 decoded with true -> decoded | false -> seg

let cut_at chars s =
  let stop =
    List.fold_left
      (fun acc c ->
        match String.index_opt s c with Some i when i < acc -> i | _ -> acc)
      (String.length s) chars
  in
  String.sub s 0 stop

type url = {host : string; path : string list}

let is_host_char = function
  | 'a' .. 'z' | '0' .. '9' | '.' | '-' -> true
  | _ -> false

(* A host with any other byte (["%"], ["\\"], ...) is one a browser would read
   differently, so it matches no pattern. *)
let host_of_authority authority =
  let after_at =
    match String.rindex_opt authority '@' with
    | Some i -> String.sub authority (i + 1) (String.length authority - i - 1)
    | None -> authority
  in
  let host = cut_at [':'] after_at in
  let host =
    match String.length host with
    | n when n > 0 && host.[n - 1] = '.' -> String.sub host 0 (n - 1)
    | _ -> host
  in
  let host = String.lowercase_ascii host in
  match host <> "" && String.for_all is_host_char host with
  | true -> Some host
  | false -> None

let scheme_length u =
  match () with
  | () when starts_with_ci ~prefix:"http://" u 0 -> Some 7
  | () when starts_with_ci ~prefix:"https://" u 0 -> Some 8
  | () -> None

(* A backslash is a path separator in an http(s) URL, as in a browser:
   "evil.com\\@identify.plantnet.org" is the host evil.com. *)
let parse_url u =
  Option.bind (scheme_length u) (fun k ->
      let rest = String.sub u k (String.length u - k) in
      let rest =
        cut_at ['?'; '#'] rest |> String.map (function '\\' -> '/' | c -> c)
      in
      let authority, path =
        match String.index_opt rest '/' with
        | Some i ->
            (String.sub rest 0 i, String.sub rest i (String.length rest - i))
        | None -> (rest, "")
      in
      let segments =
        String.split_on_char '/' path
        |> List.filter (fun seg -> seg <> "")
        |> List.map decode_segment
      in
      Option.map
        (fun host -> {host; path = segments})
        (host_of_authority authority))

(* [int_of_string_opt] alone would take "-3", "0x1F" and "1_000". *)
let positive_int s =
  match String.for_all (function '0' .. '9' -> true | _ -> false) s with
  | true -> (
      match int_of_string_opt s with Some n when n > 0 -> Some n | _ -> None)
  | false -> None

(* "12345-Digitalis-purpurea" → 12345 *)
let leading_int s =
  positive_int
    (match String.index_opt s '-' with Some i -> String.sub s 0 i | None -> s)

let strip_prefix ~prefix s =
  match String.starts_with ~prefix s with
  | true ->
      Some
        (String.sub s (String.length prefix)
           (String.length s - String.length prefix))
  | false -> None

let underscores_to_spaces = String.map (function '_' -> ' ' | c -> c)

let rec after_segment name = function
  | seg :: next :: _ when seg = name -> Some next
  | _ :: rest -> after_segment name rest
  | [] -> None

let gbif = function
  | "species" :: key :: _ | _ :: "species" :: key :: _ ->
      Option.map (fun k -> Gbif k) (positive_int key)
  | _ -> None

(* A decoded "%20" or "_" leaves nothing to search for. *)
let non_blank s =
  match String.trim s with "" -> None | trimmed -> Some trimmed

let plantnet path =
  match
    ( Option.bind (after_segment "species" path) non_blank,
      Option.bind (after_segment "observations" path) non_blank )
  with
  | Some name, _ -> Some (Plantnet name)
  | None, Some id -> Some (Plantnet_observation id)
  | None, None -> None

(* "/w/index.php" and namespaced pages ("Catégorie:…", "Spécial:…") are not
   species pages. *)
let plantuse = function
  | [lang; page] when lang <> "w" && not (String.contains page ':') ->
      Option.map
        (fun name -> Plantuse name)
        (non_blank (underscores_to_spaces page))
  | _ -> None

(* A title may hold a literal "/" ("AC/DC"), so it is every segment after
   "wiki". *)
let wikipedia lang = function
  | "wiki" :: (_ :: _ as title) ->
      Option.map
        (fun title -> Wikipedia {lang; title})
        (non_blank (underscores_to_spaces (String.concat "/" title)))
  | _ -> None

let inpn = function
  | "espece" :: "cd_nom" :: n :: _ | "explorer" :: "especes" :: n :: _ ->
      Option.map (fun n -> Inpn n) (positive_int n)
  | _ -> None

let tela = function
  | seg :: _ ->
      Option.bind (strip_prefix ~prefix:"bdtfx-nn-" seg) (fun rest ->
          Option.map (fun n -> Tela n) (leading_int rest))
  | [] -> None

let powo = function
  | "taxon" :: id :: _ -> Option.map (fun id -> Powo id) (non_blank id)
  | _ -> None

let inat = function
  | "taxa" :: id :: _ -> Option.map (fun n -> Inat n) (leading_int id)
  | _ -> None

let without_www host =
  Option.value ~default:host (strip_prefix ~prefix:"www." host)

let valid_wikipedia_lang lang =
  let n = String.length lang in
  n >= 1
  && n <= 12
  && (match lang.[0] with 'a' .. 'z' -> true | _ -> false)
  && String.for_all (function 'a' .. 'z' | '-' -> true | _ -> false) lang
  && lang <> "www"

(* "fr.wikipedia.org" | "fr.m.wikipedia.org" → Some "fr" *)
let wikipedia_lang host =
  match String.split_on_char '.' host with
  | ([lang; "wikipedia"; "org"] | [lang; "m"; "wikipedia"; "org"])
    when valid_wikipedia_lang lang ->
      Some lang
  | _ -> None

let of_url {host; path} =
  match (without_www host, wikipedia_lang host) with
  | _, Some lang -> wikipedia lang path
  | ("gbif.org" | "m.gbif.org"), None -> gbif path
  | "identify.plantnet.org", None -> plantnet path
  | ( ( "plantuse.plantnet.org" | "uses.plantnet.org"
      | "uses.plantnet-project.org" ),
      None ) ->
      plantuse path
  | "inpn.mnhn.fr", None -> inpn path
  | "tela-botanica.org", None -> tela path
  | "powo.science.kew.org", None -> powo path
  | ("inaturalist.org" | "m.inaturalist.org"), None -> inat path
  | _, None -> None

let classify_url url = Option.bind (parse_url url) of_url

let classify_scanned {url; stripped; _} =
  match classify_url url with
  (* An authorship often ends in an abbreviation ("L."), so dots ending a
     Pl@ntNet species URL belong to the name. The cost: a sentence-final dot
     after a name without authorship stays on it ("Quercus robur."). *)
  | Some (Plantnet _ as link) -> (
      match classify_url (url ^ leading_dots stripped) with
      | Some (Plantnet _ as with_dots) -> Some with_dots
      | Some _ | None -> Some link)
  | found -> found

let classify input =
  let text = String.trim input in
  let rec go from =
    match scan_url text from with
    | None -> Text text
    | Some scanned -> (
        match classify_scanned scanned with
        | Some link -> link
        | None -> go scanned.next)
  in
  go 0

(* Dashes, a colon, a bar, a middle dot or a comma often sit between a name
   and its URL ("Digitalis purpurea L. – https://…"). *)
let separators =
  ["-"; "\xe2\x80\x93"; "\xe2\x80\x94"; ":"; "|"; "\xc2\xb7"; ","]

let rec trim_separators s =
  let s = String.trim s in
  match
    List.find_opt
      (fun sep ->
        String.starts_with ~prefix:sep s || String.ends_with ~suffix:sep s)
      separators
  with
  | None -> s
  | Some sep ->
      let n = String.length sep in
      let s =
        match String.starts_with ~prefix:sep s with
        | true -> String.sub s n (String.length s - n)
        | false -> s
      in
      let s =
        match String.ends_with ~suffix:sep s with
        | true -> String.sub s 0 (String.length s - n)
        | false -> s
      in
      trim_separators s

let without_urls input =
  let b = Buffer.create (String.length input) in
  let rec go from =
    match scan_url input from with
    | None -> Buffer.add_substring b input from (String.length input - from)
    | Some {url; stripped; next} ->
        let start = next - String.length url - String.length stripped in
        Buffer.add_substring b input from (start - from);
        Buffer.add_char b ' ';
        go next
  in
  go 0;
  String.split_on_char ' '
    (String.map
       (fun c -> match is_space c with true -> ' ' | false -> c)
       (Buffer.contents b))
  |> List.filter (fun w -> w <> "")
  |> String.concat " "
  |> trim_separators
