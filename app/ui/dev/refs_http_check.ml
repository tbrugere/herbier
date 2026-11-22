module Http = Herbier_refs_io.Http
module Source = Herbier_domain.Reference.Source
module Request = Herbier_refs.Request
module Decode = Herbier_refs.Decode
module Gbif = Herbier_refs.Sources.Gbif
module Wikidata = Herbier_refs.Sources.Wikidata
module Wikipedia = Herbier_refs.Sources.Wikipedia
module Tela = Herbier_refs.Sources.Tela
module Inpn = Herbier_refs.Sources.Inpn
module Plantuse = Herbier_refs.Sources.Plantuse
module Payload = Herbier_refs.Payload
module Fanout = Herbier_refs.Fanout
module Regional = Herbier_refs.Regional
module Projection = Herbier_refs.Projection
module Reference = Herbier_domain.Reference

let in_flight () =
  String.concat "," (List.map Source.to_string (Http.in_flight ()))

let gbif id =
  Request.make Source.Gbif ~base:"https://api.gbif.org/v1"
    ~path:["species"; string_of_int id]
    ~query:[]

let wikidata id =
  Request.make Source.Wikidata ~base:"https://www.wikidata.org/w/api.php"
    ~path:[]
    ~query:
      [
        ("action", "wbgetentities");
        ("ids", Printf.sprintf "Q%d" id);
        ("format", "json");
        ("origin", "*");
      ]

let no_timeout request = (request, None)

let calls =
  (List.init 5 (fun i -> [gbif (5414463 + i); wikidata (158979 + i)])
  |> List.concat
  |> List.map no_timeout)
  @ List.map no_timeout
      [
        gbif 5414463;
        wikidata 158979;
        Request.make Source.Wikipedia
          ~base:"https://fr.wikipedia.org/api/rest_v1/page/summary"
          ~path:["Digitalis_purpurea"] ~query:[];
        Request.make Source.Inat ~base:"https://api.inaturalist.org/v1"
          ~path:["taxa"; "53719"] ~query:[];
      ]
  @ [
      no_timeout (gbif 99999999);
      (* Q158990 is not fetched earlier, so the HTTP cache cannot answer
         within the 1 ms timeout. *)
      (wikidata 158990, Some 1);
      no_timeout (wikidata 158980);
    ]

(* One request description of refs/sources and how to summarise its decoded
   payload in one line. *)
type described = {
  name : string;
  request : Request.t;
  summary : Yojson.Safe.t -> (string, Decode.error) result;
}

let digitalis = 5414995
let arnica = 5405976

(* The inputs are constants that pass their request function's checks: a
   None is a bug in this page, not a skipped request. *)
let built name = function
  | Some request -> request
  | None -> failwith (name ^ ": request not built")

