(** One sighting. [plant_id = None]: not yet identified (« À identifier »). *)

type position = {
  lat : float;  (** WGS84 degrees. *)
  lon : float;  (** WGS84 degrees. *)
  accuracy_m : float option;
      (** GPS accuracy radius in metres; [None] when unknown (no accuracy
          reported, or the point was moved by hand). *)
}

type id = Ids.Observation_id.t
(** The id of the observation: [Ids.Observation_id.t] under a local name. *)

type t = {
  id : id;
  plant_id : Ids.Plant_id.t option;
  at : Ptime.t;
  position : position option;
      (** [None] when the row has neither [lat] nor [lon]; the schema forbids
          one without the other (architecture §2). *)
  place_label : string option;
      (** User-given name of the place cluster (handoff 4b). *)
  place_derived : string option;
      (** Reverse-geocoded label, cached (architecture §8). *)
  note : string option;
  created_at : Ptime.t;
  updated_at : Ptime.t;
  deleted_at : Ptime.t option;  (** [Some] = soft-deleted. *)
}
