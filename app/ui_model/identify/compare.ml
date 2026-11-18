module Organ = Herbier_identify.Organ
module Plantnet = Herbier_identify.Plantnet
module Proposal = Herbier_identify.Proposal

(* The proposals as a zipper ([previous] nearest first): the current one is
   always there, so nothing indexes a list that could be shorter than
   thought. *)
type t = {
  previous : Plantnet.proposal list;
  current : Plantnet.proposal;
  next : Plantnet.proposal list;
  mine : Organ.t option list;
  image : int;
}
[@@deriving eq]

let ordered ~mine (p : Plantnet.proposal) =
  List.filter_map (List.nth_opt p.images)
    (Proposal.display_order ~mine p.images)

let images t = ordered ~mine:t.mine t.current

let open_ ~proposals ~mine ~proposal ~tile =
  match (mine, proposal >= 0) with
  | [], (true | false) | _ :: _, false -> None
  | _ :: _, true -> (
      match List.drop proposal proposals with
      | [] -> None
      | current :: next -> (
          match tile >= 0 && tile < List.length (Proposal.closest current) with
          | false -> None
          | true ->
              let shown =
                match Proposal.tile_more current tile > 0 with
                | true -> Proposal.tiles
                | false -> tile
              in
              let image =
                Proposal.display_order ~mine current.images
                |> List.find_index (Int.equal shown)
                |> Option.value ~default:0
              in
              Some
                {
                  previous = List.rev (List.take proposal proposals);
                  current;
                  next;
                  mine;
                  image;
                }))

type event = Previous | Next | Shown of int

let step t = function
  | Previous -> (
      match t.previous with
      | [] -> t
      | p :: previous ->
          {t with previous; current = p; next = t.current :: t.next; image = 0})
  | Next -> (
      match t.next with
      | [] -> t
      | p :: next ->
          {
            t with
            previous = t.current :: t.previous;
            current = p;
            next;
            image = 0;
          })
  | Shown k ->
      let last = List.length t.current.images - 1 in
      {t with image = max 0 (min last k)}

let index t = List.length t.previous
let count t = List.length t.previous + 1 + List.length t.next
let proposal t = t.current
let can_previous t = match t.previous with [] -> false | _ :: _ -> true
let can_next t = match t.next with [] -> false | _ :: _ -> true
let image_index t = t.image
let image t = List.nth_opt (images t) t.image

let mine_index t =
  match image t with
  | Some {organ = Some o; _} ->
      List.find_index (Option.equal Organ.equal (Some o)) t.mine
      |> Option.value ~default:0
  | Some {organ = None; _} | None -> 0

let mine_organ t = Option.join (List.nth_opt t.mine (mine_index t))

let to_load t =
  let n = List.length t.current.images in
  List.filter (fun k -> k >= 0 && k < n) [t.image - 1; t.image; t.image + 1]
