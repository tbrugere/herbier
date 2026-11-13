type position = {
  lat : float; [@equal Float.equal]
  lon : float; [@equal Float.equal]
  accuracy_m : float option; [@equal Option.equal Float.equal]
}
[@@deriving eq, show]

type id = Ids.Observation_id.t [@@deriving eq, show]

type t = {
  id : id;
  plant_id : Ids.Plant_id.t option;
  at : Ptime.t;
  position : position option;
  place_label : string option;
  place_derived : string option;
  note : string option;
  created_at : Ptime.t;
  updated_at : Ptime.t;
  deleted_at : Ptime.t option;
}
[@@deriving eq, show]