let described () =
  let gbif_page n page =
    Printf.sprintf "%d %s" (List.length page.Gbif.results) n
  in
  let fixed =
    [
      {
        name = "species";
        request = Gbif.species ~key:digitalis;
        summary =
          (fun json ->
            Result.map
              (fun (t : Gbif.Taxon.t) ->
                Printf.sprintf "%d %s" t.key t.scientific_name)
              (Gbif.species_of_json json));
      };
      {
        name = "match_name";
        request =
          built "match_name" (Gbif.match_name ~name:"Digitalis purpurea L.");
        summary =
          (fun json ->
            Result.map
              (function
                | Gbif.No_match -> "no match"
                | Gbif.Higher_rank t -> Printf.sprintf "higher rank %d" t.key
                | Gbif.Matched {taxon; fuzzy; _} ->
                    Printf.sprintf "%s %d"
                      (match fuzzy with true -> "fuzzy" | false -> "exact")
                      taxon.key)
              (Gbif.match_of_json json));
      };
      {
        name = "suggest";
        request = Gbif.suggest ~q:"Digitalis purp";
        summary =
          (fun json ->
            Result.map
              (fun l -> Printf.sprintf "%d taxa" (List.length l))
              (Gbif.suggest_of_json json));
      };
      {
        name = "vernacular_search";
        request = Gbif.vernacular_search ~q:"digitale pourpre";
        summary =
          (fun json ->
            Result.map (gbif_page "taxa") (Gbif.vernacular_search_of_json json));
      };
      {
        name = "vernacular_names";
        request = Gbif.vernacular_names ~key:digitalis;
        summary =
          (fun json ->
            Result.map (gbif_page "names") (Gbif.vernacular_names_of_json json));
      };
      {
        name = "distributions";
        request = Gbif.distributions ~key:digitalis;
        summary =
          (fun json ->
            Result.map (gbif_page "rows") (Gbif.distributions_of_json json));
      };
      {
        name = "occurrence_count";
        request = Gbif.occurrence_count ~key:digitalis;
        summary =
          (fun json ->
            Result.map string_of_int (Gbif.occurrence_count_of_json json));
      };
      {
        name = "plantnet_media";
        request = Gbif.plantnet_media ~key:digitalis;
        summary =
          (fun json ->
            Result.map (gbif_page "images") (Gbif.plantnet_media_of_json json));
      };
    ]
  in
  let qids l = String.concat "," (List.map Herbier_refs.Qid.to_string l) in
  let wikidata_search =
    {
      name = "wikidata search";
      request =
        built "wikidata search"
          (Wikidata.search ~property:Gbif_key ~value:(string_of_int digitalis));
      summary = (fun json -> Result.map qids (Wikidata.search_of_json json));
    }
  in
  let wikidata_entity =
    {
      name = "wikidata entity";
      request =
        Wikidata.entity
          (built "wikidata entity" (Herbier_refs.Qid.of_string "Q157555"));
      summary =
        (fun json ->
          Result.map
            (function
              | None -> "missing"
              | Some (e : Wikidata.Entity.t) ->
                  Printf.sprintf "%s gbif %s, %d sitelinks"
                    (Herbier_refs.Qid.to_string e.qid)
                    (Option.fold ~none:"-" ~some:string_of_int e.gbif_key)
                    (List.length e.sitelinks))
            (Wikidata.entity_of_json json));
    }
  in
  let wikipedia_summary =
    {
      name = "wikipedia summary";
      request =
        built "wikipedia summary"
          (Wikipedia.summary ~lang:"fr" ~title:"Digitalis purpurea");
      summary =
        (fun json ->
          Result.map
            (fun (s : Wikipedia.t) ->
              Printf.sprintf "%s %s" s.title
                (Option.fold ~none:"-" ~some:Herbier_refs.Qid.to_string
                   s.wikibase_item))
            (Wikipedia.summary_of_json json));
    }
  in
  let count what decode json =
    Result.map
      (fun l -> Printf.sprintf "%d %s" (List.length l) what)
      (decode json)
  in
  let regional =
    [
      {
        name = "tela names";
        request = built "tela names" (Tela.names ~name:"Digitalis purpurea");
        summary = count "names" Tela.names_of_json;
      };
      {
        name = "tela taxon";
        request = Tela.taxon ~nn:22437;
        summary =
          (fun json ->
            Result.map
              (fun (t : Tela.taxon) ->
                Printf.sprintf "%d %s cd_nom %s" t.id t.nom_sci
                  (Option.fold ~none:"-" ~some:string_of_int t.cd_nom))
              (Tela.taxon_of_json json));
      };
      {
        name = "tela baseflor";
        request = Tela.baseflor ~nn:22437;
        summary =
          (fun json ->
            Result.map
              (fun (b : Tela.baseflor) ->
                "floraison " ^ Option.value ~default:"-" b.floraison)
              (Tela.baseflor_of_json json));
      };
      {
        name = "inpn name";
        request = Inpn.name ~cd_nom:94959;
        summary =
          (fun json ->
            Result.map
              (fun (n : Inpn.name) -> Printf.sprintf "cd_ref %d" n.cd_ref)
              (Inpn.name_of_json json));
      };
      {
        name = "inpn status";
        request = Inpn.status ~cd_ref:94959;
        summary = count "statuses" Inpn.status_of_json;
      };
      {
        name = "inpn red_list";
        request = Inpn.red_list ~cd_ref:94959;
        summary = count "entries" Inpn.red_list_of_json;
      };
      {
        name = "inpn protections";
        request = Inpn.protections ~cd_ref:94959;
        summary = count "articles" Inpn.protections_of_json;
      };
    ]
  in
  (* The « Utilisations » sources: the Pl@ntUse API answers CORS
     without a custom header, the Wikimedia one carries Api-User-Agent. *)
  let uses =
    [
      {
        name = "plantuse page";
        request =
          built "plantuse page" (Plantuse.page ~titles:["Digitalis purpurea"]);
        summary =
          (fun json ->
            Result.map
              (fun answer ->
                match Plantuse.pick ~titles:["Digitalis purpurea"] answer with
                | None -> "Pl@ntUse : no page"
                | Some page ->
                    "Pl@ntUse : "
                    ^ String.concat ", " (Plantuse.uses page).summary)
              (Plantuse.answer_of_json json));
      };
      {
        name = "wikipedia extract";
        request =
          built "wikipedia extract"
            (Wikipedia.extract ~lang:"en" ~title:"Digitalis purpurea");
        summary =
          (fun json ->
            Result.map
              (fun article ->
                match Option.bind article Wikipedia.uses_line with
                | None -> "Wikipédia : no uses section"
                | Some (section, _) -> "Wikipédia (en) : " ^ section)
              (Wikipedia.article_of_json json));
      };
    ]
  in
  fixed
  @ [wikidata_search; wikidata_entity; wikipedia_summary]
  @ regional
  @ uses

