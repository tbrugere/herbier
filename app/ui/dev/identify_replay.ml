open Brr
module Organ = Herbier_identify.Organ
module Plantnet = Herbier_identify.Plantnet
module Transport = Herbier_identify.Transport
module Fixtures = Identify_fixtures
module I = Herbier_ui_model.Identify_settings
module Layer = Herbier_ui_model.Identify.Layer
module Caller = Herbier_ui_model.Identify.Caller
module Ids = Herbier_domain.Ids

type scenario =
  | Never
  | Answer of {status : int; body : string}
  | Not_plant
  | Timeout

(* style: the scenario of the layer last opened; the transport is a module,
   so the buttons hand it the scenario through this ref (one layer at a
   time on the page). *)
let scenario = ref Never
let delay_ms = 1200

let later value =
  let fut, set = Fut.create () in
  ignore (G.set_timeout ~ms:delay_ms (fun () -> set value) : G.timer_id);
  fut

module Replay_transport = struct
  type 'a io = 'a Fut.t

  let return = Fut.return
  let bind = Fut.bind

  type image = Blob.t

  let post_form ~url ~fields:(_ : (string * string) list)
      ~files:(_ : image Transport.file list) =
    match !scenario with
    | Never -> fst (Fut.create ())
    | Timeout -> later (Error Transport.Timeout)
    | Answer {status; body} -> later (Ok {Transport.status; body})
    | Not_plant ->
        later
          (Ok
             {
               Transport.status = 404;
               body =
                 (match Kit.contains ~sub:"no-reject=true" url with
                 | true -> Fixtures.not_plant_no_reject_404
                 | false -> Fixtures.not_plant_404);
             })

  let get ~url:(_ : string) =
    later (Ok {Transport.status = 200; body = Fixtures.projects_fr_200})
end

module Io = Herbier_identify.Make (Replay_transport)

let key = "rejeu"

let gate =
  match I.Key.of_input key with Some k -> I.Ready k | None -> I.No_key

let log_line log line =
  Kit.append log line;
  Console.(log [str line])

