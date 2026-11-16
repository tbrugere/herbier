let tiles = 4
let closest (p : Plantnet.proposal) = List.take tiles p.images
let more (p : Plantnet.proposal) = max 0 (List.length p.images - tiles)

let more_label p =
  match more p with 0 -> None | n -> Some (Printf.sprintf "+%d" n)

let same_organ_first ~mine images =
  match mine with
  | None -> images
  | Some _ ->
      let same, others =
        List.partition
          (fun (i : Plantnet.image) -> Option.equal Organ.equal i.organ mine)
          images
      in
      same @ others

let licence_label licence =
  let licence = String.trim licence in
  let lower = String.lowercase_ascii licence in
  match () with
  | () when String.starts_with ~prefix:"cc-" lower && String.length licence > 3
    ->
      "CC "
      ^ String.uppercase_ascii
          (String.sub licence 3 (String.length licence - 3))
  | () when String.equal lower "cc0" -> "CC0"
  | () -> licence

let credit (i : Plantnet.image) =
  String.concat " · " ["© " ^ i.author; licence_label i.licence; "Pl@ntNet"]

let min_best = 0.5
let min_lead = 0.15

(* Pl@ntNet's scores carry five decimals: the lead is compared in those
   units, since 0.6 -. 0.45 is 0.14999999999999997 in binary. *)
let in_units x = Float.round (x *. 1e5)

let uncertain : Plantnet.proposal list -> bool = function
  | [] -> true
  | best :: rest ->
      let second =
        match rest with
        | [] -> 0.
        | (second : Plantnet.proposal) :: _ -> second.score
      in
      best.score < min_best
      || in_units (best.score -. second) < in_units min_lead