let fetch log name request =
  Fut.map
    (function
      | Error e ->
          Kit.append log (Printf.sprintf "%s: %s" name (Http.error_to_string e));
          None
      | Ok body -> (
          match Decode.json_of_string body with
          | Ok json -> Some json
          | Error e ->
              Kit.append log
                (Printf.sprintf "%s: %s" name (Decode.error_to_string e));
              None))
    (Http.get request)

let first_qid search =
  match Option.map Wikidata.search_of_json search with
  | Some (Ok (qid :: _)) -> Some qid
  | Some (Ok []) | Some (Error _) | None -> None

let sitelink entity lang =
  match Option.map Wikidata.entity_of_json entity with
  | Some (Ok (Some (e : Wikidata.Entity.t))) ->
      List.find_map
        (fun (l : Wikidata.Entity.sitelink) ->
          match String.equal l.lang lang with
          | true -> Some (lang, l.title)
          | false -> None)
        e.sitelinks
  | Some (Ok None) | Some (Error _) | None -> None

(* The fr article, else the en one (architecture §6). *)
let wiki_title entity =
  match sitelink entity "fr" with
  | Some _ as fr -> fr
  | None -> sitelink entity "en"

let optional log name = function
  | None -> Fut.return None
  | Some request -> fetch log name request

(* Fetches every part of one species live, builds its payloads and projects
   them (architecture §10, spike 5). *)
