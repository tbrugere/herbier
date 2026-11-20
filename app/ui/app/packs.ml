module Place_name = Herbier_geo.Place_name
module Communes = Herbier_geo.Communes
module Commune_packs = Herbier_geo_io.Commune_packs
module Pack_rows = Herbier_store.Commune_packs
module Code = Communes.Code
module Fut_result = Herbier_bindings.Fut_result
module France_packs = Herbier_geo.France_packs
module Cap_network = Herbier_bindings.Cap_network

let packs (t : Core.t) = t.packs
let downloading (t : Core.t) = t.downloading

type pack_error = Core.pack_error =
  | Busy
  | Offline
  | Pack of Commune_packs.error

let pack_error_to_string = function
  | Busy -> "Un téléchargement est déjà en cours."
  | Offline
  | Pack (Commune_packs.Fetch Herbier_geo_io.Geocoder.(Network _ | Timeout)) ->
      "Hors-ligne : réessayez une fois connecté."
  | Pack (Commune_packs.Fetch (Herbier_geo_io.Geocoder.Refused _)) ->
      "Téléchargement non envoyé. Réessayez."
  | Pack (Commune_packs.Fetch (Herbier_geo_io.Geocoder.Status _ as e))
    when Herbier_geo_io.Geocoder.transient e ->
      "Service de l’IGN indisponible : réessayez plus tard."
  | Pack (Commune_packs.Fetch Herbier_geo_io.Geocoder.(Payload _ | Status _)) ->
      "Réponse de l’IGN inattendue."
  | Pack (Commune_packs.File _ | Commune_packs.Store _) ->
      "Enregistrement impossible."

let departements (t : Core.t) =
  match Core.online t with
  | false -> Fut.return (Error Offline)
  | true ->
      Fut_result.map_error (fun e -> Pack e) (Commune_packs.departements ())

let without_pack code =
  List.filter (fun (p : Core.pack) -> not (Code.equal p.code code))

type france = Core.france =
  | France_idle
  | France_starting
  | France_running of {step : pack_error France_packs.step; cancelling : bool}
  | France_finished of pack_error France_packs.outcome
  | France_deleting

let is_running = function
  | France_starting | France_running _ -> true
  | France_idle | France_finished _ | France_deleting -> false

let is_busy = function
  | France_starting | France_running _ | France_deleting -> true
  | France_idle | France_finished _ -> false

let france_busy (t : Core.t) = is_busy (React.S.value t.france)

(* One département through the single-département download, after the
   caller's [Busy] check:
   [downloading] set, the startup load awaited, the file and row written, the
   index and [packs] updated, the switch turned on at the first success. *)
let download_one (t : Core.t) (d : Communes.departement) =
  t.set_downloading (Some d);
  Fut.map
    (function
      | Error e ->
          Core.log_error
            [
              "communes: download";
              Code.to_string d.code;
              Commune_packs.error_to_string e;
            ];
          t.set_downloading None;
          Error (Pack e)
      | Ok ((row : Pack_rows.t), pack) ->
          t.communes := Communes.add !(t.communes) pack;
          let packs =
            List.sort
              (fun (a : Core.pack) (b : Core.pack) ->
                Code.compare a.code b.code)
              ({code = d.code; row; usable = true}
              :: without_pack d.code (React.S.value t.packs))
          in
          let step = React.Step.create () in
          t.set_packs ~step packs;
          t.set_downloading ~step None;
          React.Step.execute step;
          Core.log ["communes: downloaded"; Code.to_string d.code];
          (* Downloading a département is choosing this source. *)
          (match (React.S.value (State.place_sources t.state)).ign_offline with
          | false -> Geocoding.set_place_source t Place_name.Ign_offline true
          | true -> Geocoding.geocode_pending t);
          Ok row)
    (* Wait for the startup load: it replaces the index and [packs]
       wholesale, so a download finished before it would be lost. *)
    (Fut.bind t.communes_loaded (fun () ->
         Commune_packs.download t.db ~now:(Ptime_clock.now ()) d))

let download_pack (t : Core.t) (d : Communes.departement) =
  match (React.S.value t.downloading, france_busy t) with
  | Some (_ : Communes.departement), _ | None, true -> Fut.return (Error Busy)
  | None, false ->
      Fut.map (Result.map (fun (_ : Pack_rows.t) -> ())) (download_one t d)

let delete_one (t : Core.t) code =
  Fut.map
    (function
      | Error e ->
          Core.log_error
            [
              "communes: delete";
              Code.to_string code;
              Commune_packs.error_to_string e;
            ];
          Error (Pack e)
      | Ok () ->
          t.communes := Communes.remove !(t.communes) code;
          t.set_packs (without_pack code (React.S.value t.packs));
          Ok ())
    (Commune_packs.delete t.db code)

let delete_pack (t : Core.t) code =
  match (React.S.value t.downloading, france_busy t) with
  | _, true -> Fut.return (Error Busy)
  | Some (d : Communes.departement), false when Code.equal d.code code ->
      Fut.return (Error Busy)
  | Some _, false | None, false -> delete_one t code

let france (t : Core.t) = t.france

