open Brr
module Organ = Herbier_identify.Organ
module Plantnet = Herbier_identify.Plantnet
module Proposal = Herbier_identify.Proposal
module Settings = Herbier_store.Settings
module Db = Herbier_store_io.Db
module I = Herbier_ui_model.Identify_settings
module Caller = Herbier_ui_model.Identify.Caller
module Owned = Herbier_ui_model.Identify.Owned
module Failure = Herbier_ui_model.Identify.Failure
module Layer = Herbier_ui_model.Identify.Layer
module Compare = Herbier_ui_model.Identify.Compare
module Text = Herbier_ui_model.Identify.Text
module W = Widgets

type photo = {image : App.image; organ : Organ.sent}

(* style: a record of closures, not a functor, because the services close over
   the running App.t, its channel and signals, values made at runtime; the dev
   replay page is the second instance. *)
type services = {
  gate : I.gate React.signal;
  flora : Settings.flora option React.signal;
  set_flora : Settings.flora option -> unit Fut.t;
  floras :
    key:string -> (Plantnet.project list, App.identify_error) result Fut.t;
  identify :
    key:string ->
    flora:string ->
    no_reject:bool ->
    (App.image * Organ.sent) list ->
    Herbier_identify.identified App.current Fut.t;
  collection :
    unit ->
    (Herbier_domain.Plant.t list * Herbier_domain.Observation.t list) Fut.t;
}

let services app channel =
  let db = App.db app in
  {
    gate = App.identify_gate app;
    flora = App.plantnet_flora app;
    set_flora =
      (fun f ->
        Fut.map
          (fun (_ : (unit, Db.error) result) -> ())
          (App.set_plantnet_flora app f));
    floras = (fun ~key -> App.floras app ~key);
    identify =
      (fun ~key ~flora ~no_reject photos ->
        App.identify app channel ~key ~flora ~no_reject photos);
    collection =
      (fun () ->
        let open Fut.Syntax in
        let* plants = Db.all db Herbier_store.Plants.list in
        let+ observations = Db.all db Herbier_store.Observations.list in
        match (plants, observations) with
        | Ok plants, Ok observations -> (plants, observations)
        | Error e, (Ok _ | Error _) | Ok _, Error e ->
            Log.db ~scope:"identify" "collection" e;
            ([], []));
  }

(* A photo of the layer, its thumbnail built once (so a re-rendered row moves
   it instead of loading it again), and, for a preview in memory, the object
   URL it is shown through (revoked at close). *)
type shown = {photo : photo; url : Jstr.t option; thumb : El.t}
type menu = No_menu | Organ_menu of int | Flora_menu [@@deriving eq]

type flora_list =
  | Flora_loading
  | Flora_failed of string
  | Flora_choosing of Plantnet.project list

type t = {close : unit -> unit}

let cls = Html.cls
let attr name value = At.v (Jstr.v name) (Jstr.v value)

