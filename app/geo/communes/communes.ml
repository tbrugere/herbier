module Code = Code

let layer = Pack.layer

type departement = Wfs.departement = {code : Code.t; name : string}

let equal_departement = Wfs.equal_departement
let departements_request = Wfs.departements_request
let departements = Wfs.departements
let available = Wfs.available

type ring = Pack.ring

type commune = Pack.commune = {
  insee : string;
  name : string;
  polygons : ring list list;
}

type pack = Pack.t = {departement : Code.t; communes : commune list}

let equal_pack = Pack.equal
let tolerance_m = Pack.tolerance_m
let edge_m = Index.edge_m
let communes_request = Wfs.communes_request
let simplify = Simplify.simplify
let pack_of_payload = Wfs.pack_of_payload
let to_string = Pack_file.to_string
let of_string = Pack_file.of_string

type t = Index.t

let empty = Index.empty
let add = Index.add
let remove = Index.remove
let departements_of = Index.departements_of
let find = Index.find
let name = Index.name
