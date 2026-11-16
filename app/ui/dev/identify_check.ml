open Brr
module Cap_camera = Herbier_bindings.Cap_camera
module Cap_error = Herbier_bindings.Cap_error
module Canvas_jpeg = Herbier_bindings.Canvas_jpeg
module Image_bitmap = Herbier_bindings.Image_bitmap
module Js_error = Herbier_bindings.Js_error
module Web_path = Herbier_bindings.Web_path
module Fut_result = Herbier_bindings.Fut_result
module Preview = Herbier_photos_io.Preview
module Preview_size = Herbier_photos.Preview_size
module Plantnet = Herbier_identify.Plantnet
module Proposal = Herbier_identify.Proposal
module Fetch = Brr_io.Fetch

let api = "https://my-api.plantnet.org/v2"

(* No message names the URL: it holds the key. A JS error's name and message
   carry no URL in Chromium (see docs/notes/plantnet-webview.md). *)
let js_error e = Jstr.to_string (Jv.Error.name e) ^ ": " ^ Js_error.message e
let encode s = Result.map Jstr.to_string (Uri.encode_component (Jstr.v s))

let projects_url ~key =
  Result.map (fun key -> api ^ "/projects?lang=fr&api-key=" ^ key) (encode key)

let identify_url ~key ~flora =
  let open Result.Syntax in
  let* key = encode key in
  let+ flora = encode flora in
  api
  ^ "/identify/"
  ^ flora
  ^ "?include-related-images=true&lang=fr&nb-results=5&api-key="
  ^ key

let answer log ~label body =
  El.append_children log
    [
      El.details
        [
          El.summary [El.txt' (label ^ " (réponse)")];
          El.pre ~at:[At.v (Jstr.v "data-answer") (Jstr.v label)] [El.txt body];
        ];
    ]

(* Long enough for five previews on a slow mobile link, so the timing is
   measured; a stalled request still ends and frees the buttons. *)
let timeout_ms = 60_000

(* One request, its line and its body; true when Pl@ntNet answered 2xx. [url]
   is the Error of an unencodable key or flora (a lone surrogate): logged as a
   failure, nothing sent. A timeout logs [AbortError] with its duration. *)
let send log ~label ~photos ~bytes ~method' ?body url =
  let open Fut.Syntax in
  let now () = Performance.now_ms G.performance in
  let start = now () in
  let failed e =
    Kit.append log
      (Printf.sprintf "%s: failed (%s) after %.0f ms" label (js_error e)
         (now () -. start));
    false
  in
  match url with
  | Error e -> Fut.return (failed e)
  | Ok url ->
      let abort = Abort.controller () in
      let timer = G.set_timeout ~ms:timeout_ms (fun () -> Abort.abort abort) in
      let init =
        Fetch.Request.init ~method':(Jstr.v method') ?body
          ~signal:(Abort.signal abort) ()
      in
      let+ ok =
        let* response = Fetch.url ~init (Jstr.v url) in
        match response with
        | Error e -> Fut.return (failed e)
        | Ok response -> (
            let+ text = Fetch.Body.text (Fetch.Response.as_body response) in
            match text with
            | Error e -> failed e
            | Ok text ->
                Kit.append log
                  (Printf.sprintf
                     "%s: HTTP %d in %.0f ms, %d photo(s), %d bytes sent, %d \
                      chars answered"
                     label
                     (Fetch.Response.status response)
                     (now () -. start)
                     photos bytes (Jstr.length text));
                answer log ~label text;
                Fetch.Response.ok response)
      in
      G.stop_timer timer;
      ok

let form jpegs =
  let data = Brr_io.Form.Data.create () in
  List.iteri
    (fun i jpeg ->
      Brr_io.Form.Data.append data (Jstr.v "organs") (Jstr.v "auto");
      Brr_io.Form.Data.append_blob
        ~filename:(Jstr.v (Printf.sprintf "photo-%d.jpg" (i + 1)))
        data (Jstr.v "images") jpeg)
    jpegs;
  data

let identify log ~label ~key ~flora jpegs =
  send log ~label ~photos:(List.length jpegs)
    ~bytes:(List.fold_left (fun n b -> n + Blob.byte_length b) 0 jpegs)
    ~method':"POST"
    ~body:(Fetch.Body.of_form_data (form jpegs))
    (identify_url ~key ~flora)

(* The chosen photos, at least one: the first and the rest. *)
let originals ~limit =
  let open Fut.Result_syntax in
  let* media =
    Fut_result.map_error
      (fun e -> "choix : " ^ Cap_error.to_string e)
      (Cap_camera.choose_photos ~limit)
  in
  let blob (m : Cap_camera.media) =
    Fut_result.map_error (fun e -> "lecture : " ^ e) (Web_path.blob m.web_path)
  in
  match media with
  | [] -> Fut.return (Error "aucune photo choisie")
  | first :: rest ->
      let* first = blob first in
      let+ rest = Fut_result.traverse blob rest in
      (first, rest)

