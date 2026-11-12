open Brr
module Geocode = Herbier_geo.Geocode
module Geocoder = Herbier_geo.Geocoder
module Places = Herbier_domain.Places

let append log text = El.append_children log [El.div [El.txt' text]]
let schlucht = {Places.lat = 48.0633; lon = 7.0081}

let points =
  [
    ("schlucht", schlucht);
    ("landes", {Places.lat = 44.25; lon = -0.85});
    ("lausanne", {Places.lat = 46.5197; lon = 6.6323});
    ("kew", {Places.lat = 51.4787; lon = -0.2956});
    ("atlantic", {Places.lat = 46.2; lon = -5.0});
  ]

let now_ms () = Performance.now_ms G.performance

let on_start log t0 (r : Geocode.request) =
  append log
    (Printf.sprintf "%6.0f ms start %s %s"
       (now_ms () -. t0)
       (Geocode.provider_to_string r.provider)
       r.url)

let outcome = function
  | Ok (Some phrase) -> phrase
  | Ok None -> "aucun lieu"
  | Error e -> "error: " ^ Geocoder.error_to_string e

let run_reverse log =
  let t0 = now_ms () in
  let remaining = ref (List.length points) in
  List.iter
    (fun (name, p) ->
      Fut.await
        (Geocoder.reverse ~on_start:(on_start log t0) p)
        (fun r ->
          append log
            (Printf.sprintf "%6.0f ms %s: %s"
               (now_ms () -. t0)
               name (outcome r));
          decr remaining;
          match !remaining with 0 -> append log "reverse done" | _ -> ()))
    points

let place (p : Geocode.place) =
  Printf.sprintf "%s — %s (%s, %s)" p.name
    (Option.value p.context ~default:"")
    (Geocode.coordinate p.point.lat)
    (Geocode.coordinate p.point.lon)

let button label = El.button ~at:[At.type' (Jstr.v "button")] [El.txt' label]

let on_click el f =
  ignore (Ev.listen Ev.click (fun _ -> f ()) (El.as_target el) : Ev.listener)

let el () =
  let log = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "log")] [] in
  let reverse_button = button "Inverse" in
  on_click reverse_button (fun () -> run_reverse log);
  let input =
    El.input
      ~at:
        [
          At.type' (Jstr.v "text");
          At.v (Jstr.v "aria-label") (Jstr.v "Lieu");
          At.v (Jstr.v "placeholder") (Jstr.v "Lieu");
        ]
      ()
  in
  let search_button = button "Chercher" in
  let results = El.ul [] in
  on_click search_button (fun () ->
      let q = Jstr.to_string (El.prop El.Prop.value input) in
      let t0 = now_ms () in
      El.set_children results [];
      Fut.await
        (Geocoder.search ~on_start:(on_start log t0) ~near:schlucht q)
        (function
          | Error e -> append log ("search: " ^ Geocoder.error_to_string e)
          | Ok places ->
              append log
                (Printf.sprintf "search: %d places" (List.length places));
              El.set_children results
                (List.map (fun p -> El.li [El.txt' (place p)]) places)));
  El.div
    [
      El.h1 [El.txt' "Geocode check"];
      El.p [reverse_button];
      El.p [input; search_button];
      results;
      log;
    ]
