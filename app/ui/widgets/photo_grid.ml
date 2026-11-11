open Brr
module Photo = Herbier_domain.Photo

type t = {el : El.t; tap : Photo.t React.event; bindings : Rb.binding list}

let badges (p : Photo.t) =
  let hidden = At.v (Jstr.v "aria-hidden") (Jstr.v "true") in
  let up =
    match Photo.awaiting_drive p with
    | true ->
        [
          El.span ~at:[At.class' (Jstr.v "photo-badge-up"); hidden] [El.txt' "↑"];
        ]
    | false -> []
  in
  let local =
    match p.original_target with
    | App_only ->
        [
          El.span
            ~at:[At.class' (Jstr.v "photo-badge-local"); hidden]
            [El.txt' "local"];
        ]
    | Drive -> []
  in
  up @ local

let tile ?cls (p : Photo.t) =
  let box =
    Preview_img.v ~cls:("photo-tile" :: Option.to_list cls) p.preview_path
  in
  El.append_children box (badges p);
  box

(* The badges are hidden from screen readers; the label says the same. *)
let label ~i ~n (p : Photo.t) =
  String.concat ", "
    (Printf.sprintf "Photo %d sur %d" (i + 1) n
    :: List.concat
         [
           (match Photo.awaiting_drive p with
           | true -> ["en attente de Google Drive"]
           | false -> []);
           (match p.original_target with App_only -> ["locale"] | Drive -> []);
         ])

let v photos =
  let tap, send = React.E.create () in
  let n = List.length photos in
  let tiles =
    List.mapi
      (fun i p ->
        let b =
          El.button
            ~at:
              [
                At.type' (Jstr.v "button");
                At.class' (Jstr.v "photo-grid__item");
                At.v (Jstr.v "aria-label") (Jstr.v (label ~i ~n p));
              ]
            [tile p]
        in
        (b, Rb.listen b Ev.click (fun _ -> send p)))
      photos
  in
  {
    el = El.div ~at:[At.class' (Jstr.v "photo-grid")] (List.map fst tiles);
    tap;
    bindings = List.map snd tiles;
  }
