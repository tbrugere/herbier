open Brr
module Tab_bar = Widgets.Tab_bar
module Plant_id = Herbier_domain.Ids.Plant_id
module Observation_id = Herbier_domain.Ids.Observation_id
module Photo_id = Herbier_domain.Ids.Photo_id

type modal =
  | Tags
  | Manage_tags
  | Plant of Plant_id.t
  | Edit_plant of Plant_id.t
  | New_plant
  | Observation of Observation_id.t
  | Change_species of Observation_id.t
  | Move_point of Observation_id.t
  | Identify of Observation_id.t
  | Record
  | Recorded of {observation : Observation_id.t; identify : bool}
  | Viewer of Photo_id.t
  | Search of string
  | Link_species of Plant_id.t
  | Intercepted of {text : string; outside : bool}
  | Drive_folder

type t = Tab of Tab_bar.tab | Modal of modal | Dev of string

let dev_prefix = "dev/"
let search_prefix = "chercher/"
let intercept_prefix = "lien/"
let paste_prefix = "coller/"

let after prefix f =
  let n = String.length prefix in
  String.sub f n (String.length f - n)

(* A malformed escape (« 50% ») keeps the text as typed rather than losing it. *)
let search_query q =
  match Uri.decode_component (Jstr.v q) with
  | Ok d -> Jstr.to_string d
  | Error _ -> q

(* Cannot fail: a string from OCaml has no lone surrogate. *)
let encoded q =
  match Uri.encode_component (Jstr.v q) with
  | Ok q -> Jstr.to_string q
  | Error _ -> ""

let intercepted ~outside encoded =
  let text = search_query encoded in
  match String.trim text with
  | "" -> Tab Tab_bar.Collection
  | _ -> Modal (Intercepted {text; outside})

let of_fragment = function
  | "" | "collection" -> Tab Tab_bar.Collection
  | "carte" -> Tab Tab_bar.Map
  | "journal" -> Tab Tab_bar.Journal
  | "reglages" -> Tab Tab_bar.Settings
  | "tags" -> Modal Tags
  | "tags/gerer" -> Modal Manage_tags
  | "reglages/dossier-drive" -> Modal Drive_folder
  | "plante/nouvelle" -> Modal New_plant
  | "noter" -> Modal Record
  | "chercher" -> Modal (Search "")
  | f when String.starts_with ~prefix:dev_prefix f -> Dev (after dev_prefix f)
  (* The query may hold a '/', so it is taken whole, before the split. *)
  | f when String.starts_with ~prefix:search_prefix f ->
      Modal (Search (search_query (after search_prefix f)))
  | f when String.starts_with ~prefix:intercept_prefix f ->
      intercepted ~outside:true (after intercept_prefix f)
  | f when String.starts_with ~prefix:paste_prefix f ->
      intercepted ~outside:false (after paste_prefix f)
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
      | ["plante"; id; "lier"] -> plant id (fun id -> Link_species id)
      | ["observation"; id] -> observation id (fun id -> Observation id)
      | ["observation"; id; "espece"] ->
          observation id (fun id -> Change_species id)
      | ["observation"; id; "position"] ->
          observation id (fun id -> Move_point id)
      | ["a-identifier"; id] -> observation id (fun id -> Identify id)
      | ["noter"; "enregistre"; id] ->
          observation id (fun observation ->
              Recorded {observation; identify = false})
      | ["noter"; "enregistre"; id; "identifier"] ->
          observation id (fun observation ->
              Recorded {observation; identify = true})
      | ["photo"; id] -> (
          match Photo_id.of_string id with
          | Some id -> Modal (Viewer id)
          | None -> Tab Tab_bar.Collection)
      | _ -> Tab Tab_bar.Collection)

let to_fragment = function
  | Tab Tab_bar.Collection -> "collection"
  | Tab Tab_bar.Map -> "carte"
  | Tab Tab_bar.Journal -> "journal"
  | Tab Tab_bar.Settings -> "reglages"
  | Modal Tags -> "tags"
  | Modal Manage_tags -> "tags/gerer"
  | Modal Drive_folder -> "reglages/dossier-drive"
  | Modal (Plant id) -> "plante/" ^ Plant_id.to_string id
  | Modal (Edit_plant id) -> "plante/" ^ Plant_id.to_string id ^ "/modifier"
  | Modal New_plant -> "plante/nouvelle"
  | Modal (Observation id) -> "observation/" ^ Observation_id.to_string id
  | Modal (Change_species id) ->
      "observation/" ^ Observation_id.to_string id ^ "/espece"
  | Modal (Move_point id) ->
      "observation/" ^ Observation_id.to_string id ^ "/position"
  | Modal (Identify id) -> "a-identifier/" ^ Observation_id.to_string id
  | Modal Record -> "noter"
  | Modal (Recorded {observation; identify = false}) ->
      "noter/enregistre/" ^ Observation_id.to_string observation
  | Modal (Recorded {observation; identify = true}) ->
      "noter/enregistre/" ^ Observation_id.to_string observation ^ "/identifier"
  | Modal (Viewer id) -> "photo/" ^ Photo_id.to_string id
  | Modal (Search "") -> "chercher"
  | Modal (Search q) -> search_prefix ^ encoded q
  | Modal (Link_species id) -> "plante/" ^ Plant_id.to_string id ^ "/lier"
  | Modal (Intercepted {text; outside = true}) ->
      intercept_prefix ^ encoded text
  | Modal (Intercepted {text; outside = false}) -> paste_prefix ^ encoded text
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
