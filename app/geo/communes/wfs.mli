(** The Géoplateforme WFS side of a pack: the requests of Admin Express COG
    carto, and the decoding of their answers (the départements list, a
    département's communes simplified into a pack). *)

type departement = {code : Code.t; name : string}

val equal_departement : departement -> departement -> bool

val departements_request : Geocode.request
(** [Communes.departements_request]. *)

val departements : Yojson.Safe.t -> (departement list, Geocode.error) result
(** [Communes.departements]. *)

val available : downloaded:Code.t list -> departement list -> departement list
(** [Communes.available]. *)

val communes_request : departement:Code.t -> Geocode.request
(** [Communes.communes_request]. *)

val pack_of_payload :
  departement:Code.t -> Yojson.Safe.t -> (Pack.t, Geocode.error) result
(** [Communes.pack_of_payload]. *)
