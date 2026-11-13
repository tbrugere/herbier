open Brr
module Link = Herbier_domain.Link
module Resolve = Herbier_refs.Resolve
module Resolver = Herbier_refs_io.Resolver
module Taxon = Herbier_refs.Sources.Gbif.Taxon
module Plants = Herbier_store.Plants
module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id
module Db = Herbier_store.Db

let append log text = El.append_children log [El.div [El.txt' text]]

let examples =
  [
    "https://www.gbif.org/species/5414995";
    "https://identify.plantnet.org/fr/k-world-flora/species/Digitalis%20purpurea%20L./data";
    "https://plantuse.plantnet.org/fr/Digitalis_purpurea";
    "https://fr.wikipedia.org/wiki/Digitale_pourpre";
    "https://inpn.mnhn.fr/espece/cd_nom/94959";
    "https://www.tela-botanica.org/bdtfx-nn-22437-synthese";
    "https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:802077-1";
    "https://www.inaturalist.org/taxa/53983-Digitalis-purpurea";
    "https://www.gbif.org/species/5334357";
    "https://identify.plantnet.org/fr/observations/1012345678";
    "digitale pourpre";
  ]

let taxon (t : Taxon.t) =
  Printf.sprintf "%d %s · %s" t.key t.scientific_name
    (Option.value t.family ~default:"-")

let outcome_to_string = function
  | Resolve.Taxon t -> "taxon " ^ taxon t
  | Resolve.Candidates ts ->
      Printf.sprintf "%d candidates: %s" (List.length ts)
        (String.concat ", "
           (List.filteri
              (fun i _ -> i < 5)
              (List.map (fun (t : Taxon.t) -> string_of_int t.key) ts)))
  | Resolve.Unresolved {query; why} ->
      Printf.sprintf "unresolved (%s), query %S"
        (match why with
        | Resolve.No_species -> "no species"
        | Resolve.Observation_link -> "observation"
        | Resolve.Unavailable m -> "unavailable: " ^ m)
        query

let line link outcome = Link.to_string link ^ " → " ^ outcome_to_string outcome

let rec run_examples log = function
  | [] -> append log "examples done"
  | text :: rest ->
      Fut.await (Resolver.resolve_text text) (fun (link, outcome) ->
          append log (line link outcome);
          run_examples log rest)

let button label = El.button ~at:[At.type' (Jstr.v "button")] [El.txt' label]

let on_click el f =
  ignore (Ev.listen Ev.click (fun _ -> f ()) (El.as_target el) : Ev.listener)

let set_disabled el disabled =
  El.set_at At.Name.disabled
    (match disabled with true -> Some Jstr.empty | false -> None)
    el

let page app =
  let log = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "log")] [] in
  let examples_button = button "Exemples" in
  on_click examples_button (fun () -> run_examples log examples);
  let input =
    El.input
      ~at:
        [
          At.type' (Jstr.v "text");
          At.v (Jstr.v "aria-label") (Jstr.v "Lien ou texte");
          At.v (Jstr.v "placeholder") (Jstr.v "Lien ou texte");
        ]
      ()
  in
  let resolve_button = button "Résoudre" in
  let search_button = button "Chercher" in
  on_click search_button (fun () ->
      Route.go
        (Route.Modal
           (Route.Search (Jstr.to_string (El.prop El.Prop.value input)))));
  let sheet_button = button "4j" in
  on_click sheet_button (fun () ->
      match String.trim (Jstr.to_string (El.prop El.Prop.value input)) with
      | "" -> append log "4j: type a link or a text first"
      | text ->
          Route.go (Route.Modal (Route.Intercepted {text; outside = false})));
  (* Shown here because the console never gets user text. *)
  let received =
    El.p
      [
        El.txt'
          ("Dernier lien reçu : "
          ^ match Intake.last () with Some t -> t | None -> "aucun");
      ]
  in
  let result = El.p [] in
  let select =
    El.select ~at:[At.v (Jstr.v "aria-label") (Jstr.v "Plante")] []
  in
  let link_button = button "Lier" in
  set_disabled link_button true;
  (* style: the last resolved taxon, written by the click handlers only. *)
  let resolved = ref None in
  on_click resolve_button (fun () ->
      let text = Jstr.to_string (El.prop El.Prop.value input) in
      El.set_children result [El.txt' "…"];
      resolved := None;
      set_disabled link_button true;
      Fut.await (Resolver.resolve_text text) (fun (link, outcome) ->
          El.set_children result [El.txt' (line link outcome)];
          match outcome with
          | Resolve.Taxon t ->
              resolved := Some t;
              set_disabled link_button false
          | Resolve.Candidates _ | Resolve.Unresolved _ -> ()));
  Fut.await
    (Db.all (App.db app) Plants.list)
    (function
      | Error e -> append log ("plants: " ^ Db.error_to_string e)
      | Ok plants ->
          El.set_children select
            (List.map
               (fun (p : Plant.t) ->
                 El.option
                   ~at:[At.value (Jstr.v (Plant_id.to_string p.id))]
                   [El.txt' p.display_name])
               plants));
  on_click link_button (fun () ->
      let chosen = Jstr.to_string (El.prop El.Prop.value select) in
      match (!resolved, Plant_id.of_string chosen) with
      | Some t, Some id ->
          Fut.await (App.link app id t) (function
            | Ok () -> Route.go (Route.Modal (Plant id))
            | Error App.Plant_gone -> append log "link: plant gone"
            | Error (App.Store e) -> append log ("link: " ^ Db.error_to_string e))
      | None, _ -> append log "link: resolve a taxon first"
      | _, None -> append log "link: choose a plant");
  [
    El.h1 [El.txt' "Link check"];
    El.p [examples_button];
    received;
    El.p [input; resolve_button; search_button; sheet_button];
    result;
    El.p [select; link_button];
    log;
  ]

let el app =
  El.div
    (match app with
    | Error e -> [El.p [El.txt' ("no app: " ^ e)]]
    | Ok app -> page app)
