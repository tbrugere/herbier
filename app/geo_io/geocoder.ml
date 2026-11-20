module Geocode = Herbier_geo.Geocode
module Timed_fetch = Herbier_bindings.Timed_fetch

type error =
  | Network of string
  | Timeout
  | Status of {provider : Geocode.provider; status : int}
  | Payload of Geocode.error
  | Refused of Geocode.provider

let error_to_string = function
  | Network m -> "network: " ^ m
  | Timeout -> "timeout"
  | Status {provider; status} ->
      Printf.sprintf "%s: HTTP %d" (Geocode.provider_to_string provider) status
  | Payload e -> Geocode.error_to_string e
  | Refused provider ->
      Geocode.provider_to_string provider ^ ": refused, not sent"

let transient = function
  | Network _ | Timeout -> true
  | Status {status; provider = _} -> Geocode.transient_status status
  | Payload _ | Refused _ -> false

let spacing_ms = 1000
let default_timeout_ms = 10_000

type job = {
  provider : Geocode.provider;
  start : unit -> (string, error) result Fut.t;
  deliver : (string, error) result -> unit;
}

(* style: module-level mutable queue because the limits are global to the
   app, as the WebView's network is; nothing outside this module sees it. *)
let waiting : job list ref = ref []
let busy = ref false

(* style: last start per provider, module-level for the same reason. *)
let last_start : (Geocode.provider * float) list ref = ref []
let now_ms () = Brr.Performance.now_ms Brr.G.performance

let delay_ms provider =
  match List.assoc_opt provider !last_start with
  | None -> 0
  | Some at ->
      Int.max 0
        (Float.to_int (Float.ceil (at +. Float.of_int spacing_ms -. now_ms ())))

let rec pump () =
  match (!busy, !waiting) with
  | true, _ | false, [] -> ()
  | false, job :: rest ->
      waiting := rest;
      busy := true;
      let go () =
        last_start :=
          (job.provider, now_ms ())
          :: List.remove_assoc job.provider !last_start;
        let started =
          (* A raise here would leave the queue busy forever and the caller's
             future pending. *)
          match job.start () with
          | fut -> fut
          | exception e -> Fut.return (Error (Network (Printexc.to_string e)))
        in
        Fut.await started (fun result ->
            busy := false;
            pump ();
            job.deliver result)
      in
      (* A WebView timer can fire a few ms before [performance.now] says it
         is due (measured on the emulator: 997 ms for 1000), so the delay is
         checked again when it fires. *)
      let rec when_due () =
        match delay_ms job.provider with
        | 0 -> go ()
        | ms ->
            let _timer : Brr.G.timer_id = Brr.G.set_timeout ~ms when_due in
            ()
      in
      when_due ()

(* style: the queue guard above mirrors Herbier_refs_io.Http's (layout.md:
   geo_io and refs_io never import each other); a fix to one goes to the other. *)
let fetch ~timeout_ms provider url =
  Fut.map
    (function
      | Error Timed_fetch.Timeout -> Error Timeout
      | Error (Timed_fetch.Failed m) -> Error (Network m)
      | Ok {Timed_fetch.status; body; headers = _} -> (
          match 200 <= status && status <= 299 with
          | true -> Ok body
          | false -> Error (Status {provider; status})))
    (* [no_store]: the Géoplateforme once answered a WFS request with a 200
       metrics page marked [Cache-Control: private, max-age=1814400]; the
       WebView kept it and served it to every retry for 21 days. *)
    (Timed_fetch.get ~timeout_ms ~non_2xx_body:Timed_fetch.Skip
       ~cache:Brr_io.Fetch.Request.Cache.no_store url)

(* style: module-level, as the queue: every request start goes to them;
   only the dev hook registers one, so a release build keeps nothing. *)
let observers : (Geocode.request -> unit) list ref = ref []
let observe f = observers := !observers @ [f]

let log request =
  List.iter (fun f -> f request) !observers;
  Brr.Console.(log [str ("geocode: GET " ^ Geocode.request_endpoint request)])

let get ~timeout_ms ~on_start ~allow
    ({provider; url} as request : Geocode.request) =
  let fut, deliver = Fut.create () in
  (* Asked when the request leaves the queue, not when it joins it: a source
     turned off meanwhile stops it. *)
  let start () =
    match allow request with
    | false -> Fut.return (Error (Refused provider))
    | true ->
        log request;
        on_start request;
        fetch ~timeout_ms provider url
  in
  waiting := !waiting @ [{provider; start; deliver}];
  pump ();
  fut

let rec run ?(timeout_ms = default_timeout_ms) ?(on_start = ignore)
    ?(allow = fun (_ : Geocode.request) -> true) = function
  | Geocode.Done (Ok x) -> Fut.return (Ok x)
  | Geocode.Done (Error e) -> Fut.return (Error (Payload e))
  | Geocode.Get (request, k) ->
      Fut.bind (get ~timeout_ms ~on_start ~allow request) (function
        | Error e -> Fut.return (Error e)
        | Ok body -> (
            match Geocode.json_of_string body with
            | Error e -> Fut.return (Error (Payload e))
            | Ok json -> run ~timeout_ms ~on_start ~allow (k json)))

let search ?timeout_ms ?on_start ?allow ?near q =
  match String.trim q with
  | "" -> Fut.return (Ok [])
  | _ ->
      run ?timeout_ms ?on_start ?allow
        (Geocode.Get
           ( Geocode.photon_search ?near q,
             fun json -> Geocode.Done (Geocode.photon_places json) ))
