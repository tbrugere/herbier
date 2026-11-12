type error =
  | Network of string
  | Timeout
  | Status of {provider : Geocode.provider; status : int}
  | Payload of Geocode.error

let error_to_string = function
  | Network m -> "network: " ^ m
  | Timeout -> "timeout"
  | Status {provider; status} ->
      Printf.sprintf "%s: HTTP %d" (Geocode.provider_to_string provider) status
  | Payload e -> Geocode.error_to_string e

let transient = function
  | Network _ | Timeout -> true
  | Status {status; provider = _} ->
      Int.equal status 429 || (500 <= status && status <= 599)
  | Payload _ -> false

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
  | false, job :: rest -> (
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
      match delay_ms job.provider with
      | 0 -> go ()
      | ms ->
          let _timer : Brr.G.timer_id = Brr.G.set_timeout ~ms go in
          ())

let message e = Jstr.to_string (Jv.Error.message e)

(* style: the queue guard above and this timed fetch mirror
   Herbier_refs_io.Http (layout.md: geo and refs_io never import each other);
   a fix to one goes to the other. *)
let fetch ~timeout_ms provider url =
  let abort = Brr.Abort.controller () in
  let timed_out = ref false in
  let timer =
    Brr.G.set_timeout ~ms:timeout_ms (fun () ->
        timed_out := true;
        Brr.Abort.abort abort)
  in
  let init = Brr_io.Fetch.Request.init ~signal:(Brr.Abort.signal abort) () in
  let failed e =
    match !timed_out with true -> Timeout | false -> Network (message e)
  in
  let open Fut.Syntax in
  let+ result =
    let* response = Brr_io.Fetch.url ~init (Jstr.v url) in
    match response with
    | Error e -> Fut.return (Error (failed e))
    | Ok response -> (
        match Brr_io.Fetch.Response.ok response with
        | false ->
            Fut.return
              (Error
                 (Status
                    {provider; status = Brr_io.Fetch.Response.status response}))
        | true -> (
            let+ body =
              Brr_io.Fetch.Body.text (Brr_io.Fetch.Response.as_body response)
            in
            match body with
            | Ok body -> Ok (Jstr.to_string body)
            | Error e -> Error (failed e)))
  in
  Brr.G.stop_timer timer;
  result

let get ~timeout_ms ~on_start ({provider; url} as request : Geocode.request) =
  let fut, deliver = Fut.create () in
  let start () =
    on_start request;
    fetch ~timeout_ms provider url
  in
  waiting := !waiting @ [{provider; start; deliver}];
  pump ();
  fut

let rec run ?(timeout_ms = default_timeout_ms) ?(on_start = ignore) = function
  | Geocode.Done (Ok x) -> Fut.return (Ok x)
  | Geocode.Done (Error e) -> Fut.return (Error (Payload e))
  | Geocode.Get (request, k) ->
      Fut.bind (get ~timeout_ms ~on_start request) (function
        | Error e -> Fut.return (Error e)
        | Ok body -> (
            match Geocode.json_of_string body with
            | Error e -> Fut.return (Error (Payload e))
            | Ok json -> run ~timeout_ms ~on_start (k json)))

let reverse ?timeout_ms ?on_start p =
  run ?timeout_ms ?on_start (Geocode.reverse p)

let search ?timeout_ms ?on_start ?near q =
  match String.trim q with
  | "" -> Fut.return (Ok [])
  | _ ->
      run ?timeout_ms ?on_start
        (Geocode.Get
           ( Geocode.photon_search ?near q,
             fun json -> Geocode.Done (Geocode.photon_places json) ))