let project_one log key =
  let open Fut.Syntax in
  let label = string_of_int key in
  let* species = fetch log (label ^ " species") (Gbif.species ~key)
  and* vernacular_names =
    fetch log (label ^ " vernacular_names") (Gbif.vernacular_names ~key)
  and* distributions =
    fetch log (label ^ " distributions") (Gbif.distributions ~key)
  and* occurrence_count =
    fetch log (label ^ " occurrence_count") (Gbif.occurrence_count ~key)
  and* media = fetch log (label ^ " media") (Gbif.plantnet_media ~key)
  and* search =
    optional log (label ^ " search")
      (Wikidata.search ~property:Gbif_key ~value:label)
  in
  let* entity =
    optional log (label ^ " entity")
      (Option.map Wikidata.entity (first_qid search))
  in
  let* summary =
    optional log (label ^ " summary")
      (Option.bind (wiki_title entity) (fun (lang, title) ->
           Wikipedia.summary ~lang ~title))
  in
  (* The uses extract as the fetch reads it: fr, then en when fr has no uses
     section. *)
  let extract lang =
    optional log
      (label ^ " extract " ^ lang)
      (Option.bind (sitelink entity lang) (fun (lang, title) ->
           Wikipedia.extract ~lang ~title))
  in
  let has_uses json =
    match Option.map Wikipedia.article_of_json json with
    | Some (Ok (Some article)) -> Wikipedia.has_uses article
    | Some (Ok None) | Some (Error _) | None -> false
  in
  let* uses_extract =
    let* fr = extract "fr" in
    match has_uses fr with
    | true -> Fut.return fr
    | false ->
        Fut.map (function None -> fr | Some _ as en -> en) (extract "en")
  in
  let fetched source payload : Fanout.row =
    {source; status = Reference.Status.Complete; payload}
  in
  let gbif =
    Payload.gbif ~species ~vernacular_names ~distributions ~occurrence_count
  and wikidata = Payload.wikidata ~search ~entity in
  let input =
    Regional.input ~previous:[]
      [fetched Source.Gbif gbif; fetched Source.Wikidata wikidata]
  in
  Kit.append log
    (Format.asprintf "%s regional input: %a" label Regional.pp_input input);
  let* regional = Http.run (Regional.program input) in
  let+ uses = Http.run (Herbier_refs.Uses_fetch.program input) in
  let now = Ptime_clock.now () in
  let plant_id = Herbier_domain.Ids.Plant_id.fresh () in
  let row source payload =
    Kit.append log
      (Printf.sprintf "%s payload %s: %d bytes" label (Source.to_string source)
         (String.length (Yojson.Safe.to_string payload)));
    {
      Reference.id = Reference.id_of_key ~plant:plant_id ~source;
      plant_id;
      source;
      fetched_at = now;
      payload;
      status = Reference.Status.Complete;
      created_at = now;
      updated_at = now;
      deleted_at = None;
    }
  in
  let t =
    Projection.project ~plant_refs:[]
      ~references:
        ([
           row Source.Gbif gbif;
           row Source.Plantnet (Payload.plantnet ~media);
           row Source.Wikidata wikidata;
           row Source.Wikipedia (Payload.wikipedia ~summary ~uses:uses_extract);
         ]
        @ List.map
            (fun (r : Fanout.row) -> row r.source r.payload)
            (regional @ uses))
  in
  List.iter
    (fun field ->
      Kit.append log
        (Printf.sprintf "%s %s: %s" label
           (Projection.Field.to_string field)
           (match Projection.filled t field with
           | true -> "filled"
           | false -> "empty")))
    Projection.Field.all;
  List.iter
    (fun (p : Projection.problem) ->
      Kit.append log
        (Printf.sprintf "%s problem %s: %s" label (Payload.name p.part)
           (Decode.error_to_string p.error)))
    t.problems;
  Kit.append log
    (Printf.sprintf "%s empty fields: %d of %d" label
       (List.length (Projection.empty_fields t))
       (List.length Projection.Field.all))

let project_all log =
  let open Fut.Syntax in
  let* () = project_one log digitalis in
  let+ () = project_one log arnica in
  Kit.append log "projection done"

let decode_all log =
  let results =
    List.map
      (fun {name; request; summary} ->
        Fut.map
          (fun r ->
            Kit.append log
              (match r with
              | Error e -> Printf.sprintf "%s: %s" name (Http.error_to_string e)
              | Ok body -> (
                  match Result.bind (Decode.json_of_string body) summary with
                  | Ok text -> Printf.sprintf "%s: decoded %s" name text
                  | Error e ->
                      Printf.sprintf "%s: %s" name (Decode.error_to_string e))))
          (Http.get request))
      (described ())
  in
  Fut.await (Fut.of_list results) (fun _ ->
      Kit.append log "decode done";
      Fut.await (project_all log) Fun.id)

let run log =
  Kit.append log ("user agent: " ^ Http.user_agent);
  let results =
    List.mapi
      (fun i ((request : Request.t), timeout_ms) ->
        let source = request.source in
        let fut = Http.get ?timeout_ms request in
        Kit.append log
          (Printf.sprintf "#%d %s queued · in flight: %s" i
             (Source.to_string source) (in_flight ()));
        Fut.map
          (fun r ->
            Kit.append log
              (Printf.sprintf "#%d %s %s · in flight: %s" i
                 (Source.to_string source)
                 (match r with
                 | Ok body -> Printf.sprintf "ok, %d bytes" (String.length body)
                 | Error e -> Http.error_to_string e)
                 (in_flight ()));
            r)
          fut)
      calls
  in
  Fut.await (Fut.of_list results) (fun results ->
      let ok = List.length (List.filter Result.is_ok results) in
      Kit.append log
        (Printf.sprintf "done: %d ok, %d errors" ok (List.length results - ok));
      decode_all log)

let el () =
  let log =
    Brr.El.div
      ~at:[Brr.At.v (Jstr.v "role") (Jstr.v "log")]
      [Brr.El.h1 [Brr.El.txt' "Reference HTTP check"]]
  in
  run log;
  log
