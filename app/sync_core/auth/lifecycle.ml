type status =
  | Unconfigured
  | Restoring
  | Signed_out
  | Signed_in of {email : string option}
[@@deriving eq]

(* [Off]: this build cannot sign in. [Reading]: Preferences not read yet.
   The status is derived from it, so that the two cannot disagree. *)
type phase = Off | Reading | Ready of Session.t option

type t = {
  phase : phase;
  foreground : bool;
  attempt : int;
      (* The latest sign-in: an older one's result is dropped, so that a
         flight that never ends cannot block the next one. *)
  generation : int;
      (* Bumped when a sign-in, a sign-out or a revoked refresh replaces the
         session ({!replace}): a refresh or restore that resolves under an
         older generation changes nothing. *)
  failed_refreshes : int;
}

type action =
  | Notify of status
  | Reschedule
  | Retry_in of Ptime.Span.t
  | Stop_timer
  | Start_refresh
  | Log of string
  | Warn of string
  | Console_error of string
  | Logout_server of Session.t
  | Job_dropped
  | Forget_stored of {generation : int}
[@@deriving eq]

let create ~configured =
  {
    phase = (match configured with true -> Reading | false -> Off);
    foreground = true;
    attempt = 0;
    generation = 0;
    failed_refreshes = 0;
  }

let status t =
  match t.phase with
  | Off -> Unconfigured
  | Reading -> Restoring
  | Ready None -> Signed_out
  | Ready (Some s) -> Signed_in {email = s.email}

let configured t = match t.phase with Off -> false | Reading | Ready _ -> true
let session t = match t.phase with Ready s -> s | Off | Reading -> None
let foreground t = t.foreground

let armed t =
  match (t.foreground, session t) with
  | true, Some _ -> true
  | false, _ | true, None -> false

let generation t = t.generation
let stale t ~generation = not (Int.equal t.generation generation)
let current t ~attempt = Int.equal t.attempt attempt

let expiry_line (s : Session.t) =
  "expires " ^ Ptime.to_rfc3339 ~tz_offset_s:0 s.expires_at

let with_phase t phase =
  let next = {t with phase} in
  let after = status next in
  match equal_status (status t) after with
  | true -> (next, [])
  | false -> (next, [Notify after])

(* The one way a sign-in, a sign-out or a revoked refresh replaces the
   session: older flights become stale. *)
let replace t next =
  let t, notify =
    with_phase
      {t with generation = t.generation + 1; failed_refreshes = 0}
      (Ready next)
  in
  (t, notify @ [Reschedule])

let restored t ~generation stored =
  match (stale t ~generation, stored) with
  | true, _ -> (t, [])
  | false, Error why ->
      let t, notify = with_phase t (Ready None) in
      (t, Console_error ("session not read: " ^ why) :: notify)
  | false, Ok None -> with_phase t (Ready None)
  | false, Ok (Some text) -> (
      match Session.of_string text with
      | Ok s ->
          let t, notify = with_phase t (Ready (Some s)) in
          (t, notify @ [Log ("session restored, " ^ expiry_line s)])
      | Error reason ->
          let t, notify = with_phase t (Ready None) in
          ( t,
            (Warn ("stored session dropped: " ^ reason) :: notify)
            @ [Forget_stored {generation}] ))

let resumed ~now t =
  let t = {t with foreground = true} in
  match session t with
  | None -> (t, [])
  | Some s -> (
      match Session.due ~now s with
      | true -> (t, [Start_refresh])
      | false -> (t, [Reschedule]))

let paused t =
  ({t with foreground = false}, [Stop_timer; Log "background, timer stopped"])

let refreshed t fresh ~not_stored =
  let stored =
    match not_stored with
    | None -> []
    | Some why ->
        (* The stored refresh token is already rotated out: the next launch
           may come up signed out. *)
        [Console_error ("refreshed session not stored: " ^ why)]
  in
  let t, notify =
    with_phase {t with failed_refreshes = 0} (Ready (Some fresh))
  in
  (t, stored @ notify @ [Log ("refreshed, " ^ expiry_line fresh); Reschedule])

let revoked t e =
  let t, replaced = replace t None in
  ( t,
    (Warn ("session revoked: " ^ Gotrue.error_to_string e) :: replaced)
    @ [Job_dropped] )

let refresh_failed t ~why =
  let t = {t with failed_refreshes = t.failed_refreshes + 1} in
  let delay = Backoff.delay ~attempt:t.failed_refreshes in
  ( t,
    [
      Warn
        (Printf.sprintf "refresh failed (%s), retry in %.0f s" why
           (Ptime.Span.to_float_s delay));
      Retry_in delay;
    ] )

let sign_in_started t =
  let attempt = t.attempt + 1 in
  ({t with attempt}, attempt)

let kept t (s : Session.t) =
  let previous = session t in
  let t, replaced = replace t (Some s) in
  ( t,
    replaced
    @ [Log ("signed in, " ^ expiry_line s)]
    @ Option.to_list (Option.map (fun p -> Logout_server p) previous) )

let signed_out t =
  let t, replaced = replace t None in
  (t, replaced @ [Log "signed out"; Job_dropped])

let expiry_moved ~now t =
  match session t with
  | None -> (t, [])
  | Some s -> (
      match
        Ptime.add_span now
          (Ptime.Span.add Session.refresh_margin (Ptime.Span.of_int_s 30))
      with
      | None -> (t, [])
      | Some at ->
          let s = Session.with_expiry at s in
          let t, notify = with_phase t (Ready (Some s)) in
          (t, notify @ [Log ("expiry moved, " ^ expiry_line s); Reschedule]))
