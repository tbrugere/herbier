module Resolve = Herbier_refs.Resolve

type status =
  | Blank
  | Pending
  | Found of Resolve.Candidate.t list
  | Offline
  | Failed of string

let equal_status a b =
  match (a, b) with
  | Blank, Blank | Pending, Pending | Offline, Offline -> true
  | Found a, Found b -> List.equal Resolve.Candidate.equal a b
  | Failed a, Failed b -> String.equal a b
  | (Blank | Pending | Found _ | Offline | Failed _), _ -> false

type t = {query : string; status : status; seq : int}

let query t = t.query
let status t = t.status
let seq t = t.seq

type effect_ =
  | No_effect
  | Wait of {seq : int; ms : int}
  | Fetch of {seq : int; q : string}

let debounce_ms = 300

(* A fresh request: the query is not blank and the network is up. *)
let fetch t = ({t with status = Pending}, Fetch {seq = t.seq; q = t.query})

let start ~online t =
  match (t.query, online) with
  | "", _ -> ({t with status = Blank}, No_effect)
  | _, false -> ({t with status = Offline}, No_effect)
  | _, true -> fetch t

let init ~online text =
  start ~online {query = String.trim text; status = Blank; seq = 0}

let typed ~online text t =
  match String.trim text with
  | q when String.equal q t.query -> (t, No_effect)
  | q -> (
      let t = {t with query = q; seq = t.seq + 1} in
      match (q, online) with
      | "", _ -> ({t with status = Blank}, No_effect)
      | _, false -> ({t with status = Offline}, No_effect)
      | _, true ->
          ({t with status = Pending}, Wait {seq = t.seq; ms = debounce_ms}))

let elapsed ~online ~seq t =
  match (seq = t.seq, online) with
  | false, _ -> (t, No_effect)
  | true, false -> ({t with status = Offline}, No_effect)
  | true, true -> (t, Fetch {seq; q = t.query})

let answered ~seq result t =
  match (seq = t.seq, result) with
  | false, _ -> t
  | true, Ok l -> {t with status = Found l}
  | true, Error (Resolve.Unavailable m) -> {t with status = Failed m}
  | true, Error (Resolve.No_species | Resolve.Observation_link) ->
      {t with status = Found []}

let network ~online t =
  match (online, t.status, t.query) with
  | false, (Pending | Failed _), _ ->
      ({t with seq = t.seq + 1; status = Offline}, No_effect)
  | true, (Offline | Failed _), "" -> (t, No_effect)
  | true, (Offline | Failed _), _ -> fetch {t with seq = t.seq + 1}
  | false, (Blank | Found _ | Offline), _ | true, (Blank | Pending | Found _), _
    ->
      (t, No_effect)

let retry ~online t =
  match (t.query, online) with
  | "", _ -> (t, No_effect)
  | _, false -> ({t with status = Offline}, No_effect)
  | _, true -> fetch {t with seq = t.seq + 1}
