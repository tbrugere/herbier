type surface = Light | Dark [@@deriving eq, show]
type bar = Status | Navigation [@@deriving eq, show]
type t = {status : surface; navigation : surface} [@@deriving eq, show]

let resolve ~route ~overlays ~offline_banner =
  let top = match overlays with top :: _ -> top | [] -> route in
  {status = (if offline_banner then Dark else top); navigation = top}

let changes ~previous t =
  let bar b ~was now =
    match was with
    | Some s when equal_surface s now -> []
    | Some _ | None -> [(b, now)]
  in
  let was f = Option.map f previous in
  bar Status ~was:(was (fun p -> p.status)) t.status
  @ bar Navigation ~was:(was (fun p -> p.navigation)) t.navigation
