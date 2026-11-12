open Brr

type 'a t = {
  el : El.t;
  show : unit -> unit;
  show_only : ('a -> bool) -> unit;
  choice : 'a React.event;
  bindings : Rb.binding list;
}

(* style: module-level counter for unique ids; nothing else reads it. *)
let count = ref 0

let fresh_id () =
  incr count;
  Printf.sprintf "dialog-text-%d" !count

let v ~title ?text ?(body = []) actions =
  let text = Option.map (fun t -> (fresh_id (), t)) text in
  let buttons =
    List.map (fun (kind, label, value) -> (Button.v ~kind label, value)) actions
  in
  let el =
    El.div
      ~at:[At.class' (Jstr.v "confirm"); At.class' (Jstr.v "is-hidden")]
      [
        El.div
          ~at:
            ([
               At.class' (Jstr.v "confirm__box");
               At.v (Jstr.v "role") (Jstr.v "dialog");
               At.v (Jstr.v "aria-modal") (Jstr.v "true");
               At.v (Jstr.v "aria-label") (Jstr.v title);
             ]
            @ Option.to_list
                (Option.map
                   (fun (id, _) -> At.v (Jstr.v "aria-describedby") (Jstr.v id))
                   text))
          (El.h2 ~at:[At.class' (Jstr.v "t-sheet-title")] [El.txt' title]
           ::
           (match text with
           | None -> []
           | Some (id, t) ->
               [
                 El.p
                   ~at:[At.id (Jstr.v id); At.class' (Jstr.v "t-body")]
                   [El.txt' t];
               ])
          @ body
          @ List.map (fun ((b : Button.t), _) -> b.el) buttons);
      ]
  in
  let visible on = El.set_class (Jstr.v "is-hidden") (not on) el in
  let show_only keep =
    let shown =
      List.filter_map
        (fun ((b : Button.t), value) ->
          let on = keep value in
          El.set_class (Jstr.v "is-hidden") (not on) b.el;
          match on with true -> Some b | false -> None)
        buttons
    in
    visible true;
    match shown with
    | (b : Button.t) :: _ -> El.set_has_focus true b.el
    | [] -> ()
  in
  let show () = show_only (fun _ -> true) in
  let choice =
    React.E.select
      (List.map
         (fun ((b : Button.t), value) -> React.E.map (fun () -> value) b.click)
         buttons)
  in
  let hide = Rb.on choice (fun _ -> visible false) in
  {
    el;
    show;
    show_only;
    choice;
    bindings =
      hide :: List.concat_map (fun ((b : Button.t), _) -> b.bindings) buttons;
  }
