module Tag_id = Herbier_domain.Ids.Tag_id
module Original_target = Herbier_domain.Photo.Original_target

type filters = {
  tags : Tag_id.t list;
  year : int option;
  to_identify_only : bool;
}
[@@deriving eq]

let no_filters = {tags = []; year = None; to_identify_only = false}

type network = {online : bool} [@@deriving eq]

type account = {
  auth : Herbier_sync.Auth.status;
  storage : Original_target.t;
  drive : Herbier_sync_core.Auth.Drive_account.t;
  wifi_only : bool;
}
[@@deriving eq]

type camera = {
  center : Herbier_domain.Places.point;
  zoom : float; [@equal Float.equal]
}
[@@deriving eq]

type map_view = {
  camera : camera option;
  selected : Herbier_domain.Ids.Observation_id.t option;
  focus : Herbier_geo.Features.bounds option;
      [@equal Option.equal Herbier_domain.Bbox.equal]
}
[@@deriving eq]

let no_map_view = {camera = None; selected = None; focus = None}

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
