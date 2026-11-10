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

type account = {google_signed_in : bool; storage : Original_target.t}

let equal_account a b =
  Bool.equal a.google_signed_in b.google_signed_in
  && Original_target.equal a.storage b.storage

type 'a cell = {signal : 'a React.signal; set : ?step:React.step -> 'a -> unit}

let cell ~eq v =
  let signal, set = React.S.create ~eq v in
  {signal; set}

type t = {
  filters : filters cell;
  network : network cell;
  account : account cell;
}

let create ~network ~account =
  {
    filters = cell ~eq:equal_filters no_filters;
    network = cell ~eq:equal_network network;
    account = cell ~eq:equal_account account;
  }

let filters t = t.filters.signal
let network t = t.network.signal
let account t = t.account.signal
let set_filters t ?step v = t.filters.set ?step v
let set_network t ?step v = t.network.set ?step v
let set_account t ?step v = t.account.set ?step v
