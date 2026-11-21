module Col = Postgrest.Col
module Observation_id = Herbier_domain.Ids.Observation_id

(* A local-only table: its columns live next to its queries (layout §2), not
   in Tables. *)
type place_renames

let observation_id : (place_renames, Observation_id.t, [`Mandatory]) Col.t =
  {ty = Not_Null (Custom Tables.ids_observation_id); name = "observation_id"}

let n : (place_renames, int, [`Mandatory]) Col.t =
  {ty = Not_Null Integer; name = "n"}

let forget id =
  {
    Stmt.sql = "delete from place_renames where observation_id = ?";
    params = [Codec.param observation_id id];
  }

let count =
  Stmt.query ~json:[] (Postgrest.Row.col n)
    "select count(*) as n from place_renames" []
