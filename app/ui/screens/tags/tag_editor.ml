module Collection_filter = Herbier_ui_model.Collection_filter
module Tag_edits = Herbier_ui_model.Tag_edits
open Brr
module Db = Herbier_store_io.Db
module Tags = Herbier_store.Tags
module Tag = Herbier_domain.Tag
module Tag_id = Herbier_domain.Ids.Tag_id
module W = Widgets

let cls = Html.cls

type t = {
  el : El.t;
  open_ : Tag_edits.editor -> unit;
  saved : Tag_edits.change React.event;
  bindings : Rb.binding list;
}

(* What the box shows: the field, or the delete question asked from it. *)
type phase = Closed | Form of Tag_edits.editor | Asking of Tag_edits.editor
type answer = Confirm | Keep

let editor_of = function Closed -> None | Form e | Asking e -> Some e

let edits ~at change =
  List.map
    (function
      | Tag_edits.Insert_tag name ->
          Tags.upsert (Tag.v ~id:(Tag_id.fresh ()) ~at name)
      | Tag_edits.Rename_tag (t, name) ->
          Tags.upsert {t with name; updated_at = at}
      | Tag_edits.Delete_tag id -> Tags.soft_delete id ~at
      | Tag_edits.Link {plant; tag} -> Tags.tag ~plant ~tag ~at
      | Tag_edits.Unlink {plant; tag} -> Tags.untag ~plant ~tag ~at)
    (Tag_edits.plan change)

(* The box was opened on the tags of the last read; a pull may have changed
   them since. A merge relinks the plants carrying [from] now, a rename writes
   over the tag as stored now; [None]: the renamed tag is gone. *)
let current db change =
  let open Fut.Result_syntax in
  match change with
  | Tag_edits.Merge m ->
      let+ links = Db.all db Tags.links in
      Some
        (Tag_edits.Merge
           {
             m with
             plants = List.concat (Collection_filter.tagged links [m.from]);
           })
  | Tag_edits.Rename r -> (
      let+ found = Db.all db (Tags.get r.tag.id) in
      match found with
      | tag :: _ -> Some (Tag_edits.Rename {r with tag})
      | [] -> None)
  | Tag_edits.Create _ | Tag_edits.Delete _ -> Fut.return (Ok (Some change))

let failed = "Enregistrement impossible : rien n’a été modifié."
let title_id = "tag-editor-title"

