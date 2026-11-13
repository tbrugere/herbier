module Place_name = Herbier_geo.Place_name
module Communes = Herbier_geo.Communes
module Commune_packs = Herbier_geo_io.Commune_packs
module Pack_rows = Herbier_store.Commune_packs
module Code = Communes.Code
module Fut_result = Herbier_bindings.Fut_result

let packs (t : Core.t) = t.packs
let downloading (t : Core.t) = t.downloading

type pack_error = Busy | Offline | Pack of Commune_packs.error

let pack_error_to_string = function
  | Busy -> "Un téléchargement est déjà en cours."
  | Offline
  | Pack (Commune_packs.Fetch Herbier_geo_io.Geocoder.(Network _ | Timeout)) ->
      "Hors ligne : réessayez une fois connecté."
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

let download_pack (t : Core.t) (d : Communes.departement) =
  match React.S.value t.downloading with
  | Some (_ : Communes.departement) -> Fut.return (Error Busy)
  | None ->
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
              (match
                 (React.S.value (State.place_sources t.state)).ign_offline
               with
              | false ->
                  Geocoding.set_place_source t Place_name.Ign_offline true
              | true -> Geocoding.geocode_pending t);
              Ok ())
        (* Wait for the startup load: it replaces the index and [packs]
           wholesale, so a download finished before it would be lost. *)
        (Fut.bind t.communes_loaded (fun () ->
             Commune_packs.download t.db ~now:(Ptime_clock.now ()) d))

let delete_pack (t : Core.t) code =
  match React.S.value t.downloading with
  | Some (d : Communes.departement) when Code.equal d.code code ->
      Fut.return (Error Busy)
  | Some _ | None ->
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
