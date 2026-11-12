open Brr
module W = Widgets

(* A stand-in cover photo: a moss-to-ochre gradient, so the 5f scrim and the
   cream names show as they would on a picture. *)
let photo =
  "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 3 \
   4'%3E%3ClinearGradient id='g' x2='0' y2='1'%3E%3Cstop offset='0' \
   stop-color='%238fbf6a'/%3E%3Cstop offset='1' \
   stop-color='%23b8781a'/%3E%3C/linearGradient%3E%3Crect width='3' height='4' \
   fill='url(%23g)'/%3E%3C/svg%3E"

let cls c = At.class' (Jstr.v c)

let entry name els =
  El.div
    ~at:
      [
        At.v (Jstr.v "data-entry") (Jstr.v name);
        At.style (Jstr.v "margin:0 0 28px");
      ]
    (El.h2
       ~at:[cls "t-section-label"; At.style (Jstr.v "margin-bottom:10px")]
       [El.txt' name]
    :: els)

(* Widgets only show state; a screen derives it from their events. The
   gallery closes that loop with [S.fix]: the widget reads the delayed value
   of the signal its own events define, so it updates in the next step. *)
let toggling tone label start =
  React.S.fix start (fun delayed ->
      let chip = W.Chip.filter ~tone ~label ~active:delayed () in
      let active =
        React.S.accum (React.E.map (fun () on -> not on) chip.click) start
      in
      (active, (chip, active)))

let tab_bar () =
  React.S.fix W.Tab_bar.Collection (fun delayed ->
      let bar = W.Tab_bar.v ~active:delayed in
      let active = React.S.hold W.Tab_bar.Collection bar.select in
      (active, (bar, active)))

let el () =
  let log_el = El.ol ~at:[At.id (Jstr.v "log"); cls "t-meta"] [] in
  let log line = El.append_children log_el [El.li [El.txt' line]] in
  let logged e f = Rb.on e (fun v -> log (f v)) in
  let chips =
    List.map
      (fun (tone, label, on) ->
        let chip, _active = toggling tone label on in
        (chip, [logged chip.click (fun () -> "chip " ^ label)]))
      [
        (W.Chip.Ink, "Toutes", true);
        (W.Chip.Ink, "montagne", false);
        (W.Chip.Ink, "toxique", false);
        (W.Chip.Ochre, "À identifier · 3", false);
        (W.Chip.Ochre, "À identifier · 1", true);
      ]
  in
  let tags = W.Chip.link "Tags ›" in
  let removables =
    [
      W.Chip.removable "Forêt";
      W.Chip.removable ~fill:W.Chip.Paper "gant de Notre-Dame";
    ]
  in
  let adder = W.Adder.v ~label:"tag" ~placeholder:"Nom du tag" () in
  let cards =
    [
      W.Card.plant ~name:"Digitale pourpre" ~sci:(Some "Digitalis purpurea")
        (W.Card.Photo photo);
      W.Card.plant ~name:"Arnica" ~sci:(Some "Arnica montana")
        (W.Card.Loading "Google Photos…");
      W.Card.plant ~name:"Trolle d'Europe" ~sci:(Some "Trollius europaeus")
        (W.Card.No_photo "sans photo · 4 obs.");
      W.Card.plant ~name:"Plante du talus" ~sci:None
        (W.Card.No_photo "sans photo · 1 obs.");
      W.Card.plant ~name:"Aperçu absent" ~sci:None
        (W.Card.Preview "previews/absent.jpg");
    ]
  in
  (* Previews that do not exist, so each tile shows the striped state with the
     badges of its pair. *)
  let grid_photo original_target upload_state : Herbier_domain.Photo.t =
    let t0 = Ptime.epoch in
    {
      id = Herbier_domain.Ids.Photo_id.fresh ();
      observation_id = Herbier_domain.Ids.Observation_id.fresh ();
      taken_at = t0;
      width = 1;
      height = 1;
      sha256 = "";
      preview_path = "previews/absent.jpg";
      preview_bucket_key = None;
      original_target;
      drive_file_id = None;
      upload_state;
      created_at = t0;
      updated_at = t0;
      deleted_at = None;
    }
  in
  let grid =
    W.Photo_grid.v
      [
        grid_photo Drive Pending;
        grid_photo Drive Uploaded;
        grid_photo Drive Failed;
        grid_photo App_only Pending;
      ]
  in
  let rows =
    [
      W.List_row.v ~thumb:(W.List_row.Image photo) ~title:"Digitale pourpre"
        ~meta:"14:32 · 2 photos · note" ();
      W.List_row.v ~thumb:W.List_row.Placeholder ~tone:W.List_row.To_identify
        ~title:"À identifier"
        ~meta:"13:48 · 1 photo · « rosette poilue, sol tourbeux »" ();
      W.List_row.v ~title:"Sans vignette" ~meta:"une ligne de métadonnées" ();
    ]
  in
  let search =
    W.Text_field.v ~icon:W.Icon.Search ~action:"Coller un lien"
      ~placeholder:"Nom, tag, lieu…" ()
  in
  let name =
    W.Text_field.v ~value:"Digitale pourpre" ~placeholder:"Nom affiché" ()
  in
  let link = W.Text_field.v ~action:"Coller" ~placeholder:"Lien" () in
  let bar, _active = tab_bar () in
  let mini_maps =
    match Theme.load () with
    | Error (Theme.Missing_tokens missing) ->
        log ("mini-carte: jetons absents: " ^ String.concat ", " missing);
        []
    | Ok theme ->
        List.map
          (fun accuracy_m ->
            W.Mini_map.v ~colours:theme.map
              (React.S.const
                 (Some
                    {
                      Herbier_domain.Observation.lat = 45.7712;
                      lon = 3.0823;
                      accuracy_m;
                    })))
          [Some 30.; None]
  in
  let bindings =
    List.concat
      [
        List.concat_map (fun ((c : W.Chip.t), bs) -> bs @ c.bindings) chips;
        tags.bindings;
        [logged tags.click (fun () -> "link Tags")];
        List.concat_map (fun (c : W.Chip.t) -> c.bindings) removables;
        List.mapi
          (fun i (c : W.Chip.t) ->
            logged c.click (fun () -> Printf.sprintf "remove %d" (i + 1)))
          removables;
        adder.bindings;
        [logged adder.added (fun t -> "added " ^ t)];
        List.concat_map (fun (c : W.Card.t) -> c.bindings) cards;
        List.mapi
          (fun i (c : W.Card.t) ->
            logged c.click (fun () -> Printf.sprintf "card %d" (i + 1)))
          cards;
        grid.bindings;
        [logged grid.tap (fun _ -> "photo tap")];
        List.concat_map (fun (r : W.List_row.t) -> r.bindings) rows;
        List.mapi
          (fun i (r : W.List_row.t) ->
            logged r.click (fun () -> Printf.sprintf "row %d" (i + 1)))
          rows;
        search.bindings;
        [
          logged (React.S.changes search.value) (fun v -> "search " ^ v);
          logged search.action (fun () -> "action Coller un lien");
        ];
        name.bindings;
        [logged (React.S.changes name.value) (fun v -> "name " ^ v)];
        link.bindings;
        [logged link.action (fun () -> "action Coller")];
        List.concat_map (fun (m : W.Mini_map.t) -> m.bindings) mini_maps;
        List.mapi
          (fun i (m : W.Mini_map.t) ->
            logged m.tap (fun () -> Printf.sprintf "mini-map %d" (i + 1)))
          mini_maps;
        bar.bindings;
        [
          logged bar.select (fun t -> "tab " ^ W.Tab_bar.label t);
          logged bar.record (fun () -> "record");
        ];
      ]
  in
  (* The listener's closure keeps [bindings] reachable; see {!Rb}. *)
  let release =
    El.button ~at:[At.type' (Jstr.v "button")] [El.txt' "release"]
  in
  ignore
    (Ev.listen Ev.click
       (fun _ ->
         Rb.release bindings;
         log "released")
       (El.as_target release));
  El.div
    [
      El.h1
        ~at:[cls "t-screen-title"; At.style (Jstr.v "margin-bottom:24px")]
        [El.txt' "Gallery"];
      entry "Icon"
        [
          El.p
            ~at:[At.id (Jstr.v "icons")]
            (List.map (fun i -> W.Icon.el i) W.Icon.all);
        ];
      entry "Chip"
        [
          El.div
            ~at:[cls "chip-row"; At.id (Jstr.v "chips")]
            (List.map (fun ((c : W.Chip.t), _) -> c.el) chips @ [tags.el]);
          El.div
            ~at:
              [
                cls "chip-row";
                At.id (Jstr.v "tag-chips");
                At.style (Jstr.v "margin-top:10px");
              ]
            (W.Chip.tag "Toxique"
            :: List.map (fun (c : W.Chip.t) -> c.el) removables);
        ];
      entry "Adder" [El.div ~at:[At.id (Jstr.v "adder")] [adder.el]];
      entry "Card"
        [
          El.div
            ~at:[cls "card-grid"; At.id (Jstr.v "cards")]
            (List.map (fun (c : W.Card.t) -> c.el) cards);
          El.div
            ~at:[At.style (Jstr.v "margin-top:10px")]
            [
              W.Card.panel
                [
                  El.p ~at:[cls "t-section-label"] [El.txt' "Date"];
                  El.p [El.txt' "Ven. 12 juin 2026 · 14:32"];
                ];
            ];
        ];
      entry "Photo_grid" [El.div ~at:[At.id (Jstr.v "photo-grid")] [grid.el]];
      entry "List_row"
        [
          El.div
            ~at:[At.id (Jstr.v "rows")]
            (List.map (fun (r : W.List_row.t) -> r.el) rows);
        ];
      entry "Text_field"
        [
          search.el;
          El.div ~at:[At.style (Jstr.v "height:10px")] [];
          name.el;
          El.div ~at:[At.style (Jstr.v "height:10px")] [];
          link.el;
        ];
      entry "Mini_map"
        [
          El.div
            ~at:[At.id (Jstr.v "mini-maps")]
            (List.map
               (fun (m : W.Mini_map.t) ->
                 El.div
                   ~at:[At.style (Jstr.v "margin-bottom:10px")]
                   [W.Card.panel [m.el]])
               mini_maps);
        ];
      entry "Tab_bar" [El.div ~at:[At.id (Jstr.v "tabs")] [bar.el]];
      entry "Log" [log_el; release];
    ]
