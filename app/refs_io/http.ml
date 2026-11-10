module Source = Herbier_domain.Reference.Source

type error =
  | Network of string
  | Timeout
  | Status of {status : int; body : string; retry_after : string option}

let error_to_string = function
  | Network m -> "network: " ^ m
  | Timeout -> "timeout"
  | Status {status; body; retry_after} ->
      let body =
        match String.length body > 200 with
        | false -> body
        | true ->
            (* Back off to a UTF-8 character boundary before cutting. *)
            let rec boundary n =
              match n > 0 && Char.code body.[n] land 0xC0 = 0x80 with
              | true -> boundary (n - 1)
              | false -> n
            in
            String.sub body 0 (boundary 200) ^ "…"
      in
      let retry_after =
        match retry_after with
        | None -> ""
        | Some s -> Printf.sprintf " (retry after %s)" s
      in
      Printf.sprintf "HTTP %d%s: %s" status retry_after body

let user_agent =
  Printf.sprintf "Herbier/%s (https://github.com/tbrugere/herbier)"
    Herbier_domain.Version.git

let max_in_flight = 3
let default_timeout_ms = 15_000

let wikimedia = function
  | Source.Wikidata | Source.Wikipedia -> true
  | Source.Gbif | Source.Powo | Source.Ipni | Source.Taxref | Source.Tela
  | Source.Eppo | Source.Inat | Source.Plantnet ->
      false

type job = {
  source : Source.t;
  start : unit -> (string, error) result Fut.t;
  deliver : (string, error) result -> unit;
}

(* style: module-level mutable queue because the limits are global to the
   app, as the WebView's network is; nothing outside this module sees it. *)
let waiting : job list ref = ref []
let running : Source.t list ref = ref []

let rec next_startable acc = function
  | [] -> None
  | job :: rest when List.mem job.source !running ->
      next_startable (job :: acc) rest
  | job :: rest -> Some (job, List.rev_append acc rest)

let rec pump () =
  match List.length !running < max_in_flight with
  | false -> ()
  | true -> (
      match next_startable [] !waiting with
      | None -> ()
      | Some (job, rest) ->
          waiting := rest;
          running := job.source :: !running;
          let started =
            (* A raise here would keep the source busy forever and leave the
               caller's future pending, breaking get's "never raises". *)
            match job.start () with
            | fut -> fut
            | exception e -> Fut.return (Error (Network (Printexc.to_string e)))
          in
          Fut.await started (fun result ->
              running := List.filter (fun s -> s <> job.source) !running;
              pump ();
              job.deliver result);
          pump ())

let message e = Jstr.to_string (Jv.Error.message e)

let headers source =
  Brr_io.Fetch.Headers.of_assoc
    (match wikimedia source with
    | true -> [(Jstr.v "Api-User-Agent", Jstr.v user_agent)]
    | false -> [])

let fetch ~timeout_ms source url =
  let abort = Brr.Abort.controller () in
  let timed_out = ref false in
  let timer =
    Brr.G.set_timeout ~ms:timeout_ms (fun () ->
        timed_out := true;
        Brr.Abort.abort abort)
  in
  let init =
    Brr_io.Fetch.Request.init ~headers:(headers source)
      ~signal:(Brr.Abort.signal abort) ()
  in
  let failed e =
    match !timed_out with true -> Timeout | false -> Network (message e)
  in
  let open Fut.Syntax in
  let+ result =
    let* response = Brr_io.Fetch.url ~init (Jstr.v url) in
    match response with
    | Error e -> Fut.return (Error (failed e))
    | Ok response -> (
        let+ body =
          Brr_io.Fetch.Body.text (Brr_io.Fetch.Response.as_body response)
        in
        match (Brr_io.Fetch.Response.ok response, body) with
        | true, Ok body -> Ok (Jstr.to_string body)
        | true, Error e -> Error (failed e)
        | false, body ->
            let body =
              match body with Ok body -> Jstr.to_string body | Error _ -> ""
            in
            let retry_after =
              Brr_io.Fetch.Headers.find (Jstr.v "Retry-After")
                (Brr_io.Fetch.Response.headers response)
              |> Option.map Jstr.to_string
            in
            Error
              (Status
                 {
                   status = Brr_io.Fetch.Response.status response;
                   body;
                   retry_after;
                 }))
  in
  Brr.G.stop_timer timer;
  result

let get ?(timeout_ms = default_timeout_ms) source url =
  let fut, deliver = Fut.create () in
  let start () = fetch ~timeout_ms source url in
  waiting := !waiting @ [{source; start; deliver}];
  pump ();
  fut

let in_flight () = List.rev !running
