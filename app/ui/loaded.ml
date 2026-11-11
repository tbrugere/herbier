open Brr

let log what e =
  Console.(error [str what; str (Herbier_store.Db.error_to_string e)])

let v ?reload ?failed ~what el load render =
  (* One item, replaced on each load: [Rb.rlist] owns its bindings. *)
  let content, handle = ReactiveData.RList.create [] in
  let item = function
    | Ok v -> render v
    | Error () -> (
        match failed with Some f -> f () | None -> (El.div [], []))
  in
  let run () =
    Fut.await (load ()) (function
      | Error e -> (
          log what e;
          (* A failed reload keeps what is shown. *)
          match ReactiveData.RList.value content with
          | [] -> ReactiveData.RList.set handle [Error ()]
          | _ :: _ -> ())
      | Ok v -> ReactiveData.RList.set handle [Ok v])
  in
  run ();
  Rb.rlist el item content
  :: (match reload with Some e -> [Rb.act e run] | None -> [])

type 'a shown = Live of 'a React.signal | Gone | Failed

let live ~reload ~what ~gone ~failed el load render =
  let content, handle = ReactiveData.RList.create [] in
  (* style: [update] sets the value of the rendering on screen, if one is: a
     reload updates it rather than rendering a new one. Written by the loads'
     callbacks only. *)
  let update = ref None in
  let run () =
    Fut.await (load ()) (function
      | Error e -> (
          log what e;
          match !update with
          | Some _ -> ()
          | None -> ReactiveData.RList.set handle [Failed])
      | Ok None ->
          update := None;
          ReactiveData.RList.set handle [Gone]
      | Ok (Some v) -> (
          match !update with
          | Some set -> set v
          | None ->
              let s, set = React.S.create ~eq:( == ) v in
              update := Some set;
              ReactiveData.RList.set handle [Live s]))
  in
  run ();
  let item = function
    | Live s -> render s
    | Gone -> gone ()
    | Failed -> failed ()
  in
  [Rb.rlist el item content; Rb.act reload run]

let notice text =
  let back = Widgets.Button.text ~tone:`Ink "Retour" in
  ( El.div
      [
        El.div ~at:[At.class' (Jstr.v "modal-header")] [back.el];
        El.p ~at:[At.class' (Jstr.v "t-body")] [El.txt' text];
      ],
    Rb.act back.click Route.back :: back.bindings )