let txt_el tag classes text =
  El.v (Jstr.v tag) ~at:(List.map cls classes) [El.txt' text]

let error_of_app : App.identify_error -> Failure.error = function
  | Identify_offline -> Not_sent_offline
  | Preview_unreadable (_ : Herbier_domain.Ids.Photo_id.t) -> Preview_unreadable
  | Plantnet e -> Plantnet e

let ready = function
  | I.Ready (_ : I.Key.t) -> true
  | Waiting | No_key | Offline -> false

(* Pairs while both lists last: the layer only ever has as many organs as
   photos, this keeps a mismatch from raising. *)
let rec zip photos organs =
  match (photos, organs) with
  | p :: ps, o :: os -> (p, o) :: zip ps os
  | [], (_ :: _ | []) | _ :: _, [] -> []

let failure_attr : Failure.t -> string = function
  | No_plant _ -> "no_plant"
  | Not_answered -> "not_answered"
  | Offline -> "offline"
  | Used_up -> "used_up"
  | Key_refused -> "key_refused"
  | No_key -> "no_key"
  | Unreadable -> "unreadable"

let phase_attr : Layer.phase -> string = function
  | Sending _ -> "sending"
  | Proposals _ -> "proposals"
  | Failed _ -> "failed"
  | Closed _ -> "closed"

(* My photo's image, for 6c's thumbnails and 6d's top frame: a preview in
   memory through its object URL ([None] without one), a stored one through
   Preview_img. *)
let photo_img ~cls:c (p : photo) url =
  match (p.image, url) with
  | Preview (_ : Blob.t), Some url ->
      Some (El.img ~at:[cls c; At.src url; attr "alt" ""] ())
  | Preview (_ : Blob.t), None -> None
  | Stored id, (Some _ | None) ->
      Some (W.Preview_img.v ~cls:[c] (Herbier_store_io.Files.preview id))

let thumb_el (p : photo) url =
  El.div
    ~at:[cls "identify__thumb"]
    [
      Option.value ~default:(El.span [])
        (photo_img ~cls:"identify__thumb-img" p url);
    ]

(* [aria-disabled] and a click that does nothing while [enabled] is false. *)
let gated ~enabled el click f =
  (match enabled with
  | true -> ()
  | false -> El.set_at (Jstr.v "aria-disabled") (Some (Jstr.v "true")) el);
  Rb.act click (fun () -> match enabled with true -> f () | false -> ())

let control ?label ?(at = []) ~enabled classes children f =
  let el = Html.button ?label ~at classes children in
  let click, b = Rb.click el in
  (el, [b; gated ~enabled el click f])

let button ?(enabled = true) (b : W.Button.t) f =
  (b.el, gated ~enabled b.el b.click f :: b.bindings)

let selected_at selected =
  attr "aria-selected" (match selected with true -> "true" | false -> "false")

(* A part re-rendered on its own: [render] of each value of [s]. *)
let slot render s =
  let el = El.div ~at:[cls "identify__slot"] [] in
  (el, [Rb.view el render s])

let skeleton ~first ~slow =
  let tile i =
    El.div
      ~at:[cls "identify-card__tile"; cls "identify-card__tile--skeleton"]
      (match (first && i = 0, slow) with
      | true, true ->
          [txt_el "span" ["identify__skeleton-label"] Text.skeleton_label]
      | true, false | false, (true | false) -> [])
  in
  El.div
    ~at:[cls "identify-card"; cls "identify-card--skeleton"]
    [
      El.div ~at:[cls "identify-card__tiles"] (List.init Proposal.tiles tile);
      El.div ~at:[cls "identify-card__bar-track"] [];
      El.div
        ~at:[cls "identify-card__lines"]
        [
          El.div ~at:[cls "identify-card__line"] [];
          El.div
            ~at:[cls "identify-card__line"; cls "identify-card__line--short"]
            [];
        ];
    ]

(* A tile is a button opening 6d on its image (on the first one 6c does not
   show, for « +N »). Its [data-tile] finds it again when 6d closes, to give it
   the focus back: the cards may have been rebuilt in between. *)
let tile_key k i = Printf.sprintf "%d-%d" k i

let species_tile ~open_compare k (p : Plantnet.proposal) i
    (image : Plantnet.image) =
  let alt =
    match image.organ with
    | Some o -> p.name ^ ", " ^ Organ.label o
    | None -> p.name
  in
  let more = Proposal.tile_more p i in
  let more_el =
    match more > 0 with
    | true ->
        Option.to_list
          (Option.map
             (txt_el "span" ["identify-card__more"])
             (Proposal.more_label p))
    | false -> []
  in
  let band =
    match Text.tile_organ image.organ with
    | Some label -> [txt_el "span" ["identify-card__band"] label]
    | None -> []
  in
  let tile =
    Html.button
      ~label:(Text.tile_label p image ~more)
      ~at:[attr "data-tile" (tile_key k i)]
      ["identify-card__tile"]
      (El.img
         ~at:
           [
             cls "identify-card__img";
             At.src (Jstr.v image.small);
             attr "alt" alt;
             At.title (Jstr.v (Proposal.credit image));
             attr "loading" "lazy";
           ]
         ()
      :: (more_el @ band))
  in
  (tile, Rb.listen tile Ev.click (fun _ -> open_compare k i))

let card ~caller ~owned ~choose ~open_compare k (p : Plantnet.proposal) =
  let tiles = List.mapi (species_tile ~open_compare k p) (Proposal.closest p) in
  let action = Caller.action caller ~owned:(Option.is_some owned) in
  let button, button_b =
    control ~enabled:true ["identify-card__action"]
      [El.txt' (Text.action action)]
      (fun () -> choose k)
  in
  let latin =
    El.div
      ~at:[cls "identify-card__latin"]
      (El.txt' p.name
      ::
      (match p.author with
      | "" -> []
      | author -> [El.txt' " "; txt_el "span" ["identify-card__author"] author])
      )
  in
  let names =
    match Text.common_names p with
    | Some n -> [txt_el "div" ["identify-card__common"] n]
    | None -> []
  in
  let family =
    match p.family with
    | Some f -> [txt_el "div" ["identify-card__family"] f]
    | None -> []
  in
  let owned_el =
    match owned with
    | Some o ->
        [
          El.div
            ~at:[cls "identify-card__owned"]
            [W.Icon.el ~size:16 W.Icon.Check; El.txt' (Text.owned caller o)];
        ]
    | None -> []
  in
  let bar = El.div ~at:[cls "identify-card__bar"] [] in
  El.set_inline_style (Jstr.v "--bar-width")
    (Jstr.v (Text.bar_width p.score))
    bar;
  ( El.v (Jstr.v "article")
      ~at:[cls "identify-card"; attr "data-score" (Printf.sprintf "%g" p.score)]
      ([
         El.div ~at:[cls "identify-card__tiles"] (List.map fst tiles);
         El.div
           ~at:[cls "identify-card__score"]
           [
             El.div
               ~at:[cls "identify-card__bar-track"; attr "aria-hidden" "true"]
               [bar];
             txt_el "span" ["identify-card__percent"] (Text.percent p.score);
           ];
         El.div
           ~at:[cls "identify-card__names"]
           [
             El.div ~at:[cls "identify-card__text"] ((latin :: names) @ family);
             button;
           ];
       ]
      @ owned_el),
    button_b @ List.map snd tiles )

(* What the photo row, the menus and the label row read: one record per
   change. *)
type view = {layer : Layer.t; photos : shown list; menu : menu; gate : I.gate}

let open_ ~host services ~caller ?note ~add_photo ~on_close photos =
  let shown_of (p : photo) =
    let url =
      match p.image with
      | Preview blob -> Some (Herbier_bindings.Object_url.create blob)
      | Stored (_ : Herbier_domain.Ids.Photo_id.t) -> None
    in
    {photo = p; url; thumb = thumb_el p url}
  in
  (* style: refs for what the layer owns outside the reactive graph (its
     photos' object URLs, its timers, whether it is closed); they live as long
     as the layer. *)
  let shown = ref [] in
  let timers = ref [] in
  let closed = ref false in
  let bindings = ref [] in
  let initial, commands =
    Layer.open_ ~caller
      ~flora:(React.S.value services.flora)
      (List.map (fun (p : photo) -> p.organ) photos)
  in
  (* The photos past the layer's first ones are not sent; they go back to the
     caller as they came. *)
  let kept = List.length initial.organs in
  shown :=
    List.map shown_of (List.filteri (fun i (_ : photo) -> i < kept) photos);
  let extra = List.filteri (fun i (_ : photo) -> i >= kept) photos in
  let layer, set_layer = React.S.create ~eq:Layer.equal initial in
  (* The phase is set in a step of its own, after the layer's: re-rendering
     the body creates slots on [view], and react has no value for a signal
     created on one that the current step has not updated yet. *)
  let phase, set_phase = React.S.create ~eq:Layer.equal_phase initial.phase in
  let photos_s, set_photos = React.S.create ~eq:( == ) !shown in
  let menu, set_menu = React.S.create ~eq:equal_menu No_menu in
  let flora_list, set_flora_list = React.S.create ~eq:( == ) Flora_loading in
  let collection, set_collection = React.S.create ~eq:( == ) None in
  let root =
    El.div
      ~at:
        [
          cls "identify";
          attr "role" "dialog";
          attr "aria-modal" "true";
          attr "aria-labelledby" "identify-title";
        ]
      []
  in
  let overlay = ref None in
  (* 6d, while it is open over 6c. *)
  let compare_layer = ref None in
  let finish outcome =
    match !closed with
    | true -> ()
    | false ->
        closed := true;
        (* Before 6c's own release, and once [closed] is set, so that 6d's
           [on_close] leaves the focus alone. *)
        Option.iter Identify_compare.close !compare_layer;
        List.iter G.stop_timer !timers;
        Rb.release !bindings;
        List.iter
          (fun s -> Option.iter Herbier_bindings.Object_url.revoke s.url)
          !shown;
        El.remove root;
        Option.iter Overlay.remove !overlay;
        let organs = (React.S.value layer).organs in
        on_close outcome
          (List.map
             (fun ((s : shown), organ) -> {s.photo with organ})
             (zip !shown organs)
          @ extra)
  in
  (* Created before [dispatch]: a take for « + <organe> » gives it the focus
     back. *)
  let back =
    Html.button ~label:Text.back_label ["identify__back"]
      [W.Icon.el W.Icon.Arrow_back]
  in
  let refocus () =
    match !closed with true -> () | false -> El.set_has_focus true back
  in
  let rec dispatch event =
    match !closed with
    | true -> ()
    | false ->
        let next, commands = Layer.step (React.S.value layer) event in
        let step = React.Step.create () in
        set_layer ~step next;
        set_menu ~step No_menu;
        set_photos ~step !shown;
        React.Step.execute step;
        set_phase next.phase;
        List.iter run commands
  and run : Layer.command -> unit = function
    | Send {seq; request} -> (
        let answer result = dispatch (Answered {seq; result}) in
        match Failure.of_gate (React.S.value services.gate) with
        | Error e -> answer (Error e)
        | Ok k ->
            Fut.await
              (services.identify ~key:(I.Key.to_string k) ~flora:request.flora
                 ~no_reject:request.no_reject
                 (zip (List.map (fun s -> s.photo.image) !shown) request.organs))
              (function
                | App.Superseded -> ()
                | Settled r -> answer (Result.map_error error_of_app r)))
    | Wait_slow {seq; ms} ->
        timers := G.set_timeout ~ms (fun () -> dispatch (Slow seq)) :: !timers
    | Take_photo organ ->
        (* The focused « Annuler » is hidden when the take ends. *)
        Fut.await (add_photo organ) (function
          | None ->
              dispatch (Photo_added None);
              refocus ()
          | Some (p : photo) -> (
              match !closed with
              | true -> ()
              | false ->
                  (* Appended before the dispatch: the Send it leads to reads
                     [shown]. *)
                  (match Layer.accepts_photo (React.S.value layer) with
                  | true -> shown := !shown @ [shown_of p]
                  | false -> ());
                  dispatch (Photo_added (Some p.organ));
                  refocus ()))
    | Save_flora f -> Fut.await (services.set_flora f) Fun.id
    | Close outcome -> finish outcome
  in
  let ask_floras () =
    match React.S.value services.gate with
    | Waiting | No_key | Offline -> ()
    | Ready k ->
        set_flora_list Flora_loading;
        Fut.await
          (services.floras ~key:(I.Key.to_string k))
          (fun result ->
            match (!closed, result) with
            | true, (Ok _ | Error _) -> ()
            | false, Ok projects -> set_flora_list (Flora_choosing projects)
            | false, Error e ->
                set_flora_list (Flora_failed (App.flora_list_text e)))
  in
  let toggle_menu m =
    match (React.S.value menu, m) with
    | Organ_menu a, Organ_menu b when a = b -> set_menu No_menu
    | Flora_menu, Flora_menu -> set_menu No_menu
    | (No_menu | Organ_menu _), Flora_menu ->
        set_menu Flora_menu;
        ask_floras ()
    | (No_menu | Organ_menu _ | Flora_menu), (Organ_menu _ | No_menu) ->
        set_menu m
  in
  let back_b =
    let click, b = Rb.click back in
    [b; gated ~enabled:true back click (fun () -> dispatch Back)]
  in
  let kicker_cls =
    match caller with
    | Queue _ -> ["identify__kicker"; "identify__kicker--queue"]
    | Noter | Free_name _ -> ["identify__kicker"]
  in
  let header =
    El.div
      ~at:[cls "identify__header"]
      [
        back;
        El.div
          ~at:[cls "identify__heading"]
          [
            txt_el "span" kicker_cls (Text.kicker caller);
            El.h1
              ~at:[cls "identify__title"; At.id (Jstr.v "identify-title")]
              [El.txt' Text.title];
          ];
        El.span [];
      ]
  in
  let body = El.div ~at:[cls "identify__body"] [] in
  let footer = El.div ~at:[cls "identify__footer"] [] in
  let view =
    React.S.l4 ~eq:( == )
      (fun layer photos menu gate -> {layer; photos; menu; gate})
      layer photos_s menu services.gate
  in
  (* The slots reading [view] are all released when the body is re-rendered,
     before the new ones read it: the anchor keeps a strong release from
     stopping it in between. *)
  let view_anchor = Rb.anchor view in
  let photo_row ~organs (v : view) =
    let enabled = ready v.gate in
    let detected = Layer.effective_organs v.layer in
    let photo_els =
      List.mapi
        (fun i s ->
          match (organs, List.nth_opt detected i) with
          | true, Some organ ->
              let badge, badge_b =
                control ~enabled
                  ~at:
                    [
                      attr "aria-haspopup" "listbox";
                      attr "aria-expanded"
                        (match v.menu with
                        | Organ_menu j when j = i -> "true"
                        | Organ_menu _ | No_menu | Flora_menu -> "false");
                    ]
                  ["identify__organ"]
                  [El.txt' (Text.organ_badge organ)]
                  (fun () -> toggle_menu (Organ_menu i))
              in
              (El.div ~at:[cls "identify__photo"] [s.thumb; badge], badge_b)
          | true, None | false, (Some _ | None) ->
              (El.div ~at:[cls "identify__photo"] [s.thumb], []))
        v.photos
    in
    let uncertain =
      match v.layer.phase with
      | Proposals {uncertain; _} -> uncertain
      | Sending _ | Failed _ | Closed _ -> false
    in
    let note =
      match Option.bind note Herbier_domain.Text.non_blank with
      | None -> []
      | Some n -> [(txt_el "p" ["identify__queue-note"] ("« " ^ n ^ " »"), [])]
    in
    let add =
      match Layer.add_tile v.layer with
      | None -> []
      | Some s ->
          let tile, tile_b =
            control ~enabled ~label:(Organ.suggestion_label s)
              ("identify__add"
              ::
              (match uncertain with
              | true -> ["identify__add--strong"]
              | false -> []))
              [W.Icon.el ~size:18 W.Icon.Add; El.txt' (Text.add_word s)]
              (fun () -> dispatch Add)
          in
          (* 6j: the observation's note takes the hint's place, as in the
             artboard. *)
          let hint =
            match (v.layer.phase, note) with
            | Proposals _, [] ->
                [txt_el "span" ["identify__add-hint"] (Text.add_hint s)]
            | Proposals _, _ :: _ | (Sending _ | Failed _ | Closed _), _ -> []
          in
          [(tile, tile_b)] @ List.map (fun h -> (h, [])) hint
    in
    let row = photo_els @ add @ note in
    ( El.div
        ~at:
          (cls "identify__photos"
          ::
          (match uncertain with
          | true -> [cls "identify__photos--uncertain"]
          | false -> []))
        (List.map fst row),
      List.concat_map snd row )
  in
  let organ_menu (v : view) =
    match v.menu with
    | No_menu | Flora_menu -> (El.div [], [])
    | Organ_menu i ->
        let current = List.nth_opt (Layer.effective_organs v.layer) i in
        let options =
          List.map
            (fun organ ->
              let selected =
                match current with
                | Some (Some o) -> Organ.equal o organ
                | Some None | None -> false
              in
              control ~enabled:(ready v.gate)
                ~at:[attr "role" "option"; selected_at selected]
                ["identify__option"]
                [El.txt' (Organ.label organ)]
                (fun () -> dispatch (Set_organ {photo = i; organ})))
            Organ.all
        in
        ( El.div
            ~at:
              [
                cls "identify__menu";
                attr "role" "listbox";
                attr "aria-label" Text.organ_menu_label;
              ]
            (List.map fst options),
          List.concat_map snd options )
  in
  (* Built once per 6c: the search field keeps its text while the rest of the
     layer is re-rendered. *)
  let flora_panel () =
    let field =
      W.Text_field.v ~icon:W.Icon.Search ~placeholder:I.search_placeholder ()
    in
    let list_el = El.div ~at:[cls "identify__flora-list"] [] in
    let line text = txt_el "p" ["identify__flora-line"] text in
    let render (state, query, (v : view)) =
      match state with
      | Flora_loading -> (El.div [line I.loading], [])
      | Flora_failed text ->
          let retry, retry_b =
            button ~enabled:(ready v.gate) (W.Button.text I.retry) ask_floras
          in
          (El.div [line text; retry], retry_b)
      | Flora_choosing projects ->
          let rows =
            I.choices ~current:v.layer.flora projects
            |> I.filter ~query
            |> List.map (fun (c : I.choice) ->
                control ~enabled:(ready v.gate)
                  ~at:[attr "role" "option"; selected_at c.selected]
                  ["identify__option"]
                  [El.txt' (I.flora_detail c.flora)]
                  (fun () -> dispatch (Set_flora c.flora)))
          in
          ( El.div
              ~at:
                [attr "role" "listbox"; attr "aria-label" Text.flora_menu_label]
              (List.map fst rows),
            List.concat_map snd rows )
    in
    let searching =
      React.S.map ~eq:Bool.equal
        (function
          | Flora_choosing _ -> true | Flora_loading | Flora_failed _ -> false)
        flora_list
    in
    let panel = El.div ~at:[cls "identify__flora-panel"] [field.el; list_el] in
    ( panel,
      Rb.class_ panel "is-hidden"
        (React.S.map ~eq:Bool.equal
           (fun m -> not (equal_menu m Flora_menu))
           menu)
      :: Rb.class_ field.el "is-hidden" (React.S.map not searching)
      :: Rb.view list_el render
           (React.S.l3 ~eq:( == )
              (fun s q v -> (s, q, v))
              flora_list field.value view)
      :: field.bindings )
  in
  let label_row ~count ~menu_button (v : view) =
    let flora_text = Text.flora_label v.layer.flora in
    let flora_el, flora_b =
      match menu_button with
      | false -> (txt_el "span" ["identify__flora"] flora_text, [])
      | true ->
          control ~enabled:(ready v.gate)
            ~at:
              [
                attr "aria-haspopup" "listbox";
                attr "aria-expanded"
                  (match v.menu with
                  | Flora_menu -> "true"
                  | No_menu | Organ_menu _ -> "false");
              ]
            ["identify__flora"]
            [El.txt' (flora_text ^ " ▾")]
            (fun () -> toggle_menu Flora_menu)
    in
    ( El.div
        ~at:[cls "identify__label-row"]
        [
          txt_el "span" ["identify__label"] (Text.proposals_label caller ~count);
          flora_el;
        ],
      flora_b )
  in
  let blocked_line gate =
    match Text.reask_blocked gate with
    | Some text -> [txt_el "p" ["identify__blocked"] text]
    | None -> []
  in
  let failure_block f (v : view) =
    let n = List.length v.photos in
    let enabled = ready v.gate in
    let act ?icon ?enabled ~kind label event =
      button ?enabled (W.Button.v ~kind ?icon label) (fun () -> dispatch event)
    in
    let retry =
      match Failure.retry f with
      | true ->
          [act ~icon:W.Icon.Refresh ~enabled ~kind:Primary Text.retry Retry]
      | false -> []
    in
    let after_retry : W.Button.kind =
      match Failure.retry f with true -> Secondary | false -> Primary
    in
    let exits =
      match Caller.retake caller with
      | true ->
          [
            act ~icon:W.Icon.Photo_camera ~kind:after_retry Text.retake Retake;
            act ~kind:Secondary (Text.keep_unnamed ~photos:n) Keep_unnamed;
          ]
      | false -> [act ~kind:Secondary Text.back_label Back]
    in
    let force =
      match f with
      | No_plant {can_force = true} ->
          [
            control ~enabled ["identify__force"]
              [El.txt' Text.force]
              (fun () -> dispatch Force);
          ]
      | No_plant {can_force = false}
      | Not_answered | Offline | Used_up | Key_refused | No_key | Unreadable ->
          []
    in
    (* The line says why a gated control is inert: shown when there is one. *)
    let gated_shown =
      retry <> [] || force <> [] || Option.is_some (Layer.add_tile v.layer)
    in
    let buttons = retry @ exits in
    ( El.div
        ~at:[cls "identify__failure"]
        ([
           El.span ~at:[cls "identify__glyph"] [W.Identify_glyph.el ~size:48 ()];
           txt_el "h2" ["identify__failure-title"] (Text.failure_title f);
           txt_el "p" ["identify__failure-body"] (Text.failure_body ~photos:n f);
         ]
        @ (match gated_shown with true -> blocked_line v.gate | false -> [])
        @ [El.div ~at:[cls "identify__failure-actions"] (List.map fst buttons)]
        @ List.map fst force),
      List.concat_map snd buttons @ List.concat_map snd force )
  in
  let parts els = (El.div (List.map fst els), List.concat_map snd els) in
  let render_body : Layer.phase -> El.t * Rb.binding list = function
    | Closed (_ : Layer.outcome) -> (El.div [], [])
    | Sending {slow} ->
        let photos, photos_b = slot (photo_row ~organs:false) view in
        let label, label_b =
          slot (label_row ~count:None ~menu_button:false) view
        in
        let note = El.p ~at:[cls "identify__note"] [] in
        ( El.div
            [
              El.div
                ~at:[cls "identify__sending"]
                [
                  photos;
                  El.div
                    ~at:[cls "identify__status-block"]
                    [txt_el "p" ["identify__status"] Text.sending; note];
                ];
              label;
              El.div
                ~at:[cls "identify__cards"; attr "aria-busy" "true"]
                (List.init 3 (fun i -> skeleton ~first:(i = 0) ~slow));
            ],
          Rb.text note
            (React.S.map
               (fun l -> Text.not_kept ~photos:(List.length l))
               photos_s)
          :: (photos_b @ label_b) )
    | Proposals i ->
        let owned (p : Plantnet.proposal) = function
          | None -> None
          | Some (plants, observations) ->
              Owned.find ~current:(Caller.current caller) ~plants ~observations
                p.gbif
        in
        let open_compare k tile_index =
          Option.iter Identify_compare.close !compare_layer;
          match
            Compare.open_ ~proposals:i.answer.proposals
              ~mine:(Layer.effective_organs (React.S.value layer))
              ~proposal:k ~tile:tile_index
          with
          | None -> ()
          | Some c ->
              let photos =
                List.map
                  (fun (s : shown) ~cls -> photo_img ~cls s.photo s.url)
                  !shown
              in
              let focus_back () =
                let tile =
                  El.find_first_by_selector ~root
                    (Jstr.v
                       (Printf.sprintf "[data-tile=\"%s\"]"
                          (tile_key k tile_index)))
                in
                El.set_has_focus true (Option.value ~default:back tile)
              in
              compare_layer :=
                Some
                  (Identify_compare.open_ ~host:root ~caller
                     ~owned:
                       (React.S.map ~eq:( == )
                          (fun c p -> owned p c)
                          collection)
                     ~choose:(fun k -> dispatch (Choose k))
                     ~on_close:(fun () ->
                       compare_layer := None;
                       match !closed with true -> () | false -> focus_back ())
                     ~photos c)
        in
        let cards c =
          let cards =
            List.mapi
              (fun k p ->
                card ~caller ~owned:(owned p c)
                  ~choose:(fun k -> dispatch (Choose k))
                  ~open_compare k p)
              i.answer.proposals
          in
          ( El.div ~at:[cls "identify__cards"] (List.map fst cards),
            List.concat_map snd cards )
        in
        let blocked gate = (El.div (blocked_line gate), []) in
        parts
          [
            slot (photo_row ~organs:true) view;
            slot organ_menu view;
            slot blocked services.gate;
            slot
              (label_row
                 ~count:(Some (List.length i.answer.proposals))
                 ~menu_button:true)
              view;
            flora_panel ();
            slot cards collection;
          ]
    | Failed f ->
        parts [slot (photo_row ~organs:false) view; slot (failure_block f) view]
  in
  let render_footer : Layer.phase -> El.t * Rb.binding list = function
    | Sending _ ->
        let el, bs =
          button (W.Button.v ~kind:Secondary Text.continue_) (fun () ->
              dispatch Back)
        in
        (El.div [el], bs)
    | Proposals _ ->
        let el, bs =
          button (W.Button.v ~kind:Secondary Text.none_matches) (fun () ->
              dispatch None_matches)
        in
        (El.div [el], bs)
    | Failed _ | Closed _ -> (El.div [], [])
  in
  let footer_shown =
    React.S.map ~eq:Bool.equal
      (function
        | Layer.Sending _ | Proposals _ -> true | Failed _ | Closed _ -> false)
      phase
  in
  El.set_children root [header; body; footer];
  bindings :=
    back_b
    @ [
        Rb.on_release (fun () -> ignore (view_anchor : Rb.anchor));
        Rb.view body render_body phase;
        (* 6d shows the answer it was opened on: a new phase closes it, so
           that its « Choisir » never picks from another answer. *)
        Rb.act (React.S.changes phase) (fun (_ : Layer.phase) ->
            Option.iter Identify_compare.close !compare_layer);
        Rb.view footer render_footer phase;
        Rb.class_ footer "is-hidden" (React.S.map not footer_shown);
        Rb.attr root "data-phase"
          (React.S.map (fun p -> Some (phase_attr p)) phase);
        Rb.attr root "data-failure"
          (React.S.map
             (function
               | Layer.Failed f -> Some (failure_attr f)
               | Sending _ | Proposals _ | Closed _ -> None)
             phase);
        Rb.class_ root "identify--uncertain"
          (React.S.map
             (function
               | Layer.Proposals {uncertain; _} -> uncertain
               | Sending _ | Failed _ | Closed _ -> false)
             phase);
      ];
  Rb.hold root !bindings;
  El.append_children host [root];
  El.set_has_focus true back;
  let t = {close = (fun () -> finish Left)} in
  overlay := Some (Overlay.push ~surface:Light ~close:t.close);
  Fut.await (services.collection ()) (fun c ->
      match !closed with true -> () | false -> set_collection (Some c));
  List.iter run commands;
  t

let close t = t.close ()

let gallery_adder app o ~problem =
  (* style: whether a pick runs, read and written from future callbacks only. *)
  let adding = ref false in
  fun organ ->
    match !adding with
    | true -> Fut.return None
    | false -> (
        adding := true;
        let ended ?problem:met photo =
          adding := false;
          Option.iter problem met;
          photo
        in
        let open Fut.Syntax in
        let* picked = Herbier_photos_io.Capture.pick ~limit:1 in
        match picked with
        | Ok [] -> Fut.return (ended None)
        | Error (Herbier_photos_io.Capture.Pick c) ->
            Log.cap ~scope:"identifier" "gallery" c;
            Fut.return (ended None)
        | Error e ->
            Log.error ~scope:"identifier" "gallery"
              (Herbier_photos_io.Capture.error_to_string e);
            Fut.return (ended ~problem:"La photo n'a pas pu être lue." None)
        | Ok (shot :: (_ : Herbier_photos_io.Capture.shot list)) -> (
            let+ unsaved = App.save_photos app ~observation:o [shot] in
            match unsaved with
            | [] -> ended (Some {image = App.Preview shot.preview.jpeg; organ})
            | (_ : Herbier_photos_io.Capture.shot) :: _ ->
                Log.error ~scope:"identifier" "photo not saved"
                  "for the identification";
                ended ~problem:"La photo n'a pas pu être enregistrée." None))

(* style: the open layer and whether the caller's block is released, read and
   written from DOM and future callbacks only, never shown. *)
type launcher = {
  button : El.t;
  problem : string -> unit;
  layer : t option ref;
  released : bool ref;
}

let launcher ~button ~problem =
  {button; problem; layer = ref None; released = ref false}

let is_open l = Option.is_some !(l.layer)
let released l = !(l.released)

let launch l ~on_resolve open_layer =
  match !(l.layer) with
  | Some (_ : t) -> ()
  | None ->
      (* style: a problem met while this opening covers the caller, and
         whether it closed, written from DOM and future callbacks only. *)
      let pending = ref None and closed = ref false in
      let problem m =
        match (!closed, !(l.released)) with
        | false, (true | false) -> pending := Some m
        | true, false -> l.problem m
        | true, true -> ()
      in
      let on_close outcome (_ : photo list) =
        closed := true;
        l.layer := None;
        match (!(l.released), Layer.after_close outcome) with
        | true, (Stay | Resolve _) -> ()
        | false, Stay ->
            Option.iter l.problem !pending;
            El.set_has_focus true l.button
        | false, Resolve p ->
            Option.iter l.problem !pending;
            El.set_has_focus true l.button;
            on_resolve p
      in
      l.layer := Some (open_layer ~problem ~on_close)

let release l =
  Rb.on_release (fun () ->
      l.released := true;
      Option.iter close !(l.layer))
