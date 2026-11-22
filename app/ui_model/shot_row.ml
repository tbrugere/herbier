type ticket = int

let equal_ticket = Int.equal
let pp_ticket = Format.pp_print_int

type 'shot slot = Pending of ticket | Ready of 'shot [@@deriving eq]

(* [next] is the ticket the next tap gets: it only grows, so a ticket filled
   or dropped is never handed out again. [handed]: the pending tickets an
   Enregistrer gave to its observation. *)
type 'shot t = {next : ticket; slots : 'shot slot list; handed : ticket list}

let empty = {next = 0; slots = []; handed = []}
let slots t = t.slots

let begin_capture t =
  ({t with next = t.next + 1; slots = t.slots @ [Pending t.next]}, t.next)

let is ticket = function Pending p -> equal_ticket p ticket | Ready _ -> false

let fill ticket shot t =
  {
    t with
    slots =
      List.map
        (fun s -> match is ticket s with true -> Ready shot | false -> s)
        t.slots;
  }

let drop ticket t =
  {
    slots = List.filter (fun s -> not (is ticket s)) t.slots;
    handed = List.filter (Fun.negate (equal_ticket ticket)) t.handed;
    next = t.next;
  }

let is_pending ticket t = List.exists (is ticket) t.slots

let append shots t =
  {t with slots = t.slots @ List.map (fun s -> Ready s) shots}

let remove f t =
  {
    t with
    slots =
      List.filter (function Ready s -> not (f s) | Pending _ -> true) t.slots;
  }

let ready t =
  List.filter_map (function Ready s -> Some s | Pending _ -> None) t.slots

let is_pending_slot = function Pending _ -> true | Ready _ -> false

let pending t =
  List.fold_left
    (fun n s -> match is_pending_slot s with true -> n + 1 | false -> n)
    0 t.slots

let can_save t = not (List.is_empty t.slots)
let is_handed t ticket = List.exists (equal_ticket ticket) t.handed

let hand_over t =
  let fresh =
    List.filter_map
      (function
        | Pending p when not (is_handed t p) -> Some p
        | Pending _ | Ready _ -> None)
      t.slots
  in
  ({t with handed = t.handed @ fresh}, fresh)

type fate = Fill | Attach | Discard [@@deriving eq, show {with_path = false}]

let fate ticket t =
  match (is_pending ticket t, is_handed t ticket) with
  | false, (true | false) -> Discard
  | true, false -> Fill
  | true, true -> Attach

let attaching t = List.length (List.filter (fun p -> is_pending p t) t.handed)
