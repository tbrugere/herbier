module Json = Herbier_net.Json
module Source = Herbier_domain.Reference.Source

let base = "https://api.tela-botanica.org/service:eflore:0.1"
let request path query = Request.make Source.Tela ~base ~path ~query

let names ~name =
  match String.trim name with
  | "" -> None
  | name ->
      Some
        (request ["bdtfx"; "noms"] [("masque", name); ("retour.format", "min")])

let taxon ~nn = request ["bdtfx"; "taxons"; string_of_int nn] []

let baseflor ~nn =
  request ["baseflor"; "informations"; "bdtfx.nn:" ^ string_of_int nn] []

type name = {nn : int; nom_sci : string; retenu : bool} [@@deriving eq, show]

let retenu json =
  match Json.member "retenu" json with
  | Some (`String "true") | Some (`Bool true) -> true
  | Some _ | None -> false

let names_of_json json =
  match Json.member "resultat" json with
  | Some (`Assoc members) ->
      Ok
        (List.filter_map
           (fun (key, v) ->
             match (Json.digits key, Decode.string "nom_sci" v) with
             | Some nn, Some nom_sci -> Some {nn; nom_sci; retenu = retenu v}
             | None, _ | _, None -> None)
           members)
  (* PHP encodes an empty map as []; the service answers 404 instead today. *)
  | Some (`List []) -> Ok []
  | Some _ | None -> Decode.unexpected "/resultat" "object"

let pick ~name entries =
  let name = String.trim name in
  match List.filter (fun e -> String.equal e.nom_sci name) entries with
  | [] -> None
  | first :: _ as matching -> (
      match List.find_opt (fun e -> e.retenu) matching with
      | Some e -> Some e
      | None -> Some first)

type taxon = {
  id : int;
  nom_sci : string;
  cd_nom : int option;
  presence : string option;
  statut_origine : string option;
}
[@@deriving eq, show]

let id json =
  match (json, Json.member "id" json) with
  | `Assoc _, Some (`Int i) -> Ok i
  | `Assoc _, Some (`String s) -> (
      match Json.digits s with
      | Some i -> Ok i
      | None -> Decode.unexpected "/id" "digits")
  | `Assoc _, (Some _ | None) -> Decode.unexpected "/id" "digits"
  | _ -> Decode.unexpected "" "object"

let taxon_of_json json =
  let open Decode.Syntax in
  let* id = id json in
  let+ nom_sci = Decode.required_string "nom_sci" json in
  {
    id;
    nom_sci;
    cd_nom = Option.bind (Decode.string "cd_nom" json) Json.digits;
    presence = Decode.string "presence.libelle" json;
    statut_origine = Decode.string "statut_origine.libelle" json;
  }

type baseflor = {
  floraison : string option;
  carac_ecolo : string option;
  chorologie : string option;
  type_bio : string option;
  lumiere : string option;
  humidite_edaph : string option;
  reaction_sol : string option;
  nutriments_sol : string option;
}
[@@deriving eq, show]

let principal json =
  Option.bind (Json.member "type_bio.detail" json) (fun detail ->
      match Decode.list "type.principal" detail with
      | first :: _ -> Decode.string "libelle" first
      | [] -> None)

let baseflor_of_json json =
  let open Decode.Syntax in
  let+ (_ : string) = Decode.required_string "nom_sci" json in
  {
    floraison = Decode.string "floraison" json;
    carac_ecolo = Decode.string "carac_ecolo" json;
    chorologie = Decode.string "chorologie" json;
    type_bio =
      (match principal json with
      | Some _ as p -> p
      | None -> Decode.string "type_bio.libelle" json);
    lumiere = Decode.string "ve_lumiere.libelle" json;
    humidite_edaph = Decode.string "ve_humidite_edaph.libelle" json;
    reaction_sol = Decode.string "ve_reaction_sol.libelle" json;
    nutriments_sol = Decode.string "ve_nutriments_sol.libelle" json;
  }
