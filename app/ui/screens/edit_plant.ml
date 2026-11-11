open Brr
module Db = Herbier_store.Db
module Plants = Herbier_store.Plants
module Tags = Herbier_store.Tags
module Observations = Herbier_store.Observations
module Photos = Herbier_store.Photos
module Cascade = Herbier_store.Cascade
module Observation = Herbier_domain.Observation
module Photo = Herbier_domain.Photo
module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id
module Tag = Herbier_domain.Tag
module RList = ReactiveData.RList
module W = Widgets

type mode = Edit of Plant_id.t | New

let cls c = At.class' (Jstr.v c)

let log_error what e =
  Console.(
    error [str ("modifier la fiche: " ^ what); str (Db.error_to_string e)])

(* A stored plant carries what a delete takes with it. *)
type origin =
  | Fresh
  | Stored of {observations : Observation.t list; photos : Photo.t list}

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
          let+ photos = Db.all db (Photos.of_plant id) in
          Some {plant; tags; all_tags; origin = Stored {observations; photos}})

let delete_edits ~at (d : data) ~observations ~photos =
  Cascade.plant ~at
    ~photos:(List.map (fun (p : Photo.t) -> p.id) photos)
    ~observations:(List.map (fun (o : Observation.t) -> o.id) observations)
    ~tags:(List.map (fun (t : Tag.t) -> t.id) d.tags)
    d.plant.id

let field_card label children =
  W.Card.panel (El.h2 ~at:[cls "t-section-label"] [El.txt' label] :: children)

let apply handle =
  List.iter (function
    | List_patch.Remove i -> RList.remove i handle
    | List_patch.Insert (i, v) -> RList.insert v i handle
    | List_patch.Update (i, v) -> RList.update v i handle)

let its_observations = function
  | 1 -> "son observation"
  | n -> Printf.sprintf "ses %d observations" n

let leaving ~observations ~photos =
  match (observations, photos) with
  | 0, _ -> "La fiche quitte l'herbier."
  | n, 0 ->
      Printf.sprintf "La fiche et %s quittent l'herbier." (its_observations n)
  | n, p ->
      Printf.sprintf
        "La fiche, %s et %s %s quittent l'herbier. Les originaux envoyés dans \
         Google Drive y restent."
        (its_observations n)
        (match n with 1 -> "ses" | _ -> "leurs")
        (Fr_text.plural p "photo" "photos")

type delete = Delete | Keep

(* Built for a stored plant only. *)
let delete_part ~problem ~leave app (d : data) ~observations ~photos =
  let n = List.length observations in
  let delete =
    W.Button.text ~tone:`Danger
      (match n with
      | 0 -> "Supprimer la plante ›"
      | n -> Printf.sprintf "Supprimer la plante et %s ›" (its_observations n))
  in
  let confirm =
    W.Dialog.v
      ~title:(Printf.sprintf "Supprimer « %s » ?" d.plant.display_name)
      ~text:(leaving ~observations:n ~photos:(List.length photos))
      [
        (W.Button.Danger, "Supprimer", Delete);
        (W.Button.Secondary, "Garder la plante", Keep);
      ]
  in
  let do_delete () =
    Fut.await
      (App.save app
         (delete_edits ~at:(Ptime_clock.now ()) d ~observations ~photos))
      (function
        | Error e ->
            log_error "delete" e;
            problem "La plante n'a pas pu être supprimée."
        | Ok _ ->
            leave (fun () -> Route.replace (Route.Tab W.Tab_bar.Collection)))
  in
  ( [El.div ~at:[cls "edit-plant__footer"] [delete.el]; confirm.el],
    List.concat
      [
        [
          Rb.act delete.click confirm.show;
          Rb.act confirm.choice (function Delete -> do_delete () | Keep -> ());
        ];
        delete.bindings;
        confirm.bindings;
      ] )

let render app mode (d : data) =
  (* style: [form] is the form, written from click and [added] handlers only
     (outside update steps), each write followed by [show]; the name lives in
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
    apply aliases_handle
      (List_patch.diff ~same:String.equal ~equal:String.equal
         (RList.value aliases) !form.aliases);
    let same a b =
      String.equal (Plant_form.tag_name a) (Plant_form.tag_name b)
    in
    apply tags_handle
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
  let add_alias = W.Adder.v ~label:"alias" ~placeholder:"Autre nom" () in
  let add_tag = W.Adder.v ~label:"tag" ~placeholder:"Nom du tag" () in
  let alias_list = El.span ~at:[cls "chip-row__items"] [] in
  let tag_list = El.span ~at:[cls "chip-row__items"] [] in
  let valid =
    React.S.map ~eq:Bool.equal
      (fun n -> not (String.equal (String.trim n) ""))
      name.value
  in
  let do_save () =
    match (!saving, React.S.value valid) with
    | true, _ | false, false -> ()
    | false, true -> (
        let f = {!form with name = React.S.value name.value} in
        let c = Plant_form.diff ~before:d.plant ~before_tags:d.tags f in
        match
          Plant_edits.of_change ~at:(Ptime_clock.now ()) ~plant:d.plant.id c
        with
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
  let cards =
    [
      field_card "Nom affiché"
        [
          name.el;
          El.div ~at:[cls "edit-plant__chips"] [alias_list; add_alias.el];
        ];
      field_card "Tags"
        [El.div ~at:[cls "edit-plant__chips"] [tag_list; add_tag.el]];
    ]
  in
  let delete_els, delete_bindings =
    match d.origin with
    | Fresh -> ([], [])
    | Stored {observations; photos} ->
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
          Rb.attr save.el "aria-disabled"
            (React.S.map (function true -> None | false -> Some "true") valid);
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
        cancel.bindings;
        save.bindings;
        name.bindings;
        add_alias.bindings;
        add_tag.bindings;
      ] )

(* A plant that is not (or no longer) live, or a form that could not be
   read: the reason under « Annuler ». *)
let notice text =
  let back = W.Button.text ~tone:`Ink "Annuler" in
  ( El.div
      [
        El.div ~at:[cls "modal-header"] [back.el];
        El.p ~at:[cls "t-body"] [El.txt' text];
      ],
    Rb.act back.click Route.back :: back.bindings )

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
    bindings =
      Loaded.v ~what:"modifier la fiche"
        ~failed:(fun () -> notice "La fiche n'a pas pu être lue.")
        el
        (fun () -> load (App.db app) mode)
        item;
  }
