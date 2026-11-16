module Identify = Herbier_identify
module Plantnet = Herbier_identify.Plantnet
module Identify_io = Herbier_identify.Make (Plantnet_transport)
module Files = Herbier_store_io.Files
module Cap_error = Herbier_bindings.Cap_error
module Photo_id = Herbier_domain.Ids.Photo_id

type image = Preview of Brr.Blob.t | Stored of Photo_id.t

(* style: mutable because an answer settles in a future's callback and is
   checked then against the caller's latest request: the channel's
   generation. *)
type channel = int ref

let channel () = ref 0

type identify_error =
  | Identify_offline
  | Preview_unreadable of Photo_id.t
  | Plantnet of Plantnet.error

type 'a current = Settled of ('a, identify_error) result | Superseded

let blob (image, organ) =
  match image with
  | Preview b -> Fut.return (Ok (b, organ))
  | Stored id ->
      Fut.map
        (function Ok b -> Ok (b, organ) | Error e -> Error (id, e))
        (Files.read_blob ~path:(Files.preview id) ~type':"image/jpeg")

(* Only the photos Make sends are read. *)
let blobs photos =
  Herbier_bindings.Fut_result.traverse blob
    (List.take Identify.Organ.max_photos photos)

(* The gates run cheapest first and nothing is read for a request that cannot
   leave. Make would refuse a blank key or no photo itself, but it takes the
   previews' bytes, read only after the offline gate. *)
let identify (t : Core.t) channel ~key ~flora ?(no_reject = false) photos =
  incr channel;
  let mine = !channel in
  let settle result =
    match Int.equal !channel mine with
    | true -> Settled result
    | false -> Superseded
  in
  let not_sent reason error =
    Core.log [Identify.identify_not_sent ~flora photos reason];
    Fut.return (settle (Error error))
  in
  match Plantnet.identify_request ~key ~flora ~no_reject photos with
  | Error e -> not_sent (Plantnet.error_to_string e) (Plantnet e)
  | Ok (_ : image Plantnet.request) -> (
      match Core.online t with
      | false -> not_sent "offline" Identify_offline
      | true ->
          Fut.bind (blobs photos) (function
            | Error (id, e) ->
                Core.log_error
                  [
                    "identify: preview";
                    Photo_id.to_string id;
                    "unreadable:";
                    Cap_error.to_string e;
                  ];
                not_sent "preview unreadable" (Preview_unreadable id)
            | Ok sent ->
                Fut.map
                  (fun ({result; line} : _ Identify.logged) ->
                    Core.log [line];
                    settle (Result.map_error (fun e -> Plantnet e) result))
                  (Identify_io.identify ~key ~flora ~no_reject sent)))

(* The list is the same for every key, so a key change keeps it. *)
let ask_floras (t : Core.t) ~key =
  let asked = Identify_io.projects ~key in
  t.floras := Asking asked;
  Fut.await asked (fun ({result; line} : _ Identify.logged) ->
      Core.log [line];
      t.floras :=
        match result with
        | Ok l -> Received l
        | Error (_ : Plantnet.error) -> Not_asked);
  asked

let floras (t : Core.t) ~key =
  let settled (logged : _ Identify.logged) =
    Result.map_error (fun e -> Plantnet e) logged.result
  in
  match Plantnet.projects_request ~key with
  | Error (_ : Plantnet.error) ->
      Fut.map
        (fun (logged : _ Identify.logged) ->
          Core.log [logged.line];
          settled logged)
        (Identify_io.projects ~key)
  | Ok (_ : string) -> (
      match !(t.floras) with
      | Received l -> Fut.return (Ok l)
      | Asking asked -> Fut.map settled asked
      | Not_asked -> (
          match Core.online t with
          | false ->
              Core.log [Identify.projects_not_sent "offline"];
              Fut.return (Error Identify_offline)
          | true -> Fut.map settled (ask_floras t ~key)))
