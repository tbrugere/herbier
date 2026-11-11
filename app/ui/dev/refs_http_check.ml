module Http = Herbier_refs_io.Http
module Source = Herbier_domain.Reference.Source
module Request = Herbier_refs.Request
module Decode = Herbier_refs.Decode
module Gbif = Herbier_refs.Sources.Gbif
module Wikidata = Herbier_refs.Sources.Wikidata
module Wikipedia = Herbier_refs.Sources.Wikipedia

let append log text = Brr.El.append_children log [Brr.El.div [Brr.El.txt' text]]

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
  fixed @ [wikidata_search; wikidata_entity; wikipedia_summary]

let decode_all log =
  let results =
    List.map
      (fun {name; request; summary} ->
        Fut.map
          (fun r ->
            append log
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
  Fut.await (Fut.of_list results) (fun _ -> append log "decode done")

let run log =
  append log ("user agent: " ^ Http.user_agent);
  let results =
    List.mapi
      (fun i ((request : Request.t), timeout_ms) ->
        let source = request.source in
        let fut = Http.get ?timeout_ms request in
        append log
          (Printf.sprintf "#%d %s queued · in flight: %s" i
             (Source.to_string source) (in_flight ()));
        Fut.map
          (fun r ->
            append log
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
      append log
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
