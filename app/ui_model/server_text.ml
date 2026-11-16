module Report = Herbier_sync_core.Cycle.Report
module Outcome = Herbier_sync_core.Cycle.Outcome

let paused r =
  match Option.bind r Report.stop with
  | Some Outcome.Paused -> true
  | Some
      Outcome.(
        ( Signed_out | Auth _ | Offline _ | Unauthorized | Transient _
        | Rejected _ | Bad_response _ | Store _ | Held _ ))
  | None ->
      false

let paused_title = "Serveur en pause"

let paused_detail =
  "Les modifications attendent sur le téléphone ; elles partiront quand le \
   serveur sera réactivé."

let project_ref_char = function 'a' .. 'z' | '0' .. '9' -> true | _ -> false

let strip_suffix ~suffix s =
  match String.ends_with ~suffix s with
  | true -> Some (String.sub s 0 (String.length s - String.length suffix))
  | false -> None

let strip_prefix ~prefix s =
  match String.starts_with ~prefix s with
  | true ->
      let k = String.length prefix in
      Some (String.sub s k (String.length s - k))
  | false -> None

let dashboard_url ~supabase_url =
  let host =
    match strip_suffix ~suffix:"/" supabase_url with
    | Some s -> s
    | None -> supabase_url
  in
  Option.bind (strip_prefix ~prefix:"https://" host) (fun rest ->
      match strip_suffix ~suffix:".supabase.co" rest with
      | Some project
        when project <> "" && String.for_all project_ref_char project ->
          Some ("https://supabase.com/dashboard/project/" ^ project)
      | Some _ | None -> None)

let dashboard_label = "Ouvrir le tableau de bord ↗"