let preview original =
  Fut.map
    (function
      | Ok (p : Preview.t) -> Ok p.jpeg
      | Error e -> Error ("aperçu : " ^ Preview.error_to_string e))
    (Preview.make original)

(* Preview.make's pipeline (bitmap, fit, draw, encode) on the same original:
   only the quality differs from the preview. *)
let q09 original =
  let open Fut.Result_syntax in
  let* bitmap =
    Fut_result.map_error
      (fun e -> "q0.9 : " ^ Cap_error.to_string e)
      (Image_bitmap.of_blob original)
  in
  let width, height =
    Preview_size.fit
      ~width:(Image_bitmap.width bitmap)
      ~height:(Image_bitmap.height bitmap)
  in
  let* canvas =
    Fut.return
      (Result.map_error
         (fun e -> "q0.9 : " ^ Cap_error.to_string e)
         (Canvas_jpeg.draw ~width ~height bitmap))
  in
  Fut_result.map_error
    (function
      | Canvas_jpeg.Encode e -> "q0.9 : " ^ Cap_error.to_string e
      | Canvas_jpeg.Not_jpeg type' -> "q0.9 : " ^ type' ^ ", pas du JPEG")
    (Canvas_jpeg.encode ~quality:0.9 canvas)

let previews originals = Fut_result.traverse preview originals

let or_log log fut =
  Fut.map (function Ok () -> () | Error e -> Kit.append log e) fut

let previews_of ~limit ~label log ~key ~flora () =
  or_log log
    (let open Fut.Result_syntax in
     let* first, rest = originals ~limit in
     let* jpegs = previews (first :: rest) in
     Fut.map (fun _ -> Ok ()) (identify log ~label ~key ~flora jpegs))

(* q09 is sent only when the preview got its answer: a failed first request
   would leave nothing to compare it with. *)
let qualities log ~key ~flora () =
  or_log log
    (let open Fut.Result_syntax in
     let* original, _ = originals ~limit:1 in
     let* preview = previews [original] in
     let* q09 = q09 original in
     let label = Printf.sprintf "q%02.0f" (Preview_size.quality *. 10.) in
     let* ok = Fut.map Result.ok (identify log ~label ~key ~flora preview) in
     match ok with
     | true ->
         Fut.map (fun _ -> Ok ()) (identify log ~label:"q09" ~key ~flora [q09])
     | false -> Fut.return (Error "q09: not sent, the preview's request failed"))

let projects log ~key ~flora:_ () =
  Fut.map ignore
    (send log ~label:"projects" ~photos:0 ~bytes:0 ~method':"GET"
       (projects_url ~key))

let data name value = At.v (Jstr.v name) (Jstr.v value)

let thumb ~name (i : Plantnet.image) =
  let alt =
    Option.fold ~none:name
      ~some:(fun o -> name ^ ", " ^ Herbier_identify.Organ.label o)
      i.organ
  in
  El.img
    ~at:
      [
        At.src (Jstr.v i.small);
        At.v (Jstr.v "alt") (Jstr.v alt);
        At.title (Jstr.v (Proposal.credit i));
        At.v (Jstr.v "loading") (Jstr.v "lazy");
      ]
    ()

