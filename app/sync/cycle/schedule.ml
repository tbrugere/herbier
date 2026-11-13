type trigger =
  | Start
  | Resume
  | Local_write
  | Signed_in
  | Manual
  | Retry_timer
  | Backgrounded
[@@deriving eq, show]

type action = Run of trigger | Wait of Ptime.Span.t | Cancel_timer | Nothing
[@@deriving eq, show]

type state =
  | Idle of {attempt : int}
  | Running of {attempt : int; again : trigger option; background : bool}
  | Waiting of {attempt : int}
[@@deriving eq, show]

let trigger_to_string = function
  | Start -> "start"
  | Resume -> "resume"
  | Local_write -> "local write"
  | Signed_in -> "signed in"
  | Manual -> "manual"
  | Retry_timer -> "retry"
  | Backgrounded -> "backgrounded"

let state_to_string = function
  | Idle {attempt} -> Printf.sprintf "idle (attempt %d)" attempt
  | Running {attempt; again; background} ->
      Printf.sprintf "running (attempt %d%s%s)" attempt
        (match again with Some _ -> ", again" | None -> "")
        (match background with true -> ", background" | false -> "")
  | Waiting {attempt} -> Printf.sprintf "waiting (attempt %d)" attempt

let initial = Idle {attempt = 0}

let trigger state trigger =
  match (state, trigger) with
  | Idle _, (Retry_timer | Backgrounded) -> (state, Nothing)
  | Idle {attempt}, (Start | Resume | Local_write | Signed_in | Manual) ->
      (Running {attempt; again = None; background = false}, Run trigger)
  | Running {attempt; again; background = _}, Backgrounded ->
      (Running {attempt; again; background = true}, Nothing)
  | Running _, Retry_timer -> (state, Nothing)
  | ( Running {attempt; again = _; background = _},
      (Start | Resume | Local_write | Signed_in | Manual) ) ->
      (Running {attempt; again = Some trigger; background = false}, Nothing)
  | Waiting {attempt}, Backgrounded -> (Idle {attempt}, Cancel_timer)
  | ( Waiting {attempt},
      (Start | Resume | Local_write | Signed_in | Manual | Retry_timer) ) ->
      (Running {attempt; again = None; background = false}, Run trigger)

(* 10 s doubling, capped at 300 s (from 2^5 on): the exponent is capped first
   so that no attempt overflows. *)
let retry_delay ~attempt =
  let exponent = min 5 (max 0 (attempt - 1)) in
  Ptime.Span.of_int_s (min 300 (10 * (1 lsl exponent)))

let finished state stop =
  match (state, stop) with
  | (Idle _ | Waiting _), _ -> (state, Nothing)
  | Running {again = Some rerun; attempt = _; background}, None ->
      (Running {attempt = 0; again = None; background}, Run rerun)
  | Running {again = None; attempt = _; background = _}, None ->
      (Idle {attempt = 0}, Nothing)
  | Running {attempt; again; background}, Some stop -> (
      match (Outcome.retries stop, background, again) with
      | false, _, _ -> (Idle {attempt = 0}, Nothing)
      | true, true, _ -> (Idle {attempt = attempt + 1}, Nothing)
      | true, false, Some rerun ->
          (Running {attempt = attempt + 1; again = None; background}, Run rerun)
      | true, false, None ->
          let attempt = attempt + 1 in
          (Waiting {attempt}, Wait (retry_delay ~attempt)))
