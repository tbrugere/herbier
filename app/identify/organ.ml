type t = Flower | Leaf | Fruit | Bark | Habit [@@deriving eq]

let all = [Flower; Leaf; Fruit; Bark; Habit]

let to_string = function
  | Flower -> "flower"
  | Leaf -> "leaf"
  | Fruit -> "fruit"
  | Bark -> "bark"
  | Habit -> "habit"

let pp ppf o = Format.pp_print_string ppf (to_string o)

let of_string = function
  | "flower" -> Some Flower
  | "leaf" -> Some Leaf
  | "fruit" -> Some Fruit
  | "bark" -> Some Bark
  | "habit" -> Some Habit
  | _ -> None

let label = function
  | Flower -> "fleur"
  | Leaf -> "feuille"
  | Fruit -> "fruit"
  | Bark -> "écorce"
  | Habit -> "port"

type sent = Auto | Given of t [@@deriving eq]

let sent_to_string = function Auto -> "auto" | Given o -> to_string o
let max_photos = 5

let effective sent ~detected =
  match sent with Given o -> Some o | Auto -> detected

type suggestion = Add of t | Add_photo [@@deriving eq]

let suggest organs =
  let has o = List.exists (Option.equal equal (Some o)) organs in
  match () with
  | () when List.length organs >= max_photos -> None
  | () when not (has Flower) -> Some (Add Flower)
  | () when not (has Leaf) -> Some (Add Leaf)
  | () -> Some Add_photo

let suggestion_label = function
  | Add o -> "+ " ^ label o
  | Add_photo -> "+ photo"

let sent_of_suggestion = function Add o -> Given o | Add_photo -> Auto
