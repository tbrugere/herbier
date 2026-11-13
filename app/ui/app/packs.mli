(** The « IGN hors-ligne » packs (architecture §8): download and delete.
    Documented in {!App}. *)

val packs : Core.t -> Core.pack list React.signal

type pack_error = Busy | Offline | Pack of Herbier_geo_io.Commune_packs.error

val pack_error_to_string : pack_error -> string

val departements :
  Core.t -> (Herbier_geo.Communes.departement list, pack_error) result Fut.t

val downloading : Core.t -> Herbier_geo.Communes.departement option React.signal

val download_pack :
  Core.t -> Herbier_geo.Communes.departement -> (unit, pack_error) result Fut.t

val delete_pack :
  Core.t -> Herbier_geo.Communes.Code.t -> (unit, pack_error) result Fut.t
