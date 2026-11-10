open Brr
module Tags = Herbier_store.Tags
module Tag = Herbier_domain.Tag
module Tag_id = Herbier_domain.Ids.Tag_id
module RList = ReactiveData.RList
module W = Widgets

let cls c = At.class' (Jstr.v c)

let button classes children =
  El.button ~at:(At.type' (Jstr.v "button") :: List.map cls classes) children

(* The store writes for the staged model, at [at]. *)
let edits ~at (tags : Tag.t list) model =
  List.filter_map
    (function
      | Tag_edits.Rename (id, name) ->
          Option.map
            (fun (t : Tag.t) -> Tags.upsert {t with name; updated_at = at})
            (List.find_opt (fun (t : Tag.t) -> Tag_id.equal t.id id) tags)
      | Tag_edits.Delete id -> Some (Tags.soft_delete id ~at)
      | Tag_edits.Link {plant; tag} -> Some (Tags.tag ~plant ~tag ~at)
      | Tag_edits.Unlink {plant; tag} -> Some (Tags.untag ~plant ~tag ~at))
    (Tag_edits.plan model)

let enter ev = Jstr.equal (Ev.Keyboard.key (Ev.as_type ev)) (Jstr.v "Enter")

let v app =
  let state = App.state app in
  let rows, rows_handle = RList.create [] in
  let count_text, set_count_text = React.S.create "" in
  let bar_shown, set_bar_shown = React.S.create false in
  let merge_label, set_merge_label = React.S.create None in
  let failure, set_failure = React.S.create "" in
  (* style: the staged model, the checked tags, the tag being renamed with
     its draft, whether its field has just opened (to focus it), that field
     once built, and whether a save is running; written from [Rb.act] /
     [Rb.listen] handlers and future callbacks (outside update steps), each
     model change followed by [refresh], except [focus], which [row] sets
     while [Rb.rlist] builds the rename field and [refresh] consumes right
     after [RList.set]. *)
  let tags = ref []
  and model = ref []
  and checked = ref []
  and editing = ref None
  and opening = ref false
  and focus = ref None
  and saving = ref false in
  let rec refresh () =
    checked :=
      List.filter
        (fun id ->
          List.exists
            (fun (e : Tag_edits.entry) -> Tag_id.equal e.id id)
            (Tag_edits.visible !model))
        !checked;
    RList.set rows_handle (Tag_edits.visible !model);
    (match !focus with
    | Some input ->
        focus := None;
        opening := false;
        El.set_has_focus true input
    | None -> ());
    let n = List.length !checked in
    let step = React.Step.create () in
    set_bar_shown ~step (n > 0);
    set_count_text ~step (Fr_text.plural n "sélectionné" "sélectionnés");
    set_merge_label ~step
      (Option.map
         (fun (w : Tag_edits.entry) ->
           Printf.sprintf "Fusionner en “%s”" w.name)
         (Tag_edits.winner !checked !model));
    React.Step.execute step
  and row (e : Tag_edits.entry) =
    let is_checked = List.exists (Tag_id.equal e.id) !checked in
    let box =
      button
        (["check"] @ match is_checked with true -> ["check--on"] | false -> [])
        [
          El.span
            ~at:[cls "check__box"]
            (match is_checked with
            | true -> [W.Icon.el ~size:16 W.Icon.Check]
            | false -> []);
        ]
    in
    El.set_at (Jstr.v "aria-pressed")
      (Some (Jstr.v (string_of_bool is_checked)))
      box;
    El.set_at (Jstr.v "aria-label") (Some (Jstr.v e.name)) box;
    let box_click, b_box = Rb.click box in
    let toggle () =
      (checked :=
         match is_checked with
         | true -> List.filter (fun id -> not (Tag_id.equal id e.id)) !checked
         | false -> e.id :: !checked);
      refresh ()
    in
    let count =
      El.span
        ~at:[cls "manage-tags__count"]
        [El.txt' (string_of_int (List.length (Tag_edits.plants !model e)))]
    in
    let middle, extra =
      match !editing with
      | Some (id, draft) when Tag_id.equal id e.id ->
          let field =
            W.Text_field.v ~value:draft ~placeholder:"Nom du tag" ()
          in
          (match !opening with
          | true -> focus := Some field.input
          | false -> ());
          let ok = W.Button.text "OK" in
          let confirm () =
            model := Tag_edits.rename e.id (React.S.value field.value) !model;
            editing := None;
            refresh ()
          in
          ( El.div ~at:[cls "manage-tags__rename"] [field.el; ok.el],
            Rb.act ok.click confirm
            :: Rb.act (React.S.changes field.value) (fun v ->
                editing := Some (e.id, v))
            :: Rb.listen field.input Ev.keydown (fun ev ->
                match enter ev with true -> confirm () | false -> ())
            :: (field.bindings @ ok.bindings) )
      | Some _ | None ->
          let edit = button ["icon-button"] [W.Icon.el ~size:20 W.Icon.Edit] in
          El.set_at (Jstr.v "aria-label")
            (Some (Jstr.v ("Renommer " ^ e.name)))
            edit;
          let edit_click, b_edit = Rb.click edit in
          ( El.div
              ~at:[cls "manage-tags__name-line"]
              [
                El.span ~at:[cls "manage-tags__name"] [El.txt' e.name];
                count;
                edit;
              ],
            [
              b_edit;
              Rb.act edit_click (fun () ->
                  editing := Some (e.id, e.name);
                  opening := true;
                  refresh ());
            ] )
    in
    ( El.div ~at:[cls "manage-tags__row"] [box; middle],
      b_box :: Rb.act box_click toggle :: extra )
  in
  Fut.await
    (Tag_usage.load (App.db app))
    (function
      | Error e ->
          Console.(
            error [str "manage tags"; str (Herbier_store.Db.error_to_string e)]);
          set_failure "Lecture impossible"
      | Ok usage ->
          tags := List.map (fun (u : Tag_usage.t) -> u.tag) usage;
          model :=
            Tag_edits.init
              (List.map
                 (fun (u : Tag_usage.t) -> (u.tag.id, u.tag.name, u.plants))
                 usage);
          refresh ());
  let cancel = W.Button.text ~tone:`Ink "Annuler" in
  let done_ = W.Button.text "Terminé" in
  (* While a save runs, « Terminé » and « Annuler » do nothing: its reply
     leaves the screen once. *)
  let finish () =
    match (!saving, edits ~at:(Ptime_clock.now ()) !tags !model) with
    | true, _ -> ()
    | false, [] -> Route.back ()
    | false, es ->
        saving := true;
        set_failure "";
        Fut.await (App.save app es) (function
          | Error e ->
              saving := false;
              Console.(
                error
                  [
                    str "manage tags: save";
                    str (Herbier_store.Db.error_to_string e);
                  ]);
              set_failure "Enregistrement impossible : rien n’a été modifié."
          | Ok _ ->
              let f = React.S.value (State.filters state) in
              State.set_filters state
                {f with tags = Tag_edits.followed !model f.tags};
              Route.back ())
  in
  let delete = W.Button.v ~kind:W.Button.Danger "Supprimer" in
  let merge =
    W.Button.dynamic (React.S.map (Option.value ~default:"") merge_label)
  in
  let count_el = El.span ~at:[cls "manage-tags__selected"] [] in
  let failure_el = El.p ~at:[cls "manage-tags__failure"] [] in
  let bar =
    El.div
      ~at:[cls "manage-tags__bar"]
      [count_el; El.div ~at:[cls "manage-tags__actions"] [delete.el; merge.el]]
  in
  let list_el = El.div ~at:[cls "manage-tags__rows"] [] in
  let el =
    El.div
      ~at:[cls "screen"; cls "manage-tags"]
      [
        El.div
          ~at:[cls "modal-header"]
          [
            cancel.el;
            El.span ~at:[cls "modal-header__title"] [El.txt' "Gérer les tags"];
            done_.el;
          ];
        failure_el;
        list_el;
        bar;
      ]
  in
  {
    Screen.el;
    bindings =
      [
        Rb.rlist list_el row rows;
        Rb.text count_el count_text;
        Rb.text failure_el failure;
        Rb.class_ failure_el "is-hidden" (React.S.map (String.equal "") failure);
        Rb.class_ bar "is-hidden" (React.S.map not bar_shown);
        Rb.class_ merge.el "is-hidden" (React.S.map Option.is_none merge_label);
        Rb.act cancel.click (fun () ->
            match !saving with true -> () | false -> Route.back ());
        Rb.act done_.click finish;
        Rb.act delete.click (fun () ->
            model := Tag_edits.delete !checked !model;
            checked := [];
            refresh ());
        Rb.act merge.click (fun () ->
            model := Tag_edits.merge !checked !model;
            checked := [];
            refresh ());
      ]
      @ cancel.bindings
      @ done_.bindings
      @ delete.bindings
      @ merge.bindings;
  }
