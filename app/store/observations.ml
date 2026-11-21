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
  and+ deleted_at = Row.col O.deleted_at
  and+ place_detail = Row.col O.place_detail in
  {
    Observation.id;
    plant_id;
    at;
    position = position lat lon accuracy_m;
    place_label;
    place_derived;
    place_detail;
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

let to_geocode =
  query
    " and lat is not null and lon is not null and (place_derived is null or \
     trim(place_derived) = '') and trim(coalesce(place_label, '')) = ''"
    []

let to_rename =
  query
    " and lat is not null and lon is not null and trim(coalesce(place_derived, \
     '')) <> '' and trim(coalesce(place_label, '')) = '' and id in (select \
     observation_id from place_renames)"
    []

let labelled =
  query
    " and lat is not null and lon is not null and trim(coalesce(place_label, \
     '')) <> ''"
    []

let input (o : Observation.t) : (O.t, [`Full]) Postgrest.Input.t =
  let lat, lon, accuracy_m =
    match o.position with
    | None -> (None, None, None)
    | Some {lat; lon; accuracy_m} -> (Some lat, Some lon, accuracy_m)
  in
  Postgrest.Input.
    {
      fields =
        [
          Mandatory (O.id, Value o.id);
          Optional (O.plant_id, Value o.plant_id);
          Mandatory (O.at, Value o.at);
          Optional (O.lat, Value lat);
          Optional (O.lon, Value lon);
          Optional (O.accuracy_m, Value accuracy_m);
          Optional (O.place_label, Value o.place_label);
          Optional (O.place_derived, Value o.place_derived);
          Optional (O.note, Value o.note);
          Mandatory (O.created_at, Value o.created_at);
          Mandatory (O.updated_at, Value o.updated_at);
          Optional (O.deleted_at, Value o.deleted_at);
          Optional (O.place_detail, Value o.place_detail);
        ];
    }

module Writes = By_id.Make (struct
  type table = O.t
  type id = Observation_id.t
  type row = Observation.t

  let table = O.table
  let id = O.id
  let row = row
  let id_of (o : Observation.t) = o.id
  let id_to_string = Observation_id.to_string
  let input = input
end)

let upsert = Writes.upsert
let soft_delete = Writes.soft_delete

(* The position and "still unnamed" conditions make a name computed before a
   move or a concurrent edit a no-op instead of overwriting newer data. *)
let set_place_derived id ~lat ~lon ~detail name ~at =
  Writes.edit id
    {
      Stmt.sql =
        "update observations set place_derived = ?, place_detail = ?, \
         updated_at = ? where id = ? and deleted_at is null and lat = ? and \
         lon = ? and (place_derived is null or trim(place_derived) = '')";
      params =
        [
          Codec.param O.place_derived (Some name);
          Codec.param O.place_detail detail;
          Codec.param O.updated_at at;
          Codec.param O.id id;
          Codec.param O.lat (Some lat);
          Codec.param O.lon (Some lon);
        ];
    }

(* Same guards as set_place_derived, the name read before resolving standing
   for "still unnamed"; "is not" compares nulls as values, so an unchanged
   name and detail write nothing and queue nothing. *)
let rename_place_derived id ~lat ~lon ~was ~detail name ~at =
  Writes.edit id
    {
      Stmt.sql =
        "update observations set place_derived = ?, place_detail = ?, \
         updated_at = ? where id = ? and deleted_at is null and lat = ? and \
         lon = ? and place_derived = ? and trim(coalesce(place_label, '')) = \
         '' and (place_derived is not ? or place_detail is not ?)";
      params =
        [
          Codec.param O.place_derived (Some name);
          Codec.param O.place_detail detail;
          Codec.param O.updated_at at;
          Codec.param O.id id;
          Codec.param O.lat (Some lat);
          Codec.param O.lon (Some lon);
          Codec.param O.place_derived (Some was);
          Codec.param O.place_derived (Some name);
          Codec.param O.place_detail detail;
        ];
    }
