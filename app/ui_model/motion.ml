type place =
  | Collection
  | Tab
  | Fiche of Herbier_domain.Ids.Plant_id.t
  | Modal
  | Dev

type direction = Forward | Back | Replace | Unknown [@@deriving eq]

let direction ~before ~after =
  match (before, after) with
  | Some b, Some a -> (
      match Int.compare a b with
      | 0 -> Replace
      | c when c > 0 -> Forward
      | _ -> Back)
  | None, _ | _, None -> Unknown

type kind =
  | Instant
  | Fade
  | Modal_in
  | Modal_out
  | Hero_in of Herbier_domain.Ids.Plant_id.t
  | Hero_out of Herbier_domain.Ids.Plant_id.t
[@@deriving eq]

let kind ~from ~to_ direction =
  match (from, to_) with
  | Dev, _ | _, Dev -> Instant
  | (Collection | Tab), (Collection | Tab) -> Instant
  | Collection, Fiche p -> (
      match direction with
      | Back -> Fade
      | Forward | Replace | Unknown -> Hero_in p)
  | Fiche p, Collection -> Hero_out p
  | Tab, (Modal | Fiche _) | Collection, Modal -> (
      match direction with
      | Back -> Fade
      | Forward | Replace | Unknown -> Modal_in)
  | (Modal | Fiche _), Tab -> Modal_out
  | Modal, Collection -> Modal_out
  | (Modal | Fiche _), (Modal | Fiche _) -> (
      match direction with
      | Forward -> Modal_in
      | Back -> Modal_out
      | Replace | Unknown -> Fade)

let without_hero = function
  | Hero_in _ -> Modal_in
  | Hero_out _ -> Modal_out
  | (Instant | Fade | Modal_in | Modal_out) as k -> k

type how = Now | Css_fade | View [@@deriving eq]

let how ~supported ~reduced kind =
  match (reduced, kind, supported) with
  | true, _, _ | false, Instant, _ -> Now
  | false, (Fade | Modal_in | Modal_out | Hero_in _ | Hero_out _), false ->
      Css_fade
  | false, (Fade | Modal_in | Modal_out | Hero_in _ | Hero_out _), true -> View

let attribute = function
  | Instant -> None
  | Fade -> Some "fade"
  | Modal_in -> Some "modal-in"
  | Modal_out -> Some "modal-out"
  | Hero_in _ -> Some "hero-in"
  | Hero_out _ -> Some "hero-out"

let hero = function
  | Hero_in p | Hero_out p -> Some p
  | Instant | Fade | Modal_in | Modal_out -> None

let ready_cap_ms = 300
let in_view ~viewport_height ~top ~bottom = bottom > 0. && top < viewport_height
