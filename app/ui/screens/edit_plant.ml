module Cover = Herbier_ui_model.Cover
module Delete_plan = Herbier_ui_model.Delete_plan
module Fr_date = Herbier_ui_model.Fr_date
module Fr_text = Herbier_ui_model.Fr_text
module List_patch = Herbier_ui_model.List_patch
module Plant_form = Herbier_ui_model.Plant_form
module Ref_paste = Herbier_ui_model.Ref_paste
open Brr
module Db = Herbier_store_io.Db
module Plants = Herbier_store.Plants
module Tags = Herbier_store.Tags
module Observations = Herbier_store.Observations
module Photos = Herbier_store.Photos
module References = Herbier_store.References
module Plant_ref = Herbier_domain.Reference.Plant_ref
module Source = Herbier_domain.Reference.Source
module Observation = Herbier_domain.Observation
module Photo = Herbier_domain.Photo
module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id
module Tag = Herbier_domain.Tag
module RList = ReactiveData.RList
module W = Widgets

type mode = Edit of Plant_id.t | New

let cls = Html.cls
let log_error = Log.db ~scope:"modifier la fiche"

(* A stored plant carries what a delete takes with it, and its links. *)
type origin =
  | Fresh
  | Stored of {
      observations : Observation.t list;
      photos : Photo.t list;
      plant_refs : Plant_ref.t list;
    }

(* What the form starts from. *)
type data = {
  plant : Plant.t;
  tags : Tag.t list;
  all_tags : Tag.t list;
  origin : origin;
}

let blank () = Plant.v ~id:(Plant_id.fresh ()) ~at:(Ptime_clock.now ()) ""

let load db mode =
  let open Fut.Result_syntax in
  let* all_tags = Db.all db Tags.list in
  match mode with
  | New -> Fut.ok (Some {plant = blank (); tags = []; all_tags; origin = Fresh})
  | Edit id -> (
      let* plant = Db.find db (Plants.get id) in
      match plant with
      | None -> Fut.ok None
      | Some plant ->
          let* tags = Db.all db (Tags.of_plant id) in
          let* observations = Db.all db (Observations.of_plant id) in
          let* photos = Db.all db (Photos.of_plant id) in
          let+ plant_refs = Db.all db (References.plant_refs id) in
          Some
            {
              plant;
              tags;
              all_tags;
              origin = Stored {observations; photos; plant_refs};
            })