let v app ~tags =
  let state = App.state app in
  let phase, set_phase = React.S.create ~eq:( == ) Closed in
  let failure, set_failure = React.S.create "" in
  let saved, send_saved = React.E.create () in
  let field = W.Text_field.v ~placeholder:"Nom du tag" () in
  El.set_at (Jstr.v "aria-label") (Some (Jstr.v "Nom du tag")) field.input;
  (* style: platform state written from DOM handlers and future callbacks
     only: the overlay registered while the box is open, whether a save runs
     (its buttons then do nothing, and [open_] ignores a tap until it settles),
     and the delete question's dialog bindings while it is shown. *)
  let overlay = ref None and saving = ref false and asking = ref [] in
  let ask_host = El.div [] in
  let drop_question () =
    Rb.release !asking;
    asking := [];
    El.set_children ask_host []
  in
  let show next fail =
    let step = React.Step.create () in
    set_phase ~step next;
    set_failure ~step fail;
    React.Step.execute step
  in
  (* Android back closes the whole box, the delete question with it; its
     « Annuler » and Escape step back to the field instead. *)
  let close () =
    Option.iter Overlay.remove !overlay;
    overlay := None;
    drop_question ();
    show Closed ""
  in
  let open_ (editor : Tag_edits.editor) =
    match !saving with
    | true -> ()
    | false ->
        field.set
          (match editor with
          | Tag_edits.New -> ""
          | Tag_edits.Edit {tag; _} -> tag.name);
        show (Form editor) "";
        (match !overlay with
        | Some _ -> ()
        | None -> overlay := Some (Overlay.push ~surface:Light ~close));
        El.set_has_focus true field.input
  in
  (* A box Android back closed during the save stays closed: its failure is
     only logged. *)
  let fail editor =
    match React.S.value phase with
    | Closed -> ()
    | Form _ | Asking _ ->
        drop_question ();
        show (Form editor) failed
  in
  let save editor change =
    match !saving with
    | true -> ()
    | false ->
        saving := true;
        set_failure "";
        let at = Ptime_clock.now () in
        Fut.await
          (let open Fut.Result_syntax in
           let* change = current (App.db app) change in
           match change with
           | None -> Fut.return (Ok None)
           | Some change ->
               let+ _ = App.save app (edits ~at change) in
               Some change)
          (fun result ->
            saving := false;
            match result with
            | Error e ->
                Console.(
                  error [str "tag editor: save"; str (Db.error_to_string e)]);
                fail editor
            | Ok None ->
                Console.(error [str "tag editor: the tag is gone"]);
                fail editor
            | Ok (Some change) ->
                (* Here rather than in 4l: 4l may be gone by now. *)
                let f = React.S.value (State.filters state) in
                State.set_filters state
                  {f with tags = Tag_edits.followed change f.tags};
                close ();
                send_saved change)
  in
  let unless_saving f () = match !saving with true -> () | false -> f () in
  let submit () =
    match React.S.value phase with
    | Form editor ->
        Option.iter (save editor)
          (Tag_edits.submit ~tags:(React.S.value tags) editor
             (React.S.value field.value))
    | Closed | Asking _ -> ()
  in
  let back_to_field editor =
    drop_question ();
    show (Form editor) "";
    El.set_has_focus true field.input
  in
  let ask editor =
    match editor with
    | Tag_edits.New -> ()
    | Tag_edits.Edit {tag; plants} ->
        drop_question ();
        let d =
          W.Dialog.v
            ~title:(Tag_edits.delete_title tag)
            ~text:(Tag_edits.delete_text ~plants:(List.length plants))
            [
              (W.Button.Danger, "Supprimer", Confirm);
              (W.Button.Secondary, "Annuler", Keep);
            ]
        in
        El.set_children ask_host [d.el];
        asking :=
          Rb.act d.choice (function
            | Keep -> back_to_field editor
            | Confirm -> (
                match !saving with
                | true -> ()
                | false -> Option.iter (save editor) (Tag_edits.delete editor)))
          :: Rb.listen d.el Ev.keydown (fun ev ->
              match Html.escape ev with
              | true -> back_to_field editor
              | false -> ())
          :: d.bindings;
        show (Asking editor) "";
        d.show ()
  in
  let cancel () =
    match React.S.value phase with
    | Asking editor -> back_to_field editor
    | Form _ | Closed -> close ()
  in
  let primary =
    React.S.l3
      (fun tags phase text ->
        match editor_of phase with
        | Some editor ->
            Tag_edits.primary editor (Tag_edits.check ~tags editor text)
        | None -> Tag_edits.primary Tag_edits.New Tag_edits.Blank)
      tags phase field.value
  in
  let line =
    React.S.l2
      (fun failure (p : Tag_edits.primary) ->
        match (failure, p.line) with
        | "", line -> Option.value ~default:"" line
        | failure, _ -> failure)
      failure primary
  in
  let title =
    React.S.map
      (fun phase ->
        Option.fold ~none:"" ~some:Tag_edits.title (editor_of phase))
      phase
  in
  let ok =
    W.Button.dynamic
      (React.S.map (fun (p : Tag_edits.primary) -> p.label) primary)
  in
  let delete = W.Button.v ~kind:W.Button.Danger "Supprimer le tag" in
  let dismiss = W.Button.text ~tone:`Ink "Annuler" in
  let title_el = El.h2 ~at:[cls "t-sheet-title"; At.id (Jstr.v title_id)] [] in
  let line_el = El.p ~at:[cls "tag-editor__line"] [] in
  let box =
    El.div
      ~at:
        [
          cls "confirm__box";
          At.v (Jstr.v "role") (Jstr.v "dialog");
          At.v (Jstr.v "aria-modal") (Jstr.v "true");
          At.v (Jstr.v "aria-labelledby") (Jstr.v title_id);
        ]
      [title_el; field.el; line_el; ok.el; delete.el; dismiss.el]
  in
  let el = El.div ~at:[cls "confirm"; cls "tag-editor"] [box] in
  let is_form = function Form _ -> true | Asking _ | Closed -> false in
  let can_delete : phase -> bool = function
    | Form (Tag_edits.Edit _) -> true
    | Form Tag_edits.New | Asking _ | Closed -> false
  in
  {
    el = El.div [el; ask_host];
    open_;
    saved;
    bindings =
      [
        Rb.class_ el "is-hidden" (React.S.map (fun p -> not (is_form p)) phase);
        Rb.class_ delete.el "is-hidden"
          (React.S.map (fun p -> not (can_delete p)) phase);
        Rb.text title_el title;
        Rb.text line_el line;
        Rb.class_ line_el "is-hidden" (React.S.map (String.equal "") line);
        Rb.class_ line_el "tag-editor__line--failure"
          (React.S.map (fun f -> not (String.equal f "")) failure);
        Rb.disabled ok.el
          (React.S.map (fun (p : Tag_edits.primary) -> not p.enabled) primary);
        Rb.act ok.click (unless_saving submit);
        Rb.act delete.click
          (unless_saving (fun () ->
               match React.S.value phase with
               | Form editor -> ask editor
               | Asking _ | Closed -> ()));
        Rb.act dismiss.click (unless_saving cancel);
        Rb.listen field.input Ev.keydown (fun ev ->
            match () with
            | () when Html.enter ev -> unless_saving submit ()
            | () when Html.escape ev -> unless_saving cancel ()
            | () -> ());
        Rb.on_release (fun () ->
            Option.iter Overlay.remove !overlay;
            overlay := None;
            Rb.release !asking;
            asking := []);
      ]
      @ field.bindings
      @ ok.bindings
      @ delete.bindings
      @ dismiss.bindings;
  }
