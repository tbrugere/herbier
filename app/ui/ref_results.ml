open Brr
module Candidate = Herbier_refs.Resolve.Candidate
module Taxon = Herbier_refs.Sources.Gbif.Taxon
module Plant = Herbier_domain.Plant
module RList = ReactiveData.RList
module W = Widgets

type t = {
  el : El.t;
  status : Ref_search.status React.signal;
  bindings : Rb.binding list;
}

let cls c = At.class' (Jstr.v c)
let same (a : Candidate.t) (b : Candidate.t) = Int.equal a.taxon.key b.taxon.key

(* Offline, the rows found stay but their « + » waits (handoff: disabled
   « avec texte explicite »). *)
let status_text ~online = function
  | Ref_search.Blank -> ""
  | Ref_search.Found (_ :: _) -> (
      match online with
      | true -> ""
      | false -> "Hors-ligne : « + » reviendra avec le réseau.")
  | Ref_search.Pending -> "Recherche…"
  | Ref_search.Found [] -> "Aucune espèce trouvée dans GBIF."
  | Ref_search.Offline -> "Recherche indisponible hors-ligne."
  | Ref_search.Failed _ -> "La recherche n'a pas abouti."

let failed = function
  | Ref_search.Failed _ -> true
  | Ref_search.(Blank | Pending | Found _ | Offline) -> false

let meta ~mode ~current ~plants ~action (t : Taxon.t) =
  let here =
    match (action : Ref_pick.action) with
    | Ref_pick.Inert -> Some "Espèce actuelle"
    | Ref_pick.(Open _ | Attach_to _ | Create | Link_this) -> None
  in
  let owner =
    match (mode : Ref_pick.mode) with
    | Ref_pick.Relink ->
        Option.map
          (fun (p : Plant.t) -> "Aussi dans ma collection : " ^ p.display_name)
          (Ref_pick.other_owner ~current ~plants t)
    | Ref_pick.Browse | Ref_pick.Attach -> None
  in
  String.concat " · " (List.filter_map Fun.id [here; t.family; owner])

let round_add label =
  El.button
    ~at:
      [
        At.type' (Jstr.v "button");
        cls "ref-row__add";
        At.v (Jstr.v "aria-label") (Jstr.v label);
      ]
    [W.Icon.el ~size:22 W.Icon.Add]

let action_button = function
  | Ref_pick.Open _ -> Some (W.Button.text "Ouvrir ›").el
  | Ref_pick.Attach_to _ -> Some (W.Button.text "Lier ›").el
  | Ref_pick.Create -> Some (round_add "Créer la fiche")
  | Ref_pick.Link_this -> Some (round_add "Lier à cette espèce")
  | Ref_pick.Inert -> None

