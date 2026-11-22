type section = {level : int; title : string; body : string}
[@@deriving eq, show]

let lines text =
  List.map
    (fun l ->
      match String.ends_with ~suffix:"\r" l with
      | true -> String.sub l 0 (String.length l - 1)
      | false -> l)
    (String.split_on_char '\n' text)

let run_from s i c =
  let n = String.length s in
  let rec go j =
    match j < n && s.[j] = c with true -> go (j + 1) | false -> j
  in
  go i - i

let run_to s c =
  let rec go j =
    match j >= 0 && s.[j] = c with true -> go (j - 1) | false -> j
  in
  String.length s - 1 - go (String.length s - 1)

(* The runs are maximal, so with a title left between them its first and
   last characters are not '='. *)
let heading line =
  let t = String.trim line in
  let n = String.length t in
  let l = run_from t 0 '=' and r = run_to t '=' in
  match l = r && l >= 2 && l <= 6 && n > 2 * l with
  | true -> Some (l, String.trim (String.sub t l (n - (2 * l))))
  | false -> None

let sections text =
  let close (level, title, body) =
    {level; title; body = String.concat "\n" (List.rev body)}
  in
  let rec go lead current acc = function
    | [] -> (
        match current with
        | None -> (String.concat "\n" (List.rev lead), List.rev acc)
        | Some c ->
            (String.concat "\n" (List.rev lead), List.rev (close c :: acc)))
    | line :: rest -> (
        match (heading line, current) with
        | Some (level, title), None ->
            go lead (Some (level, title, [])) acc rest
        | Some (level, title), Some c ->
            go lead (Some (level, title, [])) (close c :: acc) rest
        | None, None -> go (line :: lead) None acc rest
        | None, Some (level, title, body) ->
            go lead (Some (level, title, line :: body)) acc rest)
  in
  go [] None [] (lines text)

let code_points s =
  String.fold_left
    (fun n c ->
      match Char.code c land 0xc0 = 0x80 with true -> n | false -> n + 1)
    0 s

let at s i sub =
  let m = String.length sub in
  let rec same k = k >= m || (s.[i + k] = sub.[k] && same (k + 1)) in
  i >= 0 && i + m <= String.length s && same 0

let find s sub i =
  let n = String.length s and m = String.length sub in
  let rec go j =
    match j + m <= n with
    | false -> None
    | true -> ( match at s j sub with true -> Some j | false -> go (j + 1))
  in
  go i

(* The index just after the "close" matching the "open" at [i], nested pairs
   counted; [None] when unclosed. *)
let matching s ~opening ~closing i =
  let n = String.length s in
  let rec go j depth =
    match () with
    | () when j >= n -> None
    | () when at s j opening -> go (j + String.length opening) (depth + 1)
    | () when at s j closing -> (
        let j = j + String.length closing in
        match depth - 1 with 0 -> Some j | d -> go j d)
    | () -> go (j + 1) depth
  in
  go i 0

(* One left-to-right pass: [step b i] appends what the text from [i] gives
   and returns where to go on (always past [i]). *)
let scan s step =
  let b = Buffer.create (String.length s) in
  let n = String.length s in
  let rec go i = match i < n with true -> go (step b i) | false -> () in
  go 0;
  Buffer.contents b

let rest b s i =
  Buffer.add_substring b s i (String.length s - i);
  String.length s

let char b s i =
  Buffer.add_char b s.[i];
  i + 1

let ref_open s i =
  at s i "<ref"
  && i + 4 < String.length s
  && match s.[i + 4] with ' ' | '>' | '/' -> true | _ -> false

(* An unclosed comment hides the rest, as MediaWiki renders it. *)
let refs_and_comments s =
  scan s (fun b i ->
      match () with
      | () when at s i "<!--" -> (
          match find s "-->" (i + 4) with
          | Some j -> j + 3
          | None -> String.length s)
      | () when ref_open s i -> (
          match find s ">" (i + 4) with
          | None -> rest b s i
          | Some j when s.[j - 1] = '/' -> j + 1
          | Some j -> (
              match find s "</ref>" (j + 1) with
              | Some k -> k + 6
              | None -> j + 1))
      | () -> char b s i)

let templates_removed s =
  scan s (fun b i ->
      match at s i "{{" with
      | false -> char b s i
      | true -> (
          match matching s ~opening:"{{" ~closing:"}}" i with
          | Some j -> j
          | None -> rest b s i))

let hidden_namespaces = ["file"; "fichier"; "image"; "category"; "catégorie"]

let namespaced target =
  match String.index_opt target ':' with
  | None -> false
  | Some k ->
      List.mem
        (String.lowercase_ascii (String.trim (String.sub target 0 k)))
        hidden_namespaces

let rec links s =
  scan s (fun b i ->
      match at s i "[[" with
      | false -> char b s i
      | true -> (
          match matching s ~opening:"[[" ~closing:"]]" i with
          | None -> rest b s i
          | Some j ->
              let inner = String.sub s (i + 2) (j - i - 4) in
              (match (namespaced inner, String.index_opt inner '|') with
              | true, _ -> ()
              | false, Some k ->
                  Buffer.add_string b
                    (links
                       (String.sub inner (k + 1) (String.length inner - k - 1)))
              | false, None -> Buffer.add_string b inner);
              j))

