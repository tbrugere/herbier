open Brr
module W = Widgets

let el () =
  let rows =
    List.init 20 (fun i ->
        W.List_row.v ~thumb:W.List_row.Placeholder
          ~title:(Printf.sprintf "Observation %d" (i + 1))
          ~meta:"14:32 · 1 photo" ())
  in
  let height = El.span ~at:[At.id (Jstr.v "visible")] [] in
  let log =
    El.ol ~at:[At.id (Jstr.v "settled"); At.class' (Jstr.v "t-meta")] []
  in
  (* A header control: a tap on it must reach it, not start a drag. *)
  let rename = El.button [El.txt' "Renommer"] in
  let renamed = El.span ~at:[At.id (Jstr.v "renamed")] [] in
  let sheet =
    W.Sheet.v ~snaps:[72.; 360.; 640.]
      ~header:
        [
          El.p ~at:[At.class' (Jstr.v "t-sheet-title")] [El.txt' "Lisière nord"];
          El.p
            ~at:[At.class' (Jstr.v "t-meta")]
            [El.txt' "rayon 500 m · 6 observations"];
          rename;
        ]
      ~body:(List.map (fun (r : W.List_row.t) -> r.el) rows)
      ()
  in
  let snap i = El.button [El.txt' (Printf.sprintf "snap %d" i)] in
  (* "snap 3" is out of range: snap_to clamps it to the top. *)
  let buttons = List.init 4 snap in
  let clicks =
    List.mapi
      (fun i b -> Rb.listen b Ev.click (fun _ -> sheet.snap_to i))
      buttons
  in
  let renames, rename_click = Rb.ev rename Ev.click in
  let root =
    El.div
      [
        El.h1 ~at:[At.class' (Jstr.v "t-screen-title")] [El.txt' "Sheet check"];
        El.p [El.txt' "visible: "; height];
        El.p [El.txt' "Renommer clicks: "; renamed];
        El.p buttons;
        log;
        sheet.el;
      ]
  in
  let bindings =
    Rb.text height
      (React.S.map
         (fun v -> string_of_int (Float.to_int (Float.round v)))
         sheet.visible)
    :: Rb.on sheet.settled (fun i ->
        El.append_children log [El.li [El.txt' (Printf.sprintf "settled %d" i)]])
    :: Rb.text renamed
         (React.S.map string_of_int (React.S.fold (fun n _ -> n + 1) 0 renames))
    :: rename_click
    :: (clicks @ sheet.bindings)
  in
  Rb.hold root bindings;
  root
