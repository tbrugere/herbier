module Source = Herbier_domain.Reference.Source
module Timed_fetch = Herbier_bindings.Timed_fetch

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
    Herbier_version.git

let max_in_flight = 3
let default_timeout_ms = Timed_fetch.timeout_ms

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

let headers source =
  match wikimedia source with
  | true -> [("Api-User-Agent", user_agent)]
  | false -> []

(* The Fetch API lowercases header names. *)
let fetch ~timeout_ms source url =
  Fut.map
    (function
      | Error Timed_fetch.Timeout -> Error Timeout
      | Error (Timed_fetch.Failed m) -> Error (Network m)
      | Ok {Timed_fetch.status; headers; body} -> (
          match 200 <= status && status <= 299 with
          | true -> Ok body
          | false ->
              Error
                (Status
                   {
                     status;
                     body;
                     retry_after = List.assoc_opt "retry-after" headers;
                   })))
    (Timed_fetch.get ~timeout_ms ~non_2xx_body:Timed_fetch.Read_or_empty
       ~headers:(headers source) url)

let get ?(timeout_ms = default_timeout_ms) (request : Herbier_refs.Request.t) =
  let source = request.source and url = request.url in
  let fut, deliver = Fut.create () in
  let start () = fetch ~timeout_ms source url in
  waiting := !waiting @ [{source; start; deliver}];
  pump ();
  fut

let in_flight () = List.rev !running

(* 404 is how GBIF species/<key> and Wikipedia say "no such taxon or page";
   any other status is treated as transient (Failed: live rows are kept and
   retried later); 429 and 5xx are the expected ones. *)
let response = function
  | Ok body -> (
      match Herbier_refs.Decode.json_of_string body with
      | Ok json -> Herbier_refs.Step.Body json
      | Error e ->
          Herbier_refs.Step.Failed (Herbier_refs.Decode.error_to_string e))
  | Error (Status {status = 404; _}) -> Herbier_refs.Step.Absent
  | Error ((Network _ | Timeout | Status _) as e) ->
      Herbier_refs.Step.Failed (error_to_string e)

(* A failed call only leaves a Failed status in the stored row: the log is
   what tells a CORS refusal from a timeout on the device. *)
let logged (request : Herbier_refs.Request.t) = function
  | Herbier_refs.Step.Failed message as r ->
      Brr.Console.(
        warn
          [
            str "refs: failed";
            str (Source.to_string request.source);
            str request.url;
            str message;
          ]);
      r
  | (Herbier_refs.Step.Body _ | Herbier_refs.Step.Absent) as r -> r

let rec run ?timeout_ms = function
  | Herbier_refs.Step.Done x -> Fut.return x
  | Herbier_refs.Step.Get (request, k) ->
      Fut.bind (get ?timeout_ms request) (fun r ->
          run ?timeout_ms (k (logged request (response r))))
