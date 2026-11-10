module Http = Herbier_refs_io.Http
module Source = Herbier_domain.Reference.Source

let append log text = Brr.El.append_children log [Brr.El.div [Brr.El.txt' text]]

let in_flight () =
  String.concat "," (List.map Source.to_string (Http.in_flight ()))

let gbif id =
  (Source.Gbif, Printf.sprintf "https://api.gbif.org/v1/species/%d" id)

let wikidata id =
  ( Source.Wikidata,
    Printf.sprintf
      "https://www.wikidata.org/w/api.php?action=wbgetentities&ids=Q%d&format=json&origin=*"
      id )

let no_timeout (source, url) = (source, url, None)

let calls =
  (List.init 5 (fun i -> [gbif (5414463 + i); wikidata (158979 + i)])
  |> List.concat
  |> List.map no_timeout)
  @ List.map no_timeout
      [
        gbif 5414463;
        wikidata 158979;
        ( Source.Wikipedia,
          "https://fr.wikipedia.org/api/rest_v1/page/summary/Digitalis_purpurea"
        );
        (Source.Inat, "https://api.inaturalist.org/v1/taxa/53719");
      ]
  @ [
      no_timeout (gbif 99999999);
      (* Q158990 is not fetched earlier, so the HTTP cache cannot answer
         within the 1 ms timeout. *)
      (let source, url = wikidata 158990 in
       (source, url, Some 1));
      no_timeout (wikidata 158980);
    ]

let run log =
  append log ("user agent: " ^ Http.user_agent);
  let results =
    List.mapi
      (fun i (source, url, timeout_ms) ->
        let fut = Http.get ?timeout_ms source url in
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
        (Printf.sprintf "done: %d ok, %d errors" ok (List.length results - ok)))

let el () =
  let log =
    Brr.El.div
      ~at:[Brr.At.v (Jstr.v "role") (Jstr.v "log")]
      [Brr.El.h1 [Brr.El.txt' "Reference HTTP check"]]
  in
  run log;
  log