let field_card label children =
  W.Card.panel (El.h2 ~at:[cls "t-card-label"] [El.txt' label] :: children)

(* Leaving for 4i with unsaved changes is refused: 5a is read again on
   return, and « Enregistrer » would otherwise write back the plant as it was
   before the link. *)
let reference_part ~problem ~dirty app (plant : Plant.t) plant_refs =
  let id = plant.id in
  let online =
    React.S.map ~eq:Bool.equal
      (fun (n : State.network) -> n.online)
      (State.network (App.state app))
  in
  let species, change =
    match plant.scientific_name with
    | Some latin ->
        ( El.p
            ~at:[cls "edit-plant__latin"]
            (El.i [El.txt' latin]
            :: Option.to_list
                 (Option.map
                    (fun a ->
                      El.span ~at:[cls "edit-plant__author"] [El.txt' (" " ^ a)])
                    plant.authorship)),
          W.Button.text "Changer ›" )
    | None ->
        ( El.p ~at:[cls "t-meta"] [El.txt' "nom libre — espèce non liée"],
          W.Button.text "Lier ›" )
  in
  let offline_hint =
    El.p
      ~at:[cls "t-meta"]
      [El.txt' "Hors-ligne : la recherche reviendra avec le réseau."]
  in
  let go_link () =
    match (React.S.value online, dirty ()) with
    | false, _ -> ()
    | true, true ->
        problem
          "Enregistrez ou annulez vos modifications avant de changer d'espèce."
    | true, false -> Route.go (Route.Modal (Route.Link_species id))
  in
  let refs, set_refs = React.S.create ~eq:( == ) plant_refs in
  let note_text, note = React.S.create ~eq:String.equal "" in
  let note_el = El.p ~at:[cls "t-meta"; cls "edit-plant__problem"] [] in
  let reload () =
    Fut.await
      (Db.all (App.db app) (References.plant_refs id))
      (function
        | Error e ->
            log_error "plant refs" e;
            note "Les liens n'ont pas pu être relus."
        | Ok rows -> set_refs rows)
  in
  let saved ?(done_ = "") what = function
    | Error e ->
        log_error what e;
        note "Le lien n'a pas pu être enregistré."
    | Ok (_ : int) ->
        note done_;
        reload ()
  in
  let ref_el (r : Plant_ref.t) =
    match Ref_paste.removable r with
    | false -> (W.Chip.tag (Ref_paste.label r), [])
    | true ->
        let c = W.Chip.removable ~fill:W.Chip.Paper (Ref_paste.label r) in
        ( c.el,
          Rb.act c.click (fun () ->
              Fut.await
                (App.save app
                   [
                     References.unlink ~plant:id ~source:r.source
                       ~at:(Ptime_clock.now ());
                   ])
                (saved "unlink"))
          :: c.bindings )
  in
  (* A handful of chips, rebuilt whole on each change: the paste field is
     outside them, so no focus or typed text is lost. *)
  let rows_el = El.span ~at:[cls "chip-row__items"] [] in
  let rows_of refs =
    let els = List.map ref_el refs in
    ( El.span ~at:[cls "edit-plant__refs"] (List.map fst els),
      List.concat_map snd els )
  in
  let paste =
    W.Adder.v ~label:"Coller un lien (POWO, INPN…)" ~placeholder:"https://…" ()
  in
  (* One link per source: a new paste replaces the stored one, and says so. *)
  let replaced source external_id =
    match
      List.find_opt
        (fun (r : Plant_ref.t) ->
          String.equal (Source.to_string r.source) (Source.to_string source)
          && not (String.equal r.external_id external_id))
        (React.S.value refs)
    with
    | None -> ""
    | Some old -> Printf.sprintf "Remplace %s." (Ref_paste.label old)
  in
  let pasted text =
    match Ref_paste.of_text text with
    | Ref_paste.Plant_ref {source; external_id; url} ->
        let done_ = replaced source external_id in
        Fut.await
          (App.save app
             [
               References.link ~plant:id ~source ~external_id ~url
                 ~at:(Ptime_clock.now ());
             ])
          (saved ~done_ "link")
    | Ref_paste.Species _ ->
        note "Lien GBIF : changez l'espèce avec « Changer › »."
    | Ref_paste.Not_a_reference -> note "Ce lien ne désigne pas une espèce."
    | Ref_paste.Unrecognised ->
        note
          "Lien non reconnu (GBIF, Pl@ntNet, Wikipédia, POWO, INPN, Tela \
           Botanica, iNaturalist)."
  in
  ( [
      field_card "Espèce de référence"
        [
          El.div ~at:[cls "edit-plant__species"] [species; change.el];
          offline_hint;
        ];
      field_card "Liens de référence"
        [El.div ~at:[cls "edit-plant__chips"] [rows_el; paste.el]; note_el];
    ],
    List.concat
      [
        [
          Rb.act change.click go_link;
          Rb.disabled change.el (React.S.map not online);
          Rb.class_ offline_hint "is-hidden" online;
          Rb.view rows_el rows_of refs;
          Rb.act paste.added pasted;
          Rb.text note_el note_text;
          Rb.class_ note_el "is-hidden"
            (React.S.map (String.equal "") note_text);
        ];
        change.bindings;
        paste.bindings;
      ] )

(* One tile of 5a « Photo de couverture ». *)
type cover_tile = {
  photo : Photo.t;
  el : El.t;
  click : unit React.event;
  binding : Rb.binding;
}

(* Built for a stored plant only. *)
let delete_part ~problem ~leave app (d : data) ~observations ~photos =
  let plan = Delete_plan.plant_of d.plant ~observations ~photos ~tags:d.tags in
  let delete = W.Button.text ~tone:`Danger (Delete_plan.plant_action plan) in
  let confirm =
    W.Dialog.v
      ~title:(Delete_plan.plant_title d.plant)
      ~text:(Delete_plan.plant_text plan)
      [
        (W.Button.Danger, "Supprimer", Delete_plan.Delete);
        (W.Button.Secondary, "Garder la plante", Delete_plan.Keep);
      ]
  in
  let do_delete () =
    Fut.await
      (App.save app (Delete_plan.plant_edits ~at:(Ptime_clock.now ()) plan))
      (function
        | Error e ->
            log_error "delete" e;
            problem Delete_plan.plant_failure
        | Ok _ ->
            leave (fun () -> Route.replace (Route.Tab W.Tab_bar.Collection)))
  in
  ( [El.div ~at:[cls "edit-plant__footer"] [delete.el]; confirm.el],
    List.concat
      [
        [
          Rb.act delete.click confirm.show;
          Rb.act confirm.choice (function
            | Delete_plan.Delete -> do_delete ()
            | Delete_plan.Keep -> ());
        ];
        delete.bindings;
        confirm.bindings;
      ] )

let render app mode (d : data) =
  (* style: [form] is the form, written from click and [added] handlers only
     (outside update steps), each write followed by [show] ([mark_cover] for
     the cover); the name lives in
     its text field and is read back at save time. [saving] keeps a second tap
     on « Enregistrer » from saving again while [App.save] runs; [left] keeps a
     second tap, or a save ending after the screen closed, from moving the
     history again. Both written from the handlers, the save's callback and
     the release. *)
  let form = ref (Plant_form.of_plant d.plant d.tags) in
  let saving = ref false and left = ref false in
  let leave nav =
    match !left with
    | true -> ()
    | false ->
        left := true;
        nav ()
  in
  let problem_text, problem = React.S.create ~eq:String.equal "" in
  let problem_el = El.p ~at:[cls "t-meta"; cls "edit-plant__problem"] [] in
  let cancel = W.Button.text ~tone:`Ink "Annuler" in
  let save = W.Button.text "Enregistrer" in
  let name =
    W.Text_field.v ~value:d.plant.display_name ~placeholder:"Nom de la plante"
      ()
  in
  El.set_class (Jstr.v "edit-plant__name") true name.el;
  let aliases, aliases_handle = RList.create [] in
  let tags, tags_handle = RList.create [] in
  let show () =
    Rb.patch aliases_handle
      (List_patch.diff ~same:String.equal ~equal:String.equal
         (RList.value aliases) !form.aliases);
    let same a b =
      String.equal (Plant_form.tag_name a) (Plant_form.tag_name b)
    in
    Rb.patch tags_handle
      (List_patch.diff ~same ~equal:same (RList.value tags) !form.tags)
  in
  let alias a =
    let c = W.Chip.removable ~fill:W.Chip.Paper a in
    ( c.el,
      Rb.act c.click (fun () ->
          form := Plant_form.remove_alias a !form;
          show ())
      :: c.bindings )
  in
  let tag t =
    let c = W.Chip.removable (Plant_form.tag_name t) in
    ( c.el,
      Rb.act c.click (fun () ->
          form := Plant_form.remove_tag t !form;
          show ())
      :: c.bindings )
  in
  show ();
  (* 5a « Photo de couverture »: the chosen one bordered; none chosen is the
     newest ({!Cover}). A tap on the tile already bordered changes nothing, so
     that tapping the newest one does not pin it. *)
  let photos = match d.origin with Fresh -> [] | Stored s -> s.photos in
  let is_cover (photo : Photo.t) =
    match Cover.choose !form.cover photos with
    | Some p -> Herbier_domain.Ids.Photo_id.equal p.id photo.id
    | None -> false
  in
  let covers =
    List.map
      (fun (photo : Photo.t) ->
        let el =
          Html.button
            ~label:
              ("Photo du "
              ^ Fr_date.day_month (Zone.date photo.taken_at)
              ^ ", choisir comme couverture")
            ["edit-plant__cover"]
            [W.Preview_img.v ~cls:["edit-plant__cover-img"] photo.preview_path]
        in
        let click, binding = Rb.click el in
        {photo; el; click; binding})
      photos
  in
  let mark_cover () =
    List.iter
      (fun c ->
        let on = is_cover c.photo in
        El.set_class (Jstr.v "is-selected") on c.el;
        El.set_at (Jstr.v "aria-pressed")
          (Some (Jstr.v (match on with true -> "true" | false -> "false")))
          c.el)
      covers
  in
  mark_cover ();
  let cover_bindings =
    List.concat_map
      (fun c ->
        [
          c.binding;
          Rb.act c.click (fun () ->
              match is_cover c.photo with
              | true -> ()
              | false ->
                  form := {!form with cover = Some c.photo.id};
                  mark_cover ());
        ])
      covers
  in
  let add_alias = W.Adder.v ~label:"alias" ~placeholder:"Autre nom" () in
  let add_tag = W.Adder.v ~label:"tag" ~placeholder:"Nom du tag" () in
  let alias_list = El.span ~at:[cls "chip-row__items"] [] in
  let tag_list = El.span ~at:[cls "chip-row__items"] [] in
  let valid =
    React.S.map ~eq:Bool.equal
      (fun n -> not (String.equal (String.trim n) ""))
      name.value
  in
  let edits_now () =
    let f = {!form with name = React.S.value name.value} in
    let c = Plant_form.diff ~before:d.plant ~before_tags:d.tags f in
    Plant_edits.of_change ~at:(Ptime_clock.now ()) ~plant:d.plant.id c
  in
  let dirty () = match edits_now () with _, [] -> false | _, _ :: _ -> true in
  let do_save () =
    match (!saving, React.S.value valid) with
    | true, _ | false, false -> ()
    | false, true -> (
        match edits_now () with
        | _, [] -> leave Route.back
        | _, edits ->
            saving := true;
            Fut.await (App.save app edits) (function
              | Error e ->
                  saving := false;
                  log_error "save" e;
                  problem "La fiche n'a pas pu être enregistrée."
              | Ok _ ->
                  leave (fun () ->
                      match mode with
                      | New ->
                          Route.replace (Route.Modal (Route.Plant d.plant.id))
                      | Edit _ -> Route.back ())))
  in
  let header =
    El.div
      ~at:[cls "modal-header"]
      [
        cancel.el;
        El.span
          ~at:[cls "modal-header__title"]
          [
            El.txt'
              (match mode with
              | New -> "Nouvelle plante"
              | Edit _ -> "Modifier");
          ];
        save.el;
      ]
  in
  let reference_els, reference_bindings =
    match d.origin with
    | Fresh -> ([], [])
    | Stored {plant_refs; _} ->
        reference_part ~problem ~dirty app d.plant plant_refs
  in
  let cards =
    List.concat
      [
        [
          field_card "Nom affiché"
            [
              name.el;
              El.div ~at:[cls "edit-plant__chips"] [alias_list; add_alias.el];
            ];
        ];
        reference_els;
        [
          field_card "Tags"
            [El.div ~at:[cls "edit-plant__chips"] [tag_list; add_tag.el]];
        ];
      ]
    @
    match covers with
    | [] -> []
    | _ :: _ ->
        [
          field_card "Photo de couverture"
            [
              El.div
                ~at:[cls "edit-plant__covers"]
                (List.map (fun c -> c.el) covers);
            ];
        ]
  in
  let delete_els, delete_bindings =
    match d.origin with
    | Fresh -> ([], [])
    | Stored {observations; photos; _} ->
        delete_part ~problem ~leave app d ~observations ~photos
  in
  let el =
    El.div
      ~at:[cls "edit-plant__content"]
      ((header :: problem_el :: cards) @ delete_els)
  in
  ( el,
    List.concat
      [
        [
          Rb.rlist alias_list alias aliases;
          Rb.rlist tag_list tag tags;
          Rb.act cancel.click (fun () -> leave Route.back);
          Rb.act save.click do_save;
          Rb.disabled save.el (React.S.map not valid);
          Rb.act add_alias.added (fun a ->
              form := Plant_form.add_alias a !form;
              show ());
          Rb.act add_tag.added (fun t ->
              form := Plant_form.add_tag ~all:d.all_tags t !form;
              show ());
          Rb.text problem_el problem_text;
          Rb.class_ problem_el "is-hidden"
            (React.S.map (String.equal "") problem_text);
          Rb.on_release (fun () -> left := true);
        ];
        delete_bindings;
        reference_bindings;
        cancel.bindings;
        save.bindings;
        name.bindings;
        add_alias.bindings;
        add_tag.bindings;
        cover_bindings;
      ] )

(* A plant that is not (or no longer) live, or a form that could not be
   read: the reason under « Annuler ». *)
let notice text = Loaded.notice ~back:"Annuler" text

let v app mode =
  (* Loaded once: the form does not follow saves made elsewhere while it is
     open. *)
  let el = El.div ~at:[cls "screen"; cls "edit-plant"] [] in
  let item = function
    | Some d -> render app mode d
    | None -> notice "Cette plante n'est plus dans l'herbier."
  in
  {
    Screen.el;
    ready = Screen.now;
    bindings =
      Loaded.v ~what:"modifier la fiche"
        ~failed:(fun () -> notice "La fiche n'a pas pu être lue.")
        el
        (fun () -> load (App.db app) mode)
        item;
  }
