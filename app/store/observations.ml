module Observation = Herbier_domain.Observation
module Observation_id = Herbier_domain.Ids.Observation_id
module Plant_id = Herbier_domain.Ids.Plant_id
module O = Tables.Observations
module Row = Postgrest.Row

let position lat lon accuracy_m =
  match (lat, lon) with
  | Some lat, Some lon -> Some {Observation.lat; lon; accuracy_m}
  | None, _ | _, None -> None

let row =
  let open Row.Syntax in
  let+ id = Row.col O.id
  and+ plant_id = Row.col O.plant_id
  and+ at = Row.col O.at
  and+ lat = Row.col O.lat
  and+ lon = Row.col O.lon
  and+ accuracy_m = Row.col O.accuracy_m
  and+ place_label = Row.col O.place_label
  and+ place_derived = Row.col O.place_derived
  and+ note = Row.col O.note
  and+ created_at = Row.col O.created_at
  and+ updated_at = Row.col O.updated_at
  and+ deleted_at = Row.col O.deleted_at in
  {
    Observation.id;
    plant_id;
    at;
    position = position lat lon accuracy_m;
    place_label;
    place_derived;
    note;
    created_at;
    updated_at;
    deleted_at;
  }

let query where params =
  Stmt.query ~json:[] row
    ("select * from observations where deleted_at is null"
    ^ where
    ^ " order by at desc, id desc")
    params

let list = query "" []
let get id = query " and id = ?" [Codec.param O.id id]

let of_plant plant =
  query " and plant_id = ?" [Codec.param O.plant_id (Some plant)]

let unidentified = query " and plant_id is null" []

let between ~from ~until =
  query " and at >= ? and at < ?"
    [Codec.param O.at from; Codec.param O.at until]

let upsert (o : Observation.t) =
  let lat, lon, accuracy_m =
    match o.position with
    | None -> (None, None, None)
    | Some {lat; lon; accuracy_m} -> (Some lat, Some lon, accuracy_m)
  in
  Stmt.upsert ~table:O.table
    [
      Stmt.col O.id o.id;
      Stmt.col O.plant_id o.plant_id;
      Stmt.col O.at o.at;
      Stmt.col O.lat lat;
      Stmt.col O.lon lon;
      Stmt.col O.accuracy_m accuracy_m;
      Stmt.col O.place_label o.place_label;
      Stmt.col O.place_derived o.place_derived;
      Stmt.col O.note o.note;
      Stmt.col O.created_at o.created_at;
      Stmt.col O.updated_at o.updated_at;
      Stmt.col O.deleted_at o.deleted_at;
    ]

let soft_delete id ~at =
  Stmt.soft_delete ~table:O.table ~id:(Codec.param O.id id) ~at
