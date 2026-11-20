module Code = Communes.Code

let measured_on = France_sizes.measured_on

(* The lower median: robust to the few very large départements. *)
let fallback_bytes =
  let sizes = List.sort Int.compare (List.map snd France_sizes.table) in
  match List.nth_opt sizes ((List.length sizes - 1) / 2) with
  | Some n -> n
  | None -> 1

let estimated_bytes code =
  match List.assoc_opt (Code.to_string code) France_sizes.table with
  | Some n -> n
  | None -> fallback_bytes

let sum table = List.fold_left (fun acc (_, n) -> acc + n) 0 table

let transfer_bytes code =
  match List.assoc_opt (Code.to_string code) France_sizes.transfer with
  | Some n -> n
  | None -> (
      match sum France_sizes.table with
      | 0 -> fallback_bytes
      | stored ->
          (* Floats: the product passes 2^31, an int's width under
             js_of_ocaml. *)
          Float.to_int
            (Float.of_int fallback_bytes
            *. Float.of_int (sum France_sizes.transfer)
            /. Float.of_int stored))

type plan = {
  departements : Communes.departement list;
      [@equal List.equal Communes.equal_departement]
  todo : Communes.departement list;
      [@equal List.equal Communes.equal_departement]
  present : int;
  total : int;
  estimate_bytes : int;
  transfer_bytes : int;
}
[@@deriving eq]

let plan ?only ~downloaded list =
  let mem codes code = List.exists (Code.equal code) codes in
  let departements =
    match only with
    | None -> list
    | Some codes ->
        List.filter (fun (d : Communes.departement) -> mem codes d.code) list
  in
  let todo =
    List.filter
      (fun (d : Communes.departement) -> not (mem downloaded d.code))
      departements
  in
  let total = List.length departements in
  let over f =
    List.fold_left (fun acc (d : Communes.departement) -> acc + f d.code) 0 todo
  in
  {
    departements;
    todo;
    present = total - List.length todo;
    total;
    estimate_bytes = over estimated_bytes;
    transfer_bytes = over transfer_bytes;
  }

type failure = Transient | Skip | Stop

type cause =
  | Network
  | Timeout
  | Status of int
  | Not_json
  | Bad_payload
  | Refused
  | Local

let failure_of_cause = function
  | Network | Timeout | Not_json -> Transient
  | Status (401 | 403) | Refused | Local -> Stop
  | Status status -> (
      match Geocode.transient_status status with
      | true -> Transient
      | false -> Skip)
  | Bad_payload -> Skip

let backoff_ms = [5_000; 20_000; 60_000]

type 'e progress = {
  plan : plan;
  downloaded : int;
  bytes : int;
  failed : (Communes.departement * 'e) list;
}

let position p = p.plan.present + p.downloaded

type 'e step =
  | Downloading of 'e progress * Communes.departement
  | Retrying of {
      progress : 'e progress;
      departement : Communes.departement;
      attempt : int;
      attempts : int;
      wait_ms : int;
      error : 'e;
    }

type 'e outcome =
  | Complete of 'e progress
  | Cancelled of 'e progress
  | Stopped of 'e progress * 'e

module type ENV = sig
  type 'a io

  val return : 'a -> 'a io
  val bind : 'a io -> ('a -> 'b io) -> 'b io

  type ctx
  type error

  val download : ctx -> Communes.departement -> (int, error) result io
  val classify : error -> failure
  val sleep : ctx -> ms:int -> unit io
  val cancelled : ctx -> bool
  val report : ctx -> error step -> unit
end

module Make (E : ENV) = struct
  let attempts = List.length backoff_ms

  let run ctx plan =
    let rec next progress = function
      | [] -> E.return (Complete progress)
      | d :: rest -> (
          match E.cancelled ctx with
          | true -> E.return (Cancelled progress)
          | false -> attempt progress d rest backoff_ms)
    and attempt progress d rest backoff_left =
      E.report ctx (Downloading (progress, d));
      E.bind (E.download ctx d) (function
        | Ok size ->
            next
              {
                progress with
                downloaded = progress.downloaded + 1;
                bytes = progress.bytes + size;
              }
              rest
        | Error e -> (
            match (E.classify e, backoff_left) with
            | Skip, _ ->
                (* style: [@] on a list of the rare skipped départements,
                   because every report needs them in order. *)
                next {progress with failed = progress.failed @ [(d, e)]} rest
            | Stop, _ | Transient, [] -> E.return (Stopped (progress, e))
            | Transient, wait_ms :: rest_backoff -> (
                E.report ctx
                  (Retrying
                     {
                       progress;
                       departement = d;
                       attempt = attempts - List.length rest_backoff;
                       attempts;
                       wait_ms;
                       error = e;
                     });
                E.bind (E.sleep ctx ~ms:wait_ms) @@ fun () ->
                match E.cancelled ctx with
                | true -> E.return (Cancelled progress)
                | false -> attempt progress d rest rest_backoff)))
    in
    next {plan; downloaded = 0; bytes = 0; failed = []} plan.todo
end
