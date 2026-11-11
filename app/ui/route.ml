open Brr
module Tab_bar = Widgets.Tab_bar
module Plant_id = Herbier_domain.Ids.Plant_id
module Observation_id = Herbier_domain.Ids.Observation_id

type modal =
  | Tags
  | Manage_tags
  | Plant of Plant_id.t
  | Edit_plant of Plant_id.t
  | New_plant
  | Observation of Observation_id.t
  | Change_species of Observation_id.t
  | Identify of Observation_id.t
  | Record
  | Saved of Observation_id.t

type t = Tab of Tab_bar.tab | Modal of modal | Dev of string

let dev_prefix = "dev/"

let of_fragment = function
  | "" | "collection" -> Tab Tab_bar.Collection
  | "carte" -> Tab Tab_bar.Map
  | "journal" -> Tab Tab_bar.Journal
  | "reglages" -> Tab Tab_bar.Settings
  | "tags" -> Modal Tags
  | "tags/gerer" -> Modal Manage_tags
  | "plante/nouvelle" -> Modal New_plant
  | "noter" -> Modal Record
  | f when String.starts_with ~prefix:dev_prefix f ->
      let n = String.length dev_prefix in
      Dev (String.sub f n (String.length f - n))
  | f -> (
      let plant id k =
        match Plant_id.of_string id with
        | Some id -> Modal (k id)
        | None -> Tab Tab_bar.Collection
      in
      let observation id k =
        match Observation_id.of_string id with
        | Some id -> Modal (k id)
        | None -> Tab Tab_bar.Collection
      in
      match String.split_on_char '/' f with
      | ["plante"; id] -> plant id (fun id -> Plant id)
      | ["plante"; id; "modifier"] -> plant id (fun id -> Edit_plant id)
      | ["observation"; id] -> observation id (fun id -> Observation id)
      | ["observation"; id; "espece"] ->
          observation id (fun id -> Change_species id)
      | ["a-identifier"; id] -> observation id (fun id -> Identify id)
      | ["noter"; "enregistre"; id] -> observation id (fun id -> Saved id)
      | _ -> Tab Tab_bar.Collection)

let to_fragment = function
  | Tab Tab_bar.Collection -> "collection"
  | Tab Tab_bar.Map -> "carte"
  | Tab Tab_bar.Journal -> "journal"
  | Tab Tab_bar.Settings -> "reglages"
  | Modal Tags -> "tags"
  | Modal Manage_tags -> "tags/gerer"
  | Modal (Plant id) -> "plante/" ^ Plant_id.to_string id
  | Modal (Edit_plant id) -> "plante/" ^ Plant_id.to_string id ^ "/modifier"
  | Modal New_plant -> "plante/nouvelle"
  | Modal (Observation id) -> "observation/" ^ Observation_id.to_string id
  | Modal (Change_species id) ->
      "observation/" ^ Observation_id.to_string id ^ "/espece"
  | Modal (Identify id) -> "a-identifier/" ^ Observation_id.to_string id
  | Modal Record -> "noter"
  | Modal (Saved id) -> "noter/enregistre/" ^ Observation_id.to_string id
  | Dev name -> dev_prefix ^ name

let fragment () = Jstr.to_string (Uri.fragment (Window.location G.window))
let current () = of_fragment (fragment ())

let with_route route k =
  let here = Window.location G.window in
  match Uri.with_uri ~fragment:(Jstr.v (to_fragment route)) here with
  | Ok uri -> k uri
  | Error e -> Console.(error [str "route: bad fragment"; str e])

let go route = with_route route (Window.set_location G.window)

(* [location.replace] fires [hashchange] like an assignment, without a new
   history entry. *)
let replace route = with_route route Herbier_bindings.Location.replace

let canonicalize route =
  match String.equal (fragment ()) (to_fragment route) with
  | true -> ()
  | false ->
      with_route route (fun uri ->
          Window.History.replace_state ~uri (Window.history G.window))

let back () = Window.History.back (Window.history G.window)
