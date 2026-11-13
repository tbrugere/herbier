module Tag_id = Herbier_domain.Ids.Tag_id
module Original_target = Herbier_domain.Photo.Original_target

type filters = {
  tags : Tag_id.t list;
  year : int option;
  to_identify_only : bool;
}

let no_filters = {tags = []; year = None; to_identify_only = false}

let equal_filters a b =
  List.equal Tag_id.equal a.tags b.tags
  && Option.equal Int.equal a.year b.year
  && Bool.equal a.to_identify_only b.to_identify_only

type network = {online : bool; pending_uploads : int}

let equal_network a b =
  Bool.equal a.online b.online && Int.equal a.pending_uploads b.pending_uploads

type account = {
  auth : Herbier_sync.Auth.status;
  storage : Original_target.t;
  wifi_only : bool;
}

let equal_account a b =
  Herbier_sync.Auth.equal_status a.auth b.auth
  && Original_target.equal a.storage b.storage
  && Bool.equal a.wifi_only b.wifi_only

type camera = {center : Herbier_domain.Places.point; zoom : float}

type map_view = {
  camera : camera option;
  selected : Herbier_domain.Ids.Observation_id.t option;
  focus : Herbier_geo.Features.bounds option;
}

let no_map_view = {camera = None; selected = None; focus = None}

let equal_camera a b =
  Float.equal a.center.lat b.center.lat
  && Float.equal a.center.lon b.center.lon
  && Float.equal a.zoom b.zoom

let equal_bounds (a : Herbier_geo.Features.bounds)
    (b : Herbier_geo.Features.bounds) =
  Float.equal a.south b.south
  && Float.equal a.west b.west
  && Float.equal a.north b.north
  && Float.equal a.east b.east

let equal_map_view a b =
  Option.equal equal_camera a.camera b.camera
  && Option.equal Herbier_domain.Ids.Observation_id.equal a.selected b.selected
  && Option.equal equal_bounds a.focus b.focus

type 'a cell = {signal : 'a React.signal; set : ?step:React.step -> 'a -> unit}

let cell ~eq v =
  let signal, set = React.S.create ~eq v in
  {signal; set}

type t = {
  filters : filters cell;
  network : network cell;
  account : account cell;
  map_view : map_view cell;
  place_sources : Herbier_geo.Place_name.sources cell;
}

let create ~network ~account ~place_sources =
  {
    filters = cell ~eq:equal_filters no_filters;
    network = cell ~eq:equal_network network;
    account = cell ~eq:equal_account account;
    map_view = cell ~eq:equal_map_view no_map_view;
    place_sources = cell ~eq:Herbier_geo.Place_name.equal_sources place_sources;
  }

let filters t = t.filters.signal
let network t = t.network.signal
let account t = t.account.signal
let map_view t = t.map_view.signal
let place_sources t = t.place_sources.signal
let set_filters t ?step v = t.filters.set ?step v
let set_network t ?step v = t.network.set ?step v
let set_account t ?step v = t.account.set ?step v
let set_map_view t ?step v = t.map_view.set ?step v
let set_place_sources t ?step v = t.place_sources.set ?step v

let focus_map t b =
  let current = React.S.value t.map_view.signal in
  t.map_view.set {current with selected = None; focus = Some b}
