module Organ = Herbier_identify.Organ
module Plantnet = Herbier_identify.Plantnet
module Settings = Herbier_store.Settings

type outcome =
  | Left
  | Chosen of Plantnet.proposal
  | None_matches
  | Retake
  | Keep_unnamed
[@@deriving eq]

type after = Stay | Resolve of Plantnet.proposal [@@deriving eq]

let after_close = function
  | Chosen p -> Resolve p
  | Left | None_matches | Retake | Keep_unnamed -> Stay

type phase =
  | Sending of {slow : bool}
  | Proposals of Herbier_identify.identified
  | Failed of Failure.t
  | Closed of outcome
[@@deriving eq]

type request = {flora : string; no_reject : bool; organs : Organ.sent list}
[@@deriving eq]

type t = {
  caller : Caller.t;
  organs : Organ.sent list;
  detected : Organ.t option list;
  flora : Settings.flora option;
  no_reject : bool;
  seq : int;
  taking : bool;
  phase : phase;
}
[@@deriving eq]

type command =
  | Send of {seq : int; request : request}
  | Wait_slow of {seq : int; ms : int}
  | Take_photo of Organ.sent
  | Save_flora of Settings.flora option
  | Close of outcome
[@@deriving eq]

type event =
  | Slow of int
  | Answered of {
      seq : int;
      result : (Herbier_identify.identified, Failure.error) result;
    }
  | Back
  | Choose of int
  | None_matches
  | Set_organ of {photo : int; organ : Organ.t}
  | Add
  | Photo_added of Organ.sent option
  | Set_flora of Settings.flora option
  | Force
  | Retry
  | Retake
  | Keep_unnamed

let slow_ms = 600

let request t =
  {
    flora = Identify_settings.flora_id t.flora;
    no_reject = t.no_reject;
    organs = t.organs;
  }