let usable_codes (t : Core.t) =
  List.filter_map
    (fun (p : Core.pack) ->
      match p.usable with true -> Some p.code | false -> None)
    (React.S.value t.packs)

let france_plan ?only (t : Core.t) =
  match (React.S.value t.downloading, france_busy t) with
  | Some (_ : Communes.departement), _ | None, true -> Fut.return (Error Busy)
  | None, false ->
      let open Fut.Result_syntax in
      let* list = departements t in
      let+ () = Fut.map Result.ok t.communes_loaded in
      France_packs.plan ?only ~downloaded:(usable_codes t) list

let connection (_ : Core.t) =
  Fut.map
    (function
      | Ok (s : Cap_network.status) -> s.connection
      | Error e ->
          Core.log_error ["network:"; Herbier_bindings.Cap_error.to_string e];
          Cap_network.Unknown)
    (Cap_network.status ())

let france_cause : pack_error -> France_packs.cause = function
  | Offline | Busy | Pack (Commune_packs.File _ | Commune_packs.Store _) ->
      Local
  | Pack (Commune_packs.Fetch (Network _)) -> Network
  | Pack (Commune_packs.Fetch Timeout) -> Timeout
  | Pack (Commune_packs.Fetch (Status {status; provider = _})) -> Status status
  | Pack (Commune_packs.Fetch (Payload (Herbier_geo.Geocode.Not_json _))) ->
      Not_json
  | Pack (Commune_packs.Fetch (Payload (Herbier_geo.Geocode.Unexpected _))) ->
      Bad_payload
  | Pack (Commune_packs.Fetch (Refused _)) -> Refused

let france_failure e = France_packs.failure_of_cause (france_cause e)

(* A backoff wait, ended early by [cancel_france] through [france_wake]. *)
let sleep (t : Core.t) ~ms =
  let fut, set = Fut.create () in
  (* style: local, the timer and a cancel may both end the wait; the future is
     set once. *)
  let pending = ref true in
  let wake () =
    match !pending with
    | false -> ()
    | true ->
        pending := false;
        t.france_wake := None;
        set ()
  in
  t.france_wake := Some wake;
  let (_ : Brr.G.timer_id) = Brr.G.set_timeout ~ms wake in
  fut

module Run = France_packs.Make (struct
  type 'a io = 'a Fut.t

  let return = Fut.return
  let bind = Fut.bind

  type ctx = Core.t
  type error = pack_error

  let download t d =
    match Core.online t with
    | false -> Fut.return (Error Offline)
    | true ->
        Fut.map
          (Result.map (fun (row : Pack_rows.t) -> row.size_bytes))
          (download_one t d)

  let classify = france_failure
  let sleep = sleep
  let cancelled (t : Core.t) = !(t.france_cancel)

  let report (t : Core.t) step =
    t.set_france (France_running {step; cancelling = !(t.france_cancel)})
end)

let outcome_log (o : pack_error France_packs.outcome) =
  let line word (p : pack_error France_packs.progress) =
    [
      "communes: france";
      word;
      Printf.sprintf "%d/%d" (France_packs.position p) p.plan.total;
      string_of_int p.bytes;
    ]
  in
  match o with
  | Complete p -> line "complete" p
  | Cancelled p -> line "cancelled" p
  | Stopped (p, e) -> line "stopped" p @ [pack_error_to_string e]

let download_france (t : Core.t) (plan : France_packs.plan) =
  match (React.S.value t.downloading, france_busy t, Core.online t) with
  | Some (_ : Communes.departement), _, _ | None, true, _ ->
      Fut.return (Error Busy)
  | None, false, false -> Fut.return (Error Offline)
  | None, false, true ->
      t.france_cancel := false;
      t.set_france France_starting;
      (* The packs present now: one downloaded since the plan was shown is
         skipped. *)
      Fut.bind t.communes_loaded (fun () ->
          Fut.map
            (fun outcome ->
              t.set_france (France_finished outcome);
              Core.log (outcome_log outcome);
              Ok outcome)
            (Run.run t
               (France_packs.plan ~downloaded:(usable_codes t) plan.departements)))

let cancel_france (t : Core.t) =
  match React.S.value t.france with
  | France_idle | France_finished _ | France_deleting -> ()
  (* Unreachable by a tap: a plan exists only once the startup load ended, so
     the run reports its first step in the same tick. *)
  | France_starting -> t.france_cancel := true
  | France_running {step; cancelling = _} ->
      t.france_cancel := true;
      t.set_france (France_running {step; cancelling = true});
      Option.iter (fun wake -> wake ()) !(t.france_wake)

let delete_all_packs (t : Core.t) =
  match (React.S.value t.downloading, france_busy t) with
  | Some (_ : Communes.departement), _ | None, true -> Fut.return (Error Busy)
  | None, false ->
      t.set_france France_deleting;
      let rec go = function
        | [] -> Fut.return (Ok ())
        | (p : Core.pack) :: rest ->
            let open Fut.Result_syntax in
            let* () = delete_one t p.code in
            go rest
      in
      Fut.map
        (fun r ->
          t.set_france France_idle;
          r)
        (go (React.S.value t.packs))
