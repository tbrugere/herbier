module Plant = Herbier_domain.Plant
module Observation = Herbier_domain.Observation
module Places = Herbier_domain.Places
module Plant_id = Herbier_domain.Ids.Plant_id
module Organ = Herbier_identify.Organ
module Plantnet = Herbier_identify.Plantnet
module Choice = Identify.Choice

type target =
  | Existing of Plant.t
  | Free of string
  | Linked of {name : string; taxon : Herbier_refs.Sources.Gbif.Taxon.t}
  | To_identify

let fold s = String.lowercase_ascii (String.trim s)

let typed ~plants ~chosen text =
  let t = fold text in
  match (chosen, String.trim text) with
  | Some (p : Plant.t), _ when String.equal (fold p.display_name) t ->
      Existing p
  | _, "" -> To_identify
  | _, name -> (
      let named (p : Plant.t) =
        List.exists
          (fun n -> String.equal (fold n) t)
          (p.display_name :: p.aliases)
      in
      match List.find_opt named plants with
      | Some p -> Existing p
      | None -> Free name)

let of_choice ~plants (c : Choice.t) =
  match (Choice.owner ~plants c, Choice.taxon c) with
  | Some p, (Some _ | None) -> Existing p
  | None, Some taxon -> Linked {name = Choice.new_name c.proposal; taxon}
  | None, None -> typed ~plants ~chosen:None (Choice.new_name c.proposal)

let choice_owner ~plants c =
  match of_choice ~plants c with
  | Existing p -> Some p
  | Free _ | Linked _ | To_identify -> None

let target ~plants ~chosen ?choice text =
  match choice with
  | Some c -> of_choice ~plants c
  | None -> typed ~plants ~chosen text

let seen_here ~here observations plants =
  let here = Places.of_position here in
  let near =
    List.filter_map
      (fun (o : Observation.t) ->
        match (o.plant_id, o.position) with
        | Some id, Some pos ->
            let p = Places.of_position pos in
            if Places.within here p then Some (id, Places.distance_m here p)
            else None
        | _ -> None)
      observations
  in
  let sorted = List.stable_sort (fun (_, a) (_, b) -> Float.compare a b) near in
  let ids =
    List.rev
      (List.fold_left
         (fun acc (id, _) ->
           if List.exists (Plant_id.equal id) acc then acc else id :: acc)
         [] sorted)
  in
  List.filter_map
    (fun id ->
      List.find_opt (fun (p : Plant.t) -> Plant_id.equal p.id id) plants)
    ids

let fix_window_s = 600.

let when_where ~now ~fix = function
  | [] -> (now, fix)
  | (taken_at, position) :: _ -> (
      let at = Option.value taken_at ~default:now in
      match position with
      | Some p -> (at, Some p)
      | None -> (
          match
            Float.abs (Ptime.Span.to_float_s (Ptime.diff now at))
            <= fix_window_s
          with
          | true -> (at, fix)
          | false -> (at, None)))

let identify_label = "Identifier avec Pl@ntNet"

let identify_enabled gate ~photos =
  match (gate : Identify_settings.gate) with
  | Ready _ -> photos > 0
  | Waiting | No_key | Offline -> false

let identify_aria : Identify_settings.gate -> string = function
  | Offline -> identify_label ^ ", indisponible hors-ligne"
  | No_key -> identify_label ^ ", clé API manquante"
  | Ready _ | Waiting -> identify_label

let offline_line =
  "Hors-ligne : l'identification reviendra avec le réseau. Sans nom, la plante \
   part dans « À identifier »."

let identify_line : Identify_settings.gate -> string option = function
  | No_key -> Some Identify_settings.no_key_line
  | Offline -> Some offline_line
  | Ready _ | Waiting -> None

let auto_open ~armed ~on_photo gate ~before ~added =
  armed
  && before = 0
  && added > 0
  && Identify_settings.opens_on_photo ~on_photo gate

type 'photo ask = {
  photos : 'photo list;
  organs : Organ.sent list;
  flora : string;
  no_reject : bool;
}

let reuses eq ~kept ask =
  List.equal eq kept.photos ask.photos
  && List.equal Organ.equal_sent kept.organs ask.organs
  && String.equal kept.flora ask.flora
  && (kept.no_reject || not ask.no_reject)

let keep_answer :
    (Herbier_identify.identified, Identify.Failure.error) result -> bool =
  function
  | Ok _ | Error (Plantnet No_plant) -> true
  | Error
      ( Plantnet
          ( No_key | No_photo | Key_refused | Key_not_exposed | Quota_used_up
          | Refused_request _ | Unreachable _ | Malformed _ )
      | Not_sent_offline | Preview_unreadable ) ->
      false

let choice_score (p : Plantnet.proposal) =
  "Pl@ntNet " ^ Identify.Text.percent p.score

let already_line (p : Plant.t) =
  "Déjà dans ma collection : l'observation s'ajoutera à " ^ p.display_name ^ "."

let clear_choice_label = "Effacer le choix"

let taking_label (o : Organ.sent) =
  let suggestion : Organ.suggestion =
    match o with Given o -> Add o | Auto -> Add_photo
  in
  "Pl@ntNet · " ^ Organ.suggestion_label suggestion

let taking_cancel = "Annuler"

type choice_change =
  | Keep_choice
  | Clear_choice
  | Set_choice of Plantnet.proposal
[@@deriving eq]

type after = {choice : choice_change; clear_text : bool; retake : bool}
[@@deriving eq]

let after_layer : Identify.Layer.outcome -> after = function
  | Left -> {choice = Keep_choice; clear_text = false; retake = false}
  | Chosen p -> {choice = Set_choice p; clear_text = true; retake = false}
  | None_matches -> {choice = Clear_choice; clear_text = false; retake = false}
  | Keep_unnamed -> {choice = Clear_choice; clear_text = true; retake = false}
  | Retake -> {choice = Clear_choice; clear_text = false; retake = true}
