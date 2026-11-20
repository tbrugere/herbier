module Plant_id = Herbier_domain.Ids.Plant_id

type place = {index : int; total : int} [@@deriving eq]

type t = Observation | Queue of place option | Free_name of Plant_id.t
[@@deriving eq]

type action = Link | Create [@@deriving eq, show]

let action t ~owned =
  match (t, owned) with
  | (Observation | Queue _), true -> Link
  | (Observation | Queue _), false -> Create
  | Free_name (_ : Plant_id.t), (true | false) -> Link

let current = function Free_name id -> Some id | Observation | Queue _ -> None