let proposal (p : Plantnet.proposal) =
  let line =
    Printf.sprintf "%.0f %% · %s · %s · %s · GBIF %s" (p.score *. 100.)
      p.scientific_name
      (Option.value p.family ~default:"—")
      (String.concat ", " p.common_names)
      (Option.fold ~none:"—" ~some:string_of_int p.gbif)
  in
  El.li
    ~at:[data "data-score" (Printf.sprintf "%g" p.score)]
    (El.txt' line
     :: List.map (thumb ~name:p.scientific_name) (Proposal.closest p)
    @ Option.to_list (Option.map El.txt' (Proposal.more_label p)))

let error_text : App.identify_error -> string = function
  | Identify_offline -> "hors-ligne : rien envoyé"
  | Preview_unreadable id ->
      "aperçu illisible : "
      ^ Herbier_domain.Ids.Photo_id.to_string id
      ^ ", rien envoyé"
  | Plantnet e -> "erreur : " ^ Plantnet.error_to_string e

let show_identified log = function
  | App.Superseded -> Kit.append log "réponse dépassée"
  | Settled (Error e) -> Kit.append log (error_text e)
  | Settled (Ok ({answer; uncertain} : Herbier_identify.identified)) ->
      Kit.append log
        (Printf.sprintf "flore : %s, reste : %s, incertain : %b"
           (Option.value answer.flora ~default:"?")
           (Option.fold ~none:"?" ~some:string_of_int answer.remaining)
           uncertain);
      El.append_children log
        [
          El.ol
            ~at:[data "data-proposals" ""]
            (List.map proposal answer.proposals);
        ]

let app_floras app log ~key ~flora:_ () =
  Fut.map
    (function
      | Ok l -> Kit.append log (Printf.sprintf "flores : %d" (List.length l))
      | Error e -> Kit.append log ("flores : " ^ error_text e))
    (App.floras app ~key)

let app_identify app channel log ~key ~flora image =
  Fut.map (show_identified log)
    (App.identify app channel ~key ~flora
       [(image, Herbier_identify.Organ.Auto)])

let app_gallery app channel log ~key ~flora () =
  or_log log
    (let open Fut.Result_syntax in
     let* original, _ = originals ~limit:1 in
     let* jpegs = previews [original] in
     match jpegs with
     | [] -> Fut.return (Error "aucun aperçu")
     | jpeg :: _ ->
         Fut.map Result.ok
           (app_identify app channel log ~key ~flora (App.Preview jpeg)))

let app_stored app channel log ~key ~flora () =
  Fut.bind
    (Herbier_store_io.Db.all (App.db app) Herbier_store.Photos.live)
    (function
      | Error e ->
          Fut.return
            (Kit.append log
               ("photos : " ^ Herbier_store_io.Db.error_to_string e))
      | Ok [] -> Fut.return (Kit.append log "aucune photo stockée")
      | Ok ((p : Herbier_domain.Photo.t) :: _) ->
          app_identify app channel log ~key ~flora (App.Stored p.id))

let input ~label ~type' ~value =
  El.input
    ~at:
      [
        At.type' (Jstr.v type');
        At.value (Jstr.v value);
        At.v (Jstr.v "autocomplete") (Jstr.v "off");
        At.v (Jstr.v "aria-label") (Jstr.v label);
        At.v (Jstr.v "placeholder") (Jstr.v label);
      ]
    ()

(* The spike's buttons: one request at a time (all disabled while one is in
   flight), a blank key refused, both fields trimmed. *)
let spike_buttons ~key_value ~flora_value log actions =
  let wired = List.map (fun (label, run) -> (Kit.button label, run)) actions in
  let buttons = List.map fst wired in
  let set_busy busy = List.iter (fun b -> Kit.set_disabled b busy) buttons in
  List.iter
    (fun (button, run) ->
      Kit.on_click button (fun () ->
          match String.trim (key_value ()) with
          | "" -> Kit.append log "pas de clé"
          | k ->
              set_busy true;
              Fut.await
                (run log ~key:k ~flora:(String.trim (flora_value ())) ())
                (fun () -> set_busy false)))
    wired;
  buttons

(* Unlike the spike's buttons: fields untrimmed and never disabled (see the
   mli). *)
let app_buttons ~key_value ~flora_value log actions =
  List.map
    (fun (label, run) ->
      let button = Kit.button label in
      Kit.on_click button (fun () ->
          Fut.await
            (run log ~key:(key_value ()) ~flora:(flora_value ()) ())
            Fun.id);
      button)
    actions

let app_block app ~key_value ~flora_value =
  let log = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "log")] [] in
  match app with
  | Error e ->
      let buttons =
        List.map Kit.button
          [
            "Flores (Identify_io)";
            "Identifier 1 photo (Identify_io)";
            "Identifier le dernier aperçu stocké";
          ]
      in
      List.iter (fun b -> Kit.set_disabled b true) buttons;
      El.div
        [
          El.h2 [El.txt' "Identify_io"];
          El.p [El.txt' ("no app: " ^ e)];
          El.div buttons;
          log;
        ]
  | Ok app ->
      let channel = App.channel () in
      let buttons =
        app_buttons ~key_value ~flora_value log
          [
            ("Flores (Identify_io)", app_floras app);
            ("Identifier 1 photo (Identify_io)", app_gallery app channel);
            ("Identifier le dernier aperçu stocké", app_stored app channel);
          ]
      in
      El.div [El.h2 [El.txt' "Identify_io"]; El.div buttons; log]

let el app =
  let log = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "log")] [] in
  let key = input ~label:"Clé API (essai)" ~type':"password" ~value:""
  and flora = input ~label:"Flore" ~type':"text" ~value:"all" in
  let value field = Jstr.to_string (El.prop El.Prop.value field) in
  let key_value () = value key and flora_value () = value flora in
  let buttons =
    spike_buttons ~key_value ~flora_value log
      [
        ("Flores (gratuit)", projects);
        ("1 aperçu", previews_of ~limit:1 ~label:"one");
        ("Aperçu q0.7 et q0.9", qualities);
        ("5 aperçus", previews_of ~limit:5 ~label:"five");
      ]
  in
  El.div
    [
      El.h1 [El.txt' "Identify check"];
      El.div [key; flora];
      El.div buttons;
      log;
      app_block app ~key_value ~flora_value;
    ]
