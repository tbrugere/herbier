module Source = Herbier_domain.Reference.Source
module Wikipedia = Sources.Wikipedia

let contains ~sub s =
  let n = String.length sub and m = String.length s in
  let rec at i = i + n <= m && (String.sub s i n = sub || at (i + 1)) in
  at 0

(* String.lowercase_ascii leaves accented capitals alone: the Latin-1 ones
   (UTF-8 C3 80 to C3 9E, but the sign at C3 97) are folded too, so
   "VÉNÉNEUX" matches. *)
let lowercase s =
  String.mapi
    (fun i c ->
      match
        i > 0 && s.[i - 1] = '\xc3' && c >= '\x80' && c <= '\x9e' && c <> '\x97'
      with
      | true -> Char.chr (Char.code c + 0x20)
      | false -> Char.lowercase_ascii c)
    s

let toxic s =
  let s = lowercase s in
  List.exists
    (fun sub -> contains ~sub s)
    ["toxique"; "toxic"; "vénéneu"; "poison"]

let blank c = c = ' ' || c = '\n'

(* A dot after a lone capital is an author's initial ("Digitalis purpurea
   L. est"), not the end of a sentence. *)
let initial s i =
  i >= 1 && s.[i - 1] >= 'A' && s.[i - 1] <= 'Z' && (i = 1 || blank s.[i - 2])

let sentences s =
  let n = String.length s in
  let rec skip i =
    match i < n && blank s.[i] with true -> skip (i + 1) | false -> i
  in
  let rec go start i acc =
    match i >= n with
    | true -> List.rev (String.sub s start (n - start) :: acc)
    | false -> (
        let cut =
          match s.[i] with
          | '\n' -> Some i
          | '.' | '!' | '?' -> (
              match
                i + 1 < n && blank s.[i + 1] && not (s.[i] = '.' && initial s i)
              with
              | true -> Some (i + 1)
              | false -> None)
          | _ -> None
        in
        match cut with
        | Some stop ->
            let next = skip stop in
            go next next (String.sub s start (stop - start) :: acc)
        | None -> go start (i + 1) acc)
  in
  go 0 0 []

let toxicity (summary : Wikipedia.t) =
  match summary.kind with
  | Disambiguation | Other _ -> None
  | Standard -> (
      let from_extract =
        Option.bind summary.extract (fun e -> List.find_opt toxic (sentences e))
      in
      match from_extract with
      | Some s -> Some (Cited.v [Source.Wikipedia] (String.trim s))
      | None -> (
          match summary.description with
          | Some d when toxic d ->
              Some (Cited.v [Source.Wikipedia] (String.trim d))
          | Some _ | None -> None))
