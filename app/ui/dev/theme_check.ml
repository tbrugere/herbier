open Brr

(* The groups of _tokens.sass that are not colours. *)
let non_colour_prefixes =
  [
    "--font-";
    "--space-";
    "--grid-";
    "--touch-";
    "--button-";
    "--radius-";
    "--shadow-";
    "--hero-";
  ]

(* Every colour custom property of _tokens.sass, read from the loaded
   stylesheet so a new colour shows up without editing this page. *)
let colours () =
  Herbier_bindings.Css_var.root_names ()
  |> List.filter (fun n ->
      not
        (List.exists
           (fun prefix -> String.starts_with ~prefix n)
           non_colour_prefixes))

(* A type role: its class in _base.sass and a sample text. *)
type role = {cls : string; sample : string}

let roles =
  [
    {cls = "t-screen-title"; sample = "Collection"};
    {cls = "t-sheet-title"; sample = "Bois de la Cambre"};
    {cls = "t-list-name"; sample = "Digitale pourpre"};
    {cls = "t-list-sci"; sample = "Digitalis purpurea"};
    {
      cls = "t-body";
      sample = "Bisannuelle des lisières et des coupes forestières.";
    };
    {
      cls = "t-notes";
      sample = "Une grande colonie au bord du chemin, en pleine floraison.";
    };
    {cls = "t-meta"; sample = "12 juin 2026 · 14:32 · Bois de la Cambre"};
    {cls = "t-section-label"; sample = "Mes notes"};
    {cls = "t-section-label-ref"; sample = "Référence"};
    {cls = "t-tab-label"; sample = "Collection"};
    {cls = "t-button-primary"; sample = "Enregistrer"};
    {cls = "t-button-secondary"; sample = "Coller un lien"};
  ]

let cls = Html.cls

let swatch (name, value) =
  El.li
    ~at:
      [
        At.v (Jstr.v "data-token") (Jstr.v name);
        At.v (Jstr.v "data-ok") (Jstr.v (string_of_bool (value <> "")));
      ]
    [
      El.span
        ~at:
          [
            cls "dev-swatch";
            At.style (Jstr.v (Printf.sprintf "background:var(%s)" name));
          ]
        [];
      El.txt' " ";
      El.code [El.txt' name];
      El.txt' " ";
      El.span ~at:[cls "t-meta"] [El.txt' value];
    ]

(* [data-ok] on the list is false when a swatch has no value or the
   stylesheet declares no token at all. *)
let colour_list () =
  let root = Document.root G.document in
  let tokens =
    List.map (fun n -> (n, Herbier_bindings.Css_var.get root n)) (colours ())
  in
  let all_set = tokens <> [] && List.for_all (fun (_, v) -> v <> "") tokens in
  El.ul
    ~at:
      [
        At.id (Jstr.v "colours");
        At.v (Jstr.v "data-ok") (Jstr.v (string_of_bool all_set));
      ]
    (List.map swatch tokens)

let role {cls = c; sample} =
  El.li
    ~at:[At.v (Jstr.v "data-role") (Jstr.v c)]
    [
      El.span ~at:[cls "t-meta"] [El.txt' (c ^ " ")];
      El.span ~at:[cls c] [El.txt' sample];
    ]

(* The hero roles sit on a photo in the handoff: a dark block with the 5f
   scrim stands in for it. *)
let hero () =
  El.div
    ~at:[cls "dev-hero"]
    [
      El.div
        ~at:[cls "t-photo-scrim"]
        [
          El.p ~at:[cls "t-hero-name"] [El.txt' "Digitale pourpre"];
          El.p
            ~at:[cls "t-hero-sci"]
            [
              El.txt' "Digitalis purpurea ";
              El.span ~at:[cls "author"] [El.txt' "L."];
            ];
        ];
    ]

let theme_result () =
  let line k v = El.li [El.txt' (k ^ " = "); El.code [El.txt' v]] in
  match Theme.load () with
  | Error (Theme.Missing_tokens missing) ->
      El.p
        ~at:[At.id (Jstr.v "theme"); At.v (Jstr.v "data-ok") (Jstr.v "false")]
        [El.txt' ("missing: " ^ String.concat ", " missing)]
  | Ok {map = m} ->
      El.ul
        ~at:[At.id (Jstr.v "theme"); At.v (Jstr.v "data-ok") (Jstr.v "true")]
        [
          line "map.point" m.point;
          line "map.point_border" m.point_border;
          line "map.selected" m.selected;
          line "map.selected_halo" m.selected_halo;
          line "map.to_identify" m.to_identify;
          line "map.accuracy_fill" m.accuracy_fill;
          line "map.accuracy_line" m.accuracy_line;
          line "map.origin" m.origin;
        ]

let section title els =
  El.div
    ~at:[cls "dev-section"]
    (El.h2 ~at:[cls "t-section-label"] [El.txt' title] :: els)

(* The [done] line every dev page ends with, printed once the bundled
   fonts have settled so a screenshot taken after it shows the real faces. *)
let done_line () =
  let p = El.p [] in
  let fonts = Jv.get (Document.to_jv G.document) "fonts" in
  let ready : (Jv.t, Jv.Error.t) Fut.result =
    Fut.of_promise ~ok:Fun.id (Jv.get fonts "ready")
  in
  Fut.await ready (fun (_ : (Jv.t, Jv.Error.t) result) ->
      El.set_children p [El.txt' "done"]);
  p

let el () =
  El.div
    [
      El.h1 ~at:[cls "t-screen-title"] [El.txt' "Theme check"];
      section "Couleurs" [colour_list ()];
      section "Typographie"
        [El.ul ~at:[At.id (Jstr.v "roles")] (List.map role roles); hero ()];
      section "Icônes"
        [
          El.p
            ~at:[At.id (Jstr.v "icons")]
            (List.map
               (fun n ->
                 El.span ~at:[cls "icon"; At.title (Jstr.v n)] [El.txt' n])
               (List.map Widgets.Icon.name Widgets.Icon.all));
        ];
      section "Theme.load" [theme_result ()];
      done_line ();
    ]
