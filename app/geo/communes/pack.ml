let layer = "ADMINEXPRESS-COG-CARTO.LATEST"

type ring = ((float[@equal Float.equal]) * (float[@equal Float.equal])) array
[@@deriving eq]

type commune = {insee : string; name : string; polygons : ring list list}
[@@deriving eq]

type t = {departement : Code.t; communes : commune list} [@@deriving eq]

let tolerance_m = 20.

(* All of a list or nothing. Tail-recursive: a ring has thousands of
   vertices. *)
let all f l =
  let rec go acc = function
    | [] -> Some (List.rev acc)
    | x :: rest -> (
        match f x with Some y -> go (y :: acc) rest | None -> None)
  in
  go [] l
