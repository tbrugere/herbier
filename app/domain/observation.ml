type position = {lat : float; lon : float; accuracy_m : float option}
type id = Ids.Observation_id.t

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
