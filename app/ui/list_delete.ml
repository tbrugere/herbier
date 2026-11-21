module Delete_plan = Herbier_ui_model.Delete_plan
open Brr
module Db = Herbier_store_io.Db
module Plants = Herbier_store.Plants
module Observations = Herbier_store.Observations
module Photos = Herbier_store.Photos
module Tags = Herbier_store.Tags
module Plant_id = Herbier_domain.Ids.Plant_id
module Observation_id = Herbier_domain.Ids.Observation_id
module W = Widgets

type t = {
  el : El.t;
  plant : from:El.t -> Plant_id.t -> unit;
  observation : from:El.t -> Observation_id.t -> unit;
  bindings : Rb.binding list;
}

let toast_ms = 2500

type question = {
  title : string;
  text : string;
  edits : at:Ptime.t -> Herbier_store.Outbox.edit list;
  failure : string;  (** the toast when the save fails *)
}

let plant_question db id =
  let open Fut.Result_syntax in
  let* plant = Db.find db (Plants.get id) in
  match plant with
  | None -> Fut.ok None
  | Some plant ->
      let* observations = Db.all db (Observations.of_plant id) in
      let* photos = Db.all db (Photos.of_plant id) in
      let+ tags = Db.all db (Tags.of_plant id) in
      let d = Delete_plan.plant_of plant ~observations ~photos ~tags in
      Some
        {
          title = Delete_plan.plant_title plant;
          text = Delete_plan.plant_text d;
          edits = (fun ~at -> Delete_plan.plant_edits ~at d);
          failure = Delete_plan.plant_failure;
        }

let observation_question db id =
  let open Fut.Result_syntax in
  let* o = Db.find db (Observations.get id) in
  match o with
  | None -> Fut.ok None
  | Some (_ : Herbier_domain.Observation.t) ->
      let+ photos = Db.all db (Photos.of_observation id) in
      let d = Delete_plan.observation_of id ~photos in
      Some
        {
          title = Delete_plan.observation_title;
          text = Delete_plan.observation_text d;
          edits = (fun ~at -> Delete_plan.observation_edits ~at d);
          failure = Delete_plan.observation_failure;
        }

(* One question at a time: [Busy] while its read or its save runs. *)
type phase =
  | Idle
  | Busy
  | Asking of {overlay : Overlay.t; bindings : Rb.binding list}
  | Left

let v app ~scope =
  let host = El.div ~at:[Html.cls "list-delete"] [] in
  (* style: refs because they are written from DOM handlers, future callbacks
     and the release, outside any React update. *)
  let phase = ref Idle and toast = ref None in
  let settle () = match !phase with Left -> () | _ -> phase := Idle in
  let close_dialog next =
    (match !phase with
    | Asking a ->
        Overlay.remove a.overlay;
        Rb.release a.bindings;
        El.set_children host []
    | Idle | Busy | Left -> ());
    phase := next
  in
  let fail failure =
    match !phase with
    | Left ->
        (* The toast region is app-wide and the toast removes itself: it
           outlives the screen without a binding. *)
        ignore (W.Toast.show ~ms:toast_ms failure : Rb.binding)
    | Idle | Busy | Asking _ ->
        Option.iter (fun b -> Rb.release [b]) !toast;
        toast := Some (W.Toast.show ~ms:toast_ms failure)
  in
  let gone what =
    (* A save or a pull removed it; the reload that event started drops the
       card or row. *)
    Log.error ~scope ("delete " ^ what) "already gone"
  in
  (* The dependents are read again: a pull may have changed them while the
     dialog was open. *)
  let save ~what ~failure read =
    let saved =
      let open Fut.Result_syntax in
      let* q = read () in
      match q with
      | None -> Fut.ok false
      | Some q ->
          let+ (_ : int) = App.save app (q.edits ~at:(Ptime_clock.now ())) in
          true
    in
    Fut.await saved (fun result ->
        settle ();
        match result with
        | Ok true -> ()
        | Ok false -> gone what
        | Error e ->
            Log.db ~scope "delete" e;
            fail failure)
  in
  let ask ~what ~from read q =
    let d =
      W.Dialog.v ~title:q.title ~text:q.text
        [
          (W.Button.Danger, "Supprimer", Delete_plan.Delete);
          (W.Button.Secondary, "Annuler", Delete_plan.Keep);
        ]
    in
    let cancel () =
      close_dialog Idle;
      (* A no-op when a reload has replaced it. *)
      El.set_has_focus true from
    in
    El.set_children host [d.el];
    let bindings =
      Rb.act d.choice (function
        | Delete_plan.Keep -> cancel ()
        | Delete_plan.Delete ->
            close_dialog Busy;
            save ~what ~failure:q.failure read)
      :: Rb.listen d.el Ev.keydown (fun ev ->
          match Html.escape ev with true -> cancel () | false -> ())
      :: d.bindings
    in
    phase :=
      Asking {overlay = Overlay.push ~surface:Light ~close:cancel; bindings};
    d.show ()
  in
  let start ~what ~failure ~from read =
    match !phase with
    | Busy | Asking _ | Left -> ()
    | Idle ->
        phase := Busy;
        Fut.await (read ()) (fun result ->
            match (!phase, result) with
            | Left, _ -> ()
            | _, Error e ->
                phase := Idle;
                Log.db ~scope ("read " ^ what) e;
                fail failure
            | _, Ok None ->
                phase := Idle;
                gone what
            | _, Ok (Some q) -> ask ~what ~from read q)
  in
  let db = App.db app in
  {
    el = host;
    plant =
      (fun ~from id ->
        start ~what:"plant" ~failure:Delete_plan.plant_failure ~from (fun () ->
            plant_question db id));
    observation =
      (fun ~from id ->
        start ~what:"observation" ~failure:Delete_plan.observation_failure ~from
          (fun () -> observation_question db id));
    bindings =
      [
        Rb.on_release (fun () ->
            close_dialog Left;
            Option.iter (fun b -> Rb.release [b]) !toast;
            toast := None);
      ];
  }
