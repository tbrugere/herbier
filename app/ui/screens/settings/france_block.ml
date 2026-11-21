open Brr
module France_text = Herbier_ui_model.France_text
module Pack_text = Herbier_ui_model.Pack_text
module France_packs = Herbier_geo.France_packs
module Communes = Herbier_geo.Communes
module W = Widgets

let cls = Html.cls

type t = {
  summary : El.t list;
  expanded : bool React.signal;
  button : El.t;
  after : El.t list;
  running : bool React.signal;
  busy : bool React.signal;
  locked : bool React.signal;
  bindings : Rb.binding list;
}

type panel =
  | Closed
  | Loading
  | Plan_failed of string
  | Confirm of {plan : France_packs.plan; cellular : bool}

type delete = Delete_closed | Delete_asking | Deleting

let panel_id = "france-panel"
let packs_id = "packs"
let line text = El.p ~at:[cls "t-meta"; cls "settings__intro"] [El.txt' text]

(* Always rendered, empty when nothing runs: a live region must be in the
   accessibility tree before its text changes. *)
let status_line () =
  El.p
    ~at:
      [
        cls "t-meta";
        cls "settings__intro";
        cls "france-status";
        At.v (Jstr.v "role") (Jstr.v "status");
      ]
    []

let title (d : Communes.departement) =
  Pack_text.title ~code:(Communes.Code.to_string d.code) ~name:d.name

let total_bytes packs =
  List.fold_left (fun acc (p : App.pack) -> acc + p.row.size_bytes) 0 packs

let retry_reason (e : App.pack_error) : France_text.retry_reason =
  match App.france_cause e with
  | Network -> Connection_lost
  | Timeout -> Timed_out
  | Not_json | Bad_payload -> Bad_answer
  | Status (_ : int) | Refused | Local -> Unavailable

let run_text : App.france -> string option = function
  | France_idle | France_deleting -> None
  | France_starting -> Some France_text.loading
  | France_running {cancelling = true; step = _} -> Some France_text.cancelling
  | France_running {cancelling = false; step = Downloading (p, d)} ->
      Some
        (France_text.progress ~position:(France_packs.position p)
           ~total:p.plan.total ~bytes:p.bytes ~estimate:p.plan.estimate_bytes
           ~current:(Some d.name))
  | France_running
      {
        cancelling = false;
        step = Retrying {departement; attempt; attempts; wait_ms; error; _};
      } ->
      Some
        (France_text.retrying ~current:departement.name
           ~reason:(retry_reason error) ~attempt ~attempts ~wait_ms)
  | France_finished (Complete p) ->
      Some
        (France_text.complete ~downloaded:p.downloaded ~bytes:p.bytes
           ~failed:
             (List.map (fun (d, (_ : App.pack_error)) -> title d) p.failed))
  | France_finished (Cancelled p) ->
      Some
        (France_text.cancelled ~position:(France_packs.position p)
           ~total:p.plan.total)
  | France_finished (Stopped (p, e)) ->
      Some
        (France_text.stopped ~position:(France_packs.position p)
           ~total:p.plan.total
           ~reason:(App.pack_error_to_string e))

let progress_of : App.france -> (int * int) option = function
  | France_running {step; _} ->
      let p = France_packs.step_progress step in
      Some (France_packs.position p, p.plan.total)
  | France_idle | France_starting | France_finished _ | France_deleting -> None

let v app ~set_message =
  let france = App.france app in
  let running = React.S.map ~eq:Bool.equal App.is_running france in
  let locked = React.S.map ~eq:Bool.equal App.is_busy france in
  let busy =
    React.S.l2 ~eq:Bool.equal
      (fun d locked -> Option.is_some d || locked)
      (App.downloading app) locked
  in
  let panel, set_panel = React.S.create ~eq:( == ) Closed in
  let set_panel p = set_panel p in
  let delete, set_delete = React.S.create ~eq:( == ) Delete_closed in
  let set_delete d = set_delete d in
  (* The outcome line stays until the next tap: [shown] hides it then. *)
  let shown, set_shown = React.S.create ~eq:Bool.equal true in
  let set_shown b = set_shown b in
  let button = W.Button.text France_text.button in
  (* A plan's answer counts only while its « Chargement… » is still shown. *)
  let planned p =
    match React.S.value panel with
    | Loading -> set_panel p
    | Closed | Plan_failed _ | Confirm _ -> ()
  in
  let open_panel () =
    match (React.S.value busy, React.S.value panel) with
    | true, _ | false, Loading -> ()
    | false, (Plan_failed _ | Confirm _) -> set_panel Closed
    | false, Closed ->
        set_message None;
        set_shown false;
        set_panel Loading;
        Fut.await
          (Fut.pair (App.france_plan app) (App.connection app))
          (function
            | ( Ok {France_packs.total = 0; _},
                (_ : Herbier_bindings.Cap_network.connection) ) ->
                planned (Plan_failed France_text.no_departements)
            | Ok plan, connection ->
                planned
                  (Confirm
                     {
                       plan;
                       cellular =
                         (match connection with
                         | Herbier_bindings.Cap_network.Cellular -> true
                         | Wifi | No_connection | Unknown -> false);
                     })
            | Error e, (_ : Herbier_bindings.Cap_network.connection) ->
                planned (Plan_failed (App.pack_error_to_string e)))
  in
  let start plan =
    set_panel Closed;
    set_shown true;
    Fut.await (App.download_france app plan) (function
      | Ok (_ : App.pack_error France_packs.outcome) -> ()
      | Error e -> set_message (Some (App.pack_error_to_string e)))
  in
  let render_panel = function
    | Closed -> (El.div [], [])
    | Loading -> (El.div [line France_text.loading], [])
    | Plan_failed text ->
        let retry = W.Button.text France_text.retry in
        ( El.div [line text; El.div ~at:[cls "settings__row"] [retry.el]],
          Rb.act retry.click (fun () ->
              set_panel Closed;
              open_panel ())
          :: retry.bindings )
    | Confirm {plan; cellular} ->
        let todo = List.length plan.todo in
        let go = W.Button.text France_text.start in
        let dismiss = W.Button.text ~tone:`Ink France_text.dismiss in
        let warning =
          match
            France_text.warn_mobile ~cellular ~bytes:plan.transfer_bytes
          with
          | true ->
              [line (France_text.mobile_warning ~bytes:plan.transfer_bytes)]
          | false -> []
        in
        let buttons =
          match todo with 0 -> [dismiss.el] | _ -> [go.el; dismiss.el]
        in
        ( El.div
            ~at:[cls "france-panel"]
            ([
               line (France_text.scope ~total:plan.total);
               line
                 (France_text.estimate ~total:plan.total ~todo
                    ~bytes:plan.estimate_bytes);
               line France_text.background_note;
             ]
            @ warning
            @ [El.div ~at:[cls "settings__row"] buttons]),
          Rb.act go.click (fun () -> start plan)
          :: Rb.act dismiss.click (fun () -> set_panel Closed)
          :: go.bindings
          @ dismiss.bindings )
  in
  let panel_el =
    El.div ~at:[cls "france-panel__holder"; At.id (Jstr.v panel_id)] []
  in
  let summary_text = El.span ~at:[cls "t-meta"] [] in
  let toggle =
    Html.button
      ~at:[At.v (Jstr.v "aria-controls") (Jstr.v packs_id)]
      ["france-summary__toggle"]
      [summary_text; W.Icon.el ~size:20 W.Icon.Chevron_right]
  in
  let expanded, set_expanded = React.S.create ~eq:Bool.equal false in
  let set_expanded b = set_expanded b in
  let delete_all = W.Button.text ~tone:`Danger France_text.delete_all in
  let summary_row =
    El.div
      ~at:[cls "settings__row"; cls "france-summary"]
      [toggle; delete_all.el]
  in
  let confirm_el = El.div ~at:[cls "france-panel__holder"] [] in
  let do_delete () =
    set_delete Deleting;
    Fut.await (App.delete_all_packs app) (fun r ->
        set_delete Delete_closed;
        match r with
        | Ok () -> ()
        | Error e -> set_message (Some (App.pack_error_to_string e)))
  in
  let confirm_panel ~deleting packs =
    let yes = W.Button.text ~tone:`Danger France_text.delete_all in
    let no = W.Button.text ~tone:`Ink France_text.dismiss in
    ( El.div
        ~at:[cls "france-panel"]
        [
          line
            (France_text.delete_all_question ~count:(List.length packs)
               ~bytes:(total_bytes packs));
          line France_text.delete_all_note;
          El.div ~at:[cls "settings__row"] [yes.el; no.el];
        ],
      Rb.disabled yes.el (React.S.const deleting)
      :: Rb.disabled no.el (React.S.const deleting)
      :: Rb.act yes.click do_delete
      :: Rb.act no.click (fun () -> set_delete Delete_closed)
      :: yes.bindings
      @ no.bindings )
  in
  let render_confirm = function
    | Delete_closed, (_ : App.pack list) -> (El.div [], [])
    | Delete_asking, packs -> confirm_panel ~deleting:false packs
    | Deleting, packs -> confirm_panel ~deleting:true packs
  in
  let bar =
    El.v (Jstr.v "progress")
      ~at:
        [
          cls "france-progress";
          At.v (Jstr.v "aria-label") (Jstr.v France_text.button);
        ]
      []
  in
  let status = status_line () in
  let interrupt = W.Button.text ~tone:`Ink France_text.interrupt in
  let interrupt_row = El.div ~at:[cls "settings__row"] [interrupt.el] in
  let text =
    React.S.l2
      ~eq:(Option.equal String.equal)
      (fun (f : App.france) shown ->
        match (f, shown) with
        | France_finished _, true -> run_text f
        | France_finished _, false -> None
        | ( (France_idle | France_starting | France_running _ | France_deleting),
            _ ) ->
            run_text f)
      france shown
  in
  let progress = React.S.map ~eq:(Option.equal ( = )) progress_of france in
  let cancelling =
    React.S.map ~eq:Bool.equal
      (function
        | App.France_running {cancelling; _} -> cancelling
        | France_starting | France_idle | France_finished _ | France_deleting ->
            false)
      france
  in
  let hidden_unless s =
    React.S.map (function true -> None | false -> Some "") s
  in
  let has_packs =
    React.S.map ~eq:Bool.equal (fun l -> l <> []) (App.packs app)
  in
  El.set_at (Jstr.v "aria-controls") (Some (Jstr.v panel_id)) button.el;
  let bindings =
    [
      Rb.view panel_el render_panel panel;
      Rb.view confirm_el render_confirm
        (React.S.l2 ~eq:( == ) (fun d p -> (d, p)) delete (App.packs app));
      Rb.text summary_text
        (React.S.map
           (fun packs ->
             France_text.summary ~count:(List.length packs)
               ~bytes:(total_bytes packs))
           (App.packs app));
      Rb.attr summary_row "hidden" (hidden_unless has_packs);
      Rb.attr toggle "aria-expanded"
        (React.S.map (fun b -> Some (Bool.to_string b)) expanded);
      Rb.listen toggle Ev.click (fun _ ->
          set_expanded (not (React.S.value expanded)));
      Rb.disabled delete_all.el busy;
      Rb.act delete_all.click (fun () ->
          match (React.S.value busy, React.S.value delete) with
          | true, _ | false, Deleting -> ()
          | false, Delete_asking -> set_delete Delete_closed
          | false, Delete_closed ->
              set_message None;
              set_shown false;
              set_delete Delete_asking);
      Rb.disabled button.el busy;
      Rb.attr button.el "aria-expanded"
        (React.S.map
           (function
             | Closed -> Some "false"
             | Loading | Plan_failed _ | Confirm _ -> Some "true")
           panel);
      Rb.act button.click open_panel;
      Rb.attr bar "max"
        (React.S.map
           (Option.map (fun (_, total) -> string_of_int total))
           progress);
      Rb.attr bar "value"
        (React.S.map (Option.map (fun (n, _) -> string_of_int n)) progress);
      Rb.attr bar "hidden"
        (hidden_unless (React.S.map ~eq:Bool.equal Option.is_some progress));
      Rb.text status (React.S.map (Option.value ~default:"") text);
      Rb.attr interrupt_row "hidden" (hidden_unless running);
      Rb.disabled interrupt.el cancelling;
      Rb.act interrupt.click (fun () -> App.cancel_france app);
    ]
    @ button.bindings
    @ delete_all.bindings
    @ interrupt.bindings
  in
  {
    summary = [summary_row; confirm_el];
    expanded;
    button = button.el;
    after = [panel_el; bar; status; interrupt_row];
    running;
    busy;
    locked;
    bindings;
  }
