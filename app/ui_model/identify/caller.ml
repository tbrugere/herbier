module Plant_id = Herbier_domain.Ids.Plant_id

type t = Noter | Queue of {index : int; total : int} | Free_name of Plant_id.t
[@@deriving eq]

type action = Choose | Link | Create [@@deriving eq, show]

let action t ~owned =
  match (t, owned) with
  | Noter, (true | false) -> Choose
  | Queue _, true -> Link
  | Queue _, false -> Create
  | Free_name (_ : Plant_id.t), (true | false) -> Link

let current = function Free_name id -> Some id | Noter | Queue _ -> None

let retake = function
  | Noter -> true
  | Queue _ | Free_name (_ : Plant_id.t) -> false
