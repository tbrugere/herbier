module Text = Herbier_domain.Text

let cap = 4096

(* Cut at a character boundary: a UTF-8 continuation byte is 10xxxxxx. *)
let capped s =
  let rec boundary i =
    match i > 0 && Char.code s.[i] land 0xc0 = 0x80 with
    | true -> boundary (i - 1)
    | false -> i
  in
  match String.length s <= cap with
  | true -> s
  | false -> String.trim (String.sub s 0 (boundary cap))

let of_url url = Option.map capped (Text.non_blank url)

let of_share ~title ~texts =
  Option.map capped
    (match List.filter_map Text.non_blank texts with
    | [] -> Text.non_blank title
    | texts -> Some (String.concat "\n" texts))