let row ~mode ~current ~plants ~online ~online_s ~pick (c : Candidate.t) =
  let action = Ref_pick.action mode ~current ~plants c.taxon in
  let text =
    El.div
      ~at:[cls "ref-row__text"]
      (List.concat
         [
           [
             El.p
               ~at:[cls "ref-row__latin"]
               (El.i [El.txt' (Taxon.latin c.taxon)]
               :: Option.to_list
                    (Option.map
                       (fun a ->
                         El.span ~at:[cls "ref-row__author"] [El.txt' a])
                       c.taxon.authorship));
           ];
           (match List.take 3 c.french with
           | [] -> []
           | names ->
               [
                 El.p
                   ~at:[cls "ref-row__french"]
                   [El.txt' (String.concat ", " names)];
               ]);
           (match meta ~mode ~current ~plants ~action c.taxon with
           | "" -> []
           | m -> [El.p ~at:[cls "t-meta"] [El.txt' m]]);
         ])
  in
  let button =
    match action_button action with
    | Some b -> b
    | None ->
        let b = round_add "Espèce actuelle" in
        El.set_at (Jstr.v "aria-disabled") (Some (Jstr.v "true")) b;
        b
  in
  let el = El.div ~at:[cls "ref-row"] [text; button] in
  El.set_class (Jstr.v "is-current") (Ref_pick.equal_action action Inert) el;
  let click, b = Rb.click button in
  let offline_disabled =
    React.S.map (function true -> None | false -> Some "true") online_s
  in
  ( el,
    b
    :: Rb.act click (fun () ->
        match action with
        | Ref_pick.Inert -> ()
        | Ref_pick.(Open _ | Attach_to _) -> pick action c
        | Ref_pick.(Create | Link_this) -> (
            match online () with true -> pick action c | false -> ()))
    ::
    (match action with
    | Ref_pick.(Create | Link_this) ->
        [Rb.attr button "aria-disabled" offline_disabled]
    | Ref_pick.(Inert | Open _ | Attach_to _) -> []) )

let v app ~mode ~current ~plants ~query ~pick =
  let network = State.network (App.state app) in
  let online () = (React.S.value network).online in
  let online_s =
    React.S.map ~eq:Bool.equal (fun (n : State.network) -> n.online) network
  in
  let first, todo = Ref_search.init ~online:(online ()) (React.S.value query) in
  let search, set_search = React.S.create ~eq:( == ) first in
  (* style: [timer] is the debounce running; [alive] turns false on release,
     so a late answer or timer cannot touch a released screen. *)
  let timer = ref None and alive = ref true in
  let stop_timer () =
    Option.iter G.stop_timer !timer;
    timer := None
  in
  let rec run = function
    | Ref_search.No_effect -> ()
    | Ref_search.Wait {seq; ms} ->
        stop_timer ();
        timer :=
          Some
            (G.set_timeout ~ms (fun () ->
                 timer := None;
                 step (Ref_search.elapsed ~online:(online ()) ~seq)))
    | Ref_search.Fetch {seq; q} ->
        Fut.await (Herbier_refs_io.Resolver.search ~q) (fun result ->
            (match result with
            | Error (Herbier_refs.Resolve.Unavailable why) ->
                Console.(error [str "refs: search"; str why])
            | Ok _ | Error Herbier_refs.Resolve.(No_species | Observation_link)
              ->
                ());
            match !alive with
            | false -> ()
            | true ->
                set_search
                  (Ref_search.answered ~seq result (React.S.value search)))
  and step f =
    match !alive with
    | false -> ()
    | true ->
        let next, todo = f (React.S.value search) in
        set_search next;
        run todo
  in
  run todo;
  let status =
    React.S.map ~eq:Ref_search.equal_status Ref_search.status search
  in
  let rows, rows_handle = RList.create [] in
  (* style: the rows shown, written by the [status] reaction's [act] only. *)
  let shown = ref [] in
  let show = function
    | Ref_search.Found next ->
        Rb.patch rows_handle
          (List_patch.diff ~same ~equal:Candidate.equal !shown next);
        shown := next
    | Ref_search.(Blank | Offline | Failed _) ->
        Rb.patch rows_handle
          (List_patch.diff ~same ~equal:Candidate.equal !shown []);
        shown := []
    | Ref_search.Pending -> ()
  in
  let rows_el = El.div ~at:[cls "ref-results__rows"] [] in
  (* Always rendered, empty when there is nothing to say: a live region
     must be in the accessibility tree before its text changes. *)
  let line =
    El.p
      ~at:
        [
          cls "t-meta";
          cls "ref-results__status";
          At.v (Jstr.v "role") (Jstr.v "status");
        ]
      []
  in
  let retry = W.Button.text "Réessayer" in
  let el =
    El.section
      ~at:[cls "ref-results"]
      [
        El.h2
          ~at:[cls "ref-results__head"]
          [
            El.span ~at:[cls "t-section-label-ref"] [El.txt' "Référence · GBIF"];
            El.span ~at:[cls "t-meta"] [El.txt' "Plantae"];
          ];
        line;
        retry.el;
        rows_el;
      ]
  in
  {
    el;
    status;
    bindings =
      List.concat
        [
          [
            Rb.rlist rows_el
              (row ~mode ~current ~plants ~online ~online_s ~pick)
              rows;
            Rb.act (React.S.changes status) show;
            Rb.act (React.S.changes query) (fun text ->
                step (Ref_search.typed ~online:(online ()) text));
            Rb.act (React.S.changes online_s) (fun online ->
                step (Ref_search.network ~online));
            Rb.act retry.click (fun () ->
                step (Ref_search.retry ~online:(online ())));
            Rb.text line
              (React.S.l2 ~eq:String.equal
                 (fun status online -> status_text ~online status)
                 status online_s);
            Rb.class_ retry.el "is-hidden"
              (React.S.map (fun s -> not (failed s)) status);
            Rb.class_ el "is-offline" (React.S.map not online_s);
            Rb.on_release (fun () ->
                alive := false;
                stop_timer ());
          ];
          retry.bindings;
        ];
  }
