module Observation_id = Herbier_domain.Ids.Observation_id
module M = Map.Make (Observation_id)

type counts = {on_way : int; written : int} [@@deriving eq]
type t = counts M.t

let empty = M.empty
let equal = M.equal equal_counts
let none = {on_way = 0; written = 0}
let counts id t = Option.value ~default:none (M.find_opt id t)
let on_way id t = (counts id t).on_way
let written id t = (counts id t).written

let add id t =
  let c = counts id t in
  M.add id {c with on_way = c.on_way + 1} t

let settle ~written id t =
  match counts id t with
  | {on_way = 0; written = _} -> t
  | c ->
      M.add id
        {
          on_way = c.on_way - 1;
          written =
            (match written with true -> c.written + 1 | false -> c.written);
        }
        t