let take n l = List.filteri (fun i (_ : 'a) -> i < n) l

(* [l] cut or padded with [None] to [n] elements. *)
let fit n l =
  let l = take n l in
  l @ List.init (n - List.length l) (fun (_ : int) -> None)

let effective_organs t =
  List.map2
    (fun sent detected -> Organ.effective sent ~detected)
    t.organs
    (fit (List.length t.organs) t.detected)

let room t = List.length t.organs < Organ.max_photos

let accepts_photo t =
  match t.phase with
  | Proposals (_ : Herbier_identify.identified) -> room t
  | Failed f -> Failure.reask f && room t
  | Sending _ | Closed (_ : outcome) -> false

let add_tile t =
  match t.phase with
  | Proposals (_ : Herbier_identify.identified) ->
      Organ.suggest (effective_organs t)
  | Failed (_ : Failure.t) when accepts_photo t -> Some Organ.Add_photo
  | Failed (_ : Failure.t) | Sending _ | Closed (_ : outcome) -> None

let sending seq request = [Send {seq; request}; Wait_slow {seq; ms = slow_ms}]

let reask ?(before = []) t =
  let t = {t with seq = t.seq + 1; phase = Sending {slow = false}} in
  (t, before @ sending t.seq (request t))

let close t outcome = ({t with phase = Closed outcome}, [Close outcome])

let open_ ~caller ~flora organs =
  let organs = take Organ.max_photos organs in
  let t =
    {
      caller;
      organs;
      detected = List.map (fun (_ : Organ.sent) -> None) organs;
      flora;
      no_reject = false;
      seq = 0;
      taking = false;
      phase = Sending {slow = false};
    }
  in
  match organs with [] -> close t Left | _ :: _ -> reask t

let answered t result =
  match result with
  | Ok (i : Herbier_identify.identified) -> (
      match i.answer.proposals with
      | [] -> {t with phase = Failed (No_plant {can_force = not t.no_reject})}
      | _ :: _ ->
          {
            t with
            phase = Proposals i;
            detected = fit (List.length t.organs) i.answer.detected;
          })
  | Error e ->
      {t with phase = Failed (Failure.of_error ~no_reject:t.no_reject e)}

let set_organ t ~photo ~organ =
  match photo >= 0 with
  | false -> (t, [])
  | true -> (
      match List.nth_opt t.organs photo with
      | None -> (t, [])
      | Some sent -> (
          let detected =
            Option.join
              (List.nth_opt (fit (List.length t.organs) t.detected) photo)
          in
          match
            Option.equal Organ.equal
              (Organ.effective sent ~detected)
              (Some organ)
          with
          | true -> (t, [])
          | false ->
              let organs =
                List.mapi
                  (fun i o ->
                    match i = photo with
                    | true -> Organ.Given organ
                    | false -> o)
                  t.organs
              in
              reask {t with organs; no_reject = false}))

let on_open t event =
  let same = (t, []) in
  match (event, t.phase) with
  | Back, (Sending _ | Proposals _ | Failed _ | Closed _) -> close t Left
  | Slow s, Sending _ when s = t.seq ->
      ({t with phase = Sending {slow = true}}, [])
  | Slow (_ : int), (Sending _ | Proposals _ | Failed _ | Closed _) -> same
  | Answered {seq; result}, Sending _ when seq = t.seq -> (answered t result, [])
  | Answered _, (Sending _ | Proposals _ | Failed _ | Closed _) -> same
  | Photo_added (Some o), (Sending _ | Proposals _ | Failed _ | Closed _)
    when accepts_photo t ->
      reask
        {
          t with
          organs = t.organs @ [o];
          detected = fit (List.length t.organs) t.detected @ [None];
          no_reject = false;
          taking = false;
        }
  | ( Photo_added (Some (_ : Organ.sent) | None),
      (Sending _ | Proposals _ | Failed _ | Closed _) ) ->
      ({t with taking = false}, [])
  | ( (Add | Set_organ _ | Set_flora _ | Force | Retry),
      (Sending _ | Proposals _ | Failed _ | Closed _) )
    when t.taking ->
      same
  | Choose k, Proposals i when k >= 0 -> (
      match List.nth_opt i.answer.proposals k with
      | Some p -> close t (Chosen p)
      | None -> same)
  | Choose (_ : int), (Sending _ | Proposals _ | Failed _ | Closed _) -> same
  | None_matches, Proposals (_ : Herbier_identify.identified) ->
      close t None_matches
  | None_matches, (Sending _ | Failed _ | Closed _) -> same
  | Set_organ {photo; organ}, Proposals (_ : Herbier_identify.identified) ->
      set_organ t ~photo ~organ
  | Set_organ _, (Sending _ | Failed _ | Closed _) -> same
  | Add, (Sending _ | Proposals _ | Failed _ | Closed _) -> (
      match add_tile t with
      | Some s ->
          ({t with taking = true}, [Take_photo (Organ.sent_of_suggestion s)])
      | None -> same)
  | Set_flora f, Proposals (_ : Herbier_identify.identified)
    when not (Option.equal Settings.equal_flora f t.flora) ->
      reask ~before:[Save_flora f] {t with flora = f; no_reject = false}
  | Set_flora _, (Sending _ | Proposals _ | Failed _ | Closed _) -> same
  | Force, Failed (No_plant {can_force = true}) ->
      reask {t with no_reject = true}
  | Force, (Sending _ | Proposals _ | Failed _ | Closed _) -> same
  | Retry, Failed f when Failure.retry f -> reask t
  | Retry, (Sending _ | Proposals _ | Failed _ | Closed _) -> same
  | Retake, Failed (_ : Failure.t) when Caller.retake t.caller -> close t Retake
  | Keep_unnamed, Failed (_ : Failure.t) when Caller.retake t.caller ->
      close t Keep_unnamed
  | (Retake | Keep_unnamed), (Sending _ | Proposals _ | Failed _ | Closed _) ->
      same

let step t event =
  match t.phase with
  | Closed (_ : outcome) -> (t, [])
  | Sending _ | Proposals _ | Failed _ -> on_open t event