let external_links s =
  scan s (fun b i ->
      match
        s.[i] = '[' && (at s (i + 1) "http://" || at s (i + 1) "https://")
      with
      | false -> char b s i
      | true -> (
          match String.index_from_opt s i ']' with
          | None -> char b s i
          | Some j ->
              let inner = String.sub s (i + 1) (j - i - 1) in
              (match String.index_opt inner ' ' with
              | Some k ->
                  Buffer.add_string b
                    (String.sub inner (k + 1) (String.length inner - k - 1))
              | None -> ());
              j + 1))

let quotes s =
  scan s (fun b i ->
      match run_from s i '\'' with n when n >= 2 -> i + n | _ -> char b s i)

let tag_start s i =
  s.[i] = '<'
  && i + 1 < String.length s
  &&
  match s.[i + 1] with
  | 'a' .. 'z' | 'A' .. 'Z' | '/' | '!' -> true
  | _ -> false

let tags s =
  scan s (fun b i ->
      match tag_start s i with
      | false -> char b s i
      | true -> (
          match String.index_from_opt s i '>' with
          | Some j -> j + 1
          | None -> char b s i))

let entity_list =
  [
    ("&nbsp;", " ");
    ("&amp;", "&");
    ("&lt;", "<");
    ("&gt;", ">");
    ("&quot;", "\"");
    ("&#39;", "'");
  ]

let entities s =
  scan s (fun b i ->
      match List.find_opt (fun (e, _) -> at s i e) entity_list with
      | Some (e, v) ->
          Buffer.add_string b v;
          i + String.length e
      | None -> char b s i)

let is_space = function ' ' | '\t' | '\n' | '\r' -> true | _ -> false

let collapse s =
  String.trim
    (scan s (fun b i ->
         match is_space s.[i] with
         | false -> char b s i
         | true ->
             Buffer.add_char b ' ';
             let rec skip j =
               match j < String.length s && is_space s.[j] with
               | true -> skip (j + 1)
               | false -> j
             in
             skip i))

let strip s =
  s
  |> refs_and_comments
  |> templates_removed
  |> links
  |> external_links
  |> quotes
  |> tags
  |> entities
  |> collapse

(* The pieces of a template's inside, split on the '|' outside nested
   templates and links. *)
let pieces inner =
  let n = String.length inner in
  let rec go i start depth acc =
    match () with
    | () when i >= n -> List.rev (String.sub inner start (n - start) :: acc)
    | () when at inner i "{{" || at inner i "[[" ->
        go (i + 2) start (depth + 1) acc
    | () when (at inner i "}}" || at inner i "]]") && depth > 0 ->
        go (i + 2) start (depth - 1) acc
    | () when inner.[i] = '|' && depth = 0 ->
        go (i + 1) (i + 1) depth (String.sub inner start (i - start) :: acc)
    | () -> go (i + 1) start depth acc
  in
  go 0 0 0 []

let capitalised s = match s with "" -> s | _ -> String.capitalize_ascii s
let same_name a b = String.equal (capitalised (String.trim a)) (capitalised b)

let named_parameters pieces =
  List.filter_map
    (fun piece ->
      Option.map
        (fun k ->
          ( String.trim (String.sub piece 0 k),
            String.trim (String.sub piece (k + 1) (String.length piece - k - 1))
          ))
        (String.index_opt piece '='))
    pieces

let templates ~name s =
  let name = String.trim name in
  let rec go i acc =
    match find s "{{" i with
    | None -> List.rev acc
    | Some i -> (
        match matching s ~opening:"{{" ~closing:"}}" i with
        | None -> go (i + 2) acc
        | Some j -> (
            match pieces (String.sub s (i + 2) (j - i - 4)) with
            | first :: params when same_name first name ->
                go j (named_parameters params :: acc)
            | _ :: _ | [] -> go (i + 2) acc))
  in
  go 0 []

let bullets text =
  List.filter_map
    (fun line ->
      let t = String.trim line in
      match run_from t 0 '*' with
      | 0 -> None
      | stars -> (
          match strip (String.sub t stars (String.length t - stars)) with
          | "" -> None
          | b -> Some b))
    (lines text)

let blank c = c = ' ' || c = '\n'

let initial s i =
  i >= 1 && s.[i - 1] >= 'A' && s.[i - 1] <= 'Z' && (i = 1 || blank s.[i - 2])

let first_sentences ~n text =
  let s = String.trim text in
  let len = String.length s in
  let rec go i count =
    match i >= len with
    | true -> s
    | false -> (
        match s.[i] with
        | ('.' | '!' | '?') as c
          when (i + 1 = len || blank s.[i + 1]) && not (c = '.' && initial s i)
          -> (
            match count + 1 >= n with
            | true -> String.sub s 0 (i + 1)
            | false -> go (i + 1) (count + 1))
        | _ -> go (i + 1) count)
  in
  match n <= 0 with true -> "" | false -> go 0 0