(* The plant « Dans ma collection » shows on 6c's first card. *)
let collection () =
  let now = Ptime_clock.now () in
  let gbif =
    match Plantnet.decode_answer Fixtures.two_flower_leaf_200 with
    | Ok {proposals = p :: _; _} -> p.gbif
    | Ok {proposals = []; _} | Error (_ : Plantnet.error) -> None
  in
  let plant =
    {
      (Herbier_domain.Plant.v ~id:(Ids.Plant_id.fresh ()) ~at:now
         "Ma plante (rejeu)")
      with
      gbif_key = gbif;
    }
  in
  let observation () : Herbier_domain.Observation.t =
    {
      id = Ids.Observation_id.fresh ();
      plant_id = Some plant.id;
      at = now;
      position = None;
      place_label = None;
      place_derived = None;
      place_detail = None;
      note = None;
      created_at = now;
      updated_at = now;
      deleted_at = None;
    }
  in
  ([plant], [observation (); observation ()])

let services log ~flora ~set_flora : Screens.Identify.services =
  {
    gate = React.S.const gate;
    flora;
    set_flora =
      (fun f ->
        set_flora f;
        Fut.return ());
    floras =
      (fun ~key ->
        Fut.map
          (fun ({result; line} : _ Herbier_identify.logged) ->
            log_line log ("rejeu: " ^ line);
            Result.map_error (fun e -> App.Plantnet e) result)
          (Io.projects ~key));
    identify =
      (fun ~key ~flora ~no_reject photos ->
        (* The page only makes previews: a stored photo fails as App's
           unreadable one does, rather than being left out. *)
        let rec blobs acc = function
          | [] -> Ok (List.rev acc)
          | ((image : App.image), organ) :: rest -> (
              match image with
              | Preview b -> blobs ((b, organ) :: acc) rest
              | Stored id -> Error (App.Preview_unreadable id))
        in
        match blobs [] photos with
        | Error e -> Fut.return (App.Settled (Error e))
        | Ok blobs ->
            Fut.map
              (fun ({result; line} : _ Herbier_identify.logged) ->
                log_line log ("rejeu: " ^ line);
                App.Settled (Result.map_error (fun e -> App.Plantnet e) result))
              (Io.identify ~key ~flora ~no_reject blobs));
    collection = (fun () -> Fut.return (collection ()));
  }

let outcome_text : Layer.outcome -> string = function
  | Left -> "Left"
  | Chosen p -> "Chosen " ^ p.name
  | None_matches -> "None_matches"

let photo log ~color organ =
  Fut.map
    (function
      | Ok blob -> Some {Screens.Identify.image = App.Preview blob; organ}
      | Error e ->
          log_line log ("photo : " ^ e);
          None)
    (Kit.test_jpeg ~color ())

let colors = ["#2e7d32"; "#6d4c41"; "#1565c0"; "#8e24aa"; "#ef6c00"]
let color i = List.nth colors (i mod List.length colors)

(* [n] test photos, made one after the other; one that fails is logged and
   left out. *)
let shots log n =
  let rec go acc i =
    match i < n with
    | false -> Fut.return (List.rev acc)
    | true ->
        Fut.bind
          (photo log ~color:(color i) Organ.Auto)
          (function Some p -> go (p :: acc) (i + 1) | None -> go acc (i + 1))
  in
  go [] 0

let el () =
  let log = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "log")] [] in
  let page = El.div [] in
  let flora, set_flora =
    React.S.create ~eq:(Option.equal Herbier_store.Settings.equal_flora) None
  in
  let services = services log ~flora ~set_flora:(fun f -> set_flora f) in
  let next_color = ref 1 in
  let add_photo organ =
    incr next_color;
    photo log ~color:(color !next_color) organ
  in
  (* 6k's caller: a free-name plant that is not the synthetic collection
     plant, so that one shows as « Aussi dans ma collection ». *)
  let free_name = Caller.Free_name (Ids.Plant_id.fresh ()) in
  let as_free_name =
    El.input
      ~at:[At.type' (Jstr.v "checkbox"); At.id (Jstr.v "replay-caller")]
      ()
  in
  let caller () =
    match El.prop El.Prop.checked as_free_name with
    | true -> free_name
    | false -> Caller.Observation
  in
  let open_layer ~photos chosen () =
    scenario := chosen;
    let caller = caller () in
    Fut.await (shots log photos) (fun shots ->
        ignore
          (Screens.Identify.open_ ~host:page services ~caller ~add_photo
             ~on_close:(fun outcome photos ->
               log_line log
                 (Printf.sprintf "fermé : %s (%d photo(s))"
                    (outcome_text outcome) (List.length photos)))
             shots
            : Screens.Identify.t))
  in
  let buttons =
    List.map
      (fun (label, photos, chosen) ->
        Kit.action label (open_layer ~photos chosen))
      [
        ("6b envoi", 1, Never);
        ( "6c propositions",
          2,
          Answer {status = 200; body = Fixtures.two_flower_leaf_200} );
        ( "6f incertaines",
          1,
          Answer {status = 200; body = Fixtures.one_auto_200} );
        ("6g aucune plante", 1, Not_plant);
        ("6g injoignable", 1, Timeout);
        ( "6g clé non exposée",
          1,
          Answer {status = 403; body = Fixtures.origin_refused_403} );
        ("6g requête refusée", 1, Answer {status = 413; body = ""});
        ("6g quota", 1, Answer {status = 429; body = ""});
        ( "6g clé refusée",
          1,
          Answer {status = 401; body = Fixtures.invalid_key_401} );
      ]
  in
  El.set_children page
    [
      El.h2 [El.txt' "Couche d'identification (rejeu)"];
      El.label
        ~at:[At.for' (Jstr.v "replay-caller")]
        [as_free_name; El.txt' " Appelant : fiche nom libre (6k)"];
      El.div buttons;
      log;
    ];
  page
