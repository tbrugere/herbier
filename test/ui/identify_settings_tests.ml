(* Herbier_ui_model.Identify_settings (app/ui_model/identify_settings.mli):
   the Pl@ntNet key's rule and mask, the key/gate/flora_row/choice
   values, the stored settings' defaults, [choices]/[filter] over the
   recorded floras, [flora_list_error] (the generic text; the CORS cause is
   named only in App.floras' console line), and the section's French texts.

   No testable here prints a [Key.t] by its real value: pp functions show
   [Key.masked] only, so a failing [Alcotest.check] never echoes a key, real
   or fake, into the test log. *)

module Is = Herbier_ui_model.Identify_settings
module Key = Is.Key
module Plantnet = Herbier_identify.Plantnet
module Settings = Herbier_store.Settings
module Fixture = Herbier_test_support.Fixture
module Text = Herbier_test_support.Text

(* ---------- testables ---------- *)

let pp_key ppf = function
  | Is.Loading -> Format.pp_print_string ppf "Loading"
  | Is.Absent -> Format.pp_print_string ppf "Absent"
  | Is.Present k -> Format.fprintf ppf "Present %s" (Key.masked k)

let key_t = Alcotest.testable pp_key Is.equal_key

let pp_gate ppf = function
  | Is.Ready k -> Format.fprintf ppf "Ready %s" (Key.masked k)
  | Is.Waiting -> Format.pp_print_string ppf "Waiting"
  | Is.No_key -> Format.pp_print_string ppf "No_key"
  | Is.Offline -> Format.pp_print_string ppf "Offline"

let gate_t = Alcotest.testable pp_gate Is.equal_gate

let pp_note ppf = function
  | None -> Format.pp_print_string ppf "None"
  | Some s -> Format.fprintf ppf "Some %S" s

let flora_row_t =
  Alcotest.testable
    (fun ppf (r : Is.flora_row) ->
      Format.fprintf ppf "{detail = %S; note = %a; enabled = %b}" r.detail
        pp_note r.note r.enabled)
    Is.equal_flora_row

let pp_flora_opt ppf = function
  | None -> Format.pp_print_string ppf "None"
  | Some (f : Settings.flora) ->
      Format.fprintf ppf "Some {id = %S; title = %S}" f.id f.title

let choice_t =
  Alcotest.testable
    (fun ppf (c : Is.choice) ->
      Format.fprintf ppf "{flora = %a; selected = %b}" pp_flora_opt c.flora
        c.selected)
    Is.equal_choice

let error_t = Alcotest.testable Plantnet.pp_error Plantnet.equal_error
let title (c : Is.choice) = Is.flora_detail c.flora

(* ---------- fixture ---------- *)

let projects_fr =
  lazy
    (match
       Plantnet.decode_projects (Fixture.read "plantnet_projects_fr_200.json")
     with
    | Ok ps -> ps
    | Error e ->
        Alcotest.failf "decode_projects: %s" (Plantnet.error_to_string e))

(* ---------- 1. preferences_key ---------- *)

let preferences_key () =
  Alcotest.(check string)
    "preferences_key" "plantnet.api_key" Is.preferences_key

(* ---------- 2. Key.of_input ---------- *)

let key_of_input () =
  (match Key.of_input "  2b10abc  " with
  | Some k -> Alcotest.(check string) "trimmed" "2b10abc" (Key.to_string k)
  | None -> Alcotest.fail "\"  2b10abc  \" should be Some");
  List.iter
    (fun input ->
      Alcotest.(check bool)
        (Printf.sprintf "of_input %S is None" input)
        true
        (Option.is_none (Key.of_input input)))
    [""; "   "; "\n\t "];
  match Key.of_input "a b" with
  | Some k -> Alcotest.(check string) "inner space kept" "a b" (Key.to_string k)
  | None -> Alcotest.fail "\"a b\" should be Some"

(* ---------- 3. Key.masked ---------- *)

let key25 = "2b10AbCdEfGhIjKlMnOpQrStu"
let masked_of s = Key.masked (Option.get (Key.of_input s))

let key_masked () =
  Alcotest.(check string) "25 chars" "•••• rStu" (masked_of key25);
  Alcotest.(check string) "8 chars" "•••• efgh" (masked_of "abcdefgh");
  Alcotest.(check string) "7 chars" "••••" (masked_of "abcdefg");
  Alcotest.(check string) "non-ASCII tail" "•••• efgé" (masked_of "abcdefgé");
  Alcotest.(check string)
    "7 scalars in 9 bytes: counted in scalars" "••••" (masked_of "abcdeéé");
  Alcotest.(check string)
    "an invalid byte is one scalar" "•••• efg\xff" (masked_of "abcdefg\xff");
  let result = masked_of key25 in
  Alcotest.(check bool)
    "does not contain the key's first 21 characters" false
    (Text.contains ~sub:(String.sub key25 0 21) result);
  Alcotest.(check bool)
    "does not contain the key" false
    (Text.contains ~sub:key25 result)

(* ---------- 4. key_detail ---------- *)

let key_detail () =
  let k = Option.get (Key.of_input "abcdefgh") in
  Alcotest.(check string) "Loading" "…" (Is.key_detail Is.Loading);
  Alcotest.(check string) "Absent" "Aucune clé" (Is.key_detail Is.Absent);
  Alcotest.(check string)
    "Present" (Key.masked k)
    (Is.key_detail (Is.Present k))

(* ---------- 4b. key_of_stored ---------- *)

let key_of_stored () =
  let k = Option.get (Key.of_input "abcdefgh") in
  Alcotest.(check key_t) "None" Is.Absent (Is.key_of_stored None);
  Alcotest.(check key_t) "Some blank" Is.Absent (Is.key_of_stored (Some "  "));
  Alcotest.(check key_t)
    "Some key, trimmed" (Is.Present k)
    (Is.key_of_stored (Some " abcdefgh "))

(* ---------- 4c. settings_of_stored ---------- *)

let settings_of_stored () =
  let f : Settings.flora = {id = "k-x"; title = "X"} in
  let check msg ~on_photo ~flora (expected : Is.settings) =
    let got = Is.settings_of_stored ~on_photo ~flora in
    Alcotest.(check bool) (msg ^ ": on_photo") expected.on_photo got.on_photo;
    Alcotest.(check bool)
      (msg ^ ": flora") true
      (Option.equal Settings.equal_flora expected.flora got.flora)
  in
  check "unset: on, Automatique" ~on_photo:None ~flora:None
    {on_photo = true; flora = None};
  check "stored off" ~on_photo:(Some false) ~flora:None
    {on_photo = false; flora = None};
  check "stored on, a flora" ~on_photo:(Some true) ~flora:(Some f)
    {on_photo = true; flora = Some f}

(* ---------- 5. gate ---------- *)

let gate () =
  let k = Option.get (Key.of_input "abcdefgh") in
  List.iter
    (fun (key, online, expected) ->
      Alcotest.(check gate_t)
        (Printf.sprintf "online=%b" online)
        expected (Is.gate key ~online))
    [
      (Is.Loading, true, Is.Waiting);
      (Is.Loading, false, Is.Waiting);
      (Is.Absent, true, Is.No_key);
      (Is.Absent, false, Is.No_key);
      (Is.Present k, true, Is.Ready k);
      (Is.Present k, false, Is.Offline);
    ]

(* ---------- 6. opens_on_photo ---------- *)

let opens_on_photo () =
  let k = Option.get (Key.of_input "abcdefgh") in
  Alcotest.(check bool)
    "Ready, on_photo true" true
    (Is.opens_on_photo ~on_photo:true (Is.Ready k));
  Alcotest.(check bool)
    "Ready, on_photo false" false
    (Is.opens_on_photo ~on_photo:false (Is.Ready k));
  List.iter
    (fun g ->
      Alcotest.(check bool)
        "on_photo true, not Ready" false
        (Is.opens_on_photo ~on_photo:true g))
    [Is.Waiting; Is.No_key; Is.Offline]

(* ---------- 7. flora_id / flora_detail ---------- *)

let flora_id_and_detail () =
  let f : Settings.flora = {id = "k-x"; title = "X"} in
  Alcotest.(check string) "flora_id None" Plantnet.automatic (Is.flora_id None);
  Alcotest.(check string) "flora_id (Some f)" f.id (Is.flora_id (Some f));
  Alcotest.(check string)
    "flora_detail None" "Automatique" (Is.flora_detail None);
  Alcotest.(check string)
    "flora_detail (Some f)" f.title (Is.flora_detail (Some f))

(* ---------- 8. flora_row ---------- *)

let flora_row () =
  let k = Option.get (Key.of_input "abcdefgh") in
  let stored : Settings.flora = {id = "k-x"; title = "Ma flore"} in
  let check msg ~key ~online ~current expected =
    Alcotest.(check flora_row_t)
      msg expected
      (Is.flora_row ~key ~online current)
  in
  check "Loading: disabled, no note" ~key:Is.Loading ~online:true ~current:None
    {Is.detail = "Automatique"; note = None; enabled = false};
  check "Loading, a stored flora: its title" ~key:Is.Loading ~online:true
    ~current:(Some stored)
    {Is.detail = "Ma flore"; note = None; enabled = false};
  check "Absent online, a stored flora: its title" ~key:Is.Absent ~online:true
    ~current:(Some stored)
    {
      detail = "Ma flore";
      note = Some "Ajoutez votre clé API Pl@ntNet pour choisir la flore.";
      enabled = false;
    };
  check "Absent offline, a stored flora: its title" ~key:Is.Absent ~online:false
    ~current:(Some stored)
    {
      detail = "Ma flore";
      note = Some "Ajoutez votre clé API Pl@ntNet pour choisir la flore.";
      enabled = false;
    };
  check "Present online, a stored flora: its title" ~key:(Is.Present k)
    ~online:true ~current:(Some stored)
    {detail = "Ma flore"; note = None; enabled = true};
  check "Absent online: no-key note" ~key:Is.Absent ~online:true ~current:None
    {
      detail = "Automatique";
      note = Some "Ajoutez votre clé API Pl@ntNet pour choisir la flore.";
      enabled = false;
    };
  check "Present offline: offline note, stored title as detail"
    ~key:(Is.Present k) ~online:false ~current:(Some stored)
    {
      detail = "Ma flore";
      note = Some "Hors-ligne : la liste des flores demande le réseau.";
      enabled = false;
    };
  check "Present online: enabled, no note" ~key:(Is.Present k) ~online:true
    ~current:None
    {detail = "Automatique"; note = None; enabled = true};
  check "Absent offline: no-key note takes precedence over offline"
    ~key:Is.Absent ~online:false ~current:None
    {
      detail = "Automatique";
      note = Some "Ajoutez votre clé API Pl@ntNet pour choisir la flore.";
      enabled = false;
    }

(* ---------- 9. choices ---------- *)

let choices () =
  let projects = Lazy.force projects_fr in
  let all_none = Is.choices ~current:None projects in
  Alcotest.(check int) "1 + 75 projects" 76 (List.length all_none);
  (match all_none with
  | head :: _ ->
      Alcotest.(check choice_t)
        "head is Automatique, selected"
        {Is.flora = None; selected = true}
        head
  | [] -> Alcotest.fail "empty");
  Alcotest.(check (list bool))
    "nothing else selected with ~current:None"
    (List.map (fun _ -> false) projects)
    (List.map (fun (c : Is.choice) -> c.selected) (List.tl all_none));
  Alcotest.(check (list string))
    "the rest in decoded order"
    (List.map (fun (p : Plantnet.project) -> p.title) projects)
    (List.map title (List.tl all_none));
  let current : Settings.flora option =
    Some {id = "k-middle-europe"; title = "x"}
  in
  let with_current = Is.choices ~current projects in
  (match List.filter (fun (c : Is.choice) -> c.selected) with_current with
  | [c] ->
      Alcotest.(check bool)
        "the selected entry is not Automatique" false
        (Is.equal_choice c {Is.flora = None; selected = true});
      let listed =
        List.find
          (fun (p : Plantnet.project) -> String.equal p.id "k-middle-europe")
          projects
      in
      Alcotest.(check choice_t)
        "the selected entry is the list's project, with the list's title"
        {
          Is.flora = Some {id = listed.id; title = listed.title};
          selected = true;
        }
        c
  | sel ->
      Alcotest.failf "expected exactly one selected, got %d" (List.length sel));
  Alcotest.(check (list string))
    "a selection moves nothing"
    ("Automatique" :: List.map (fun (p : Plantnet.project) -> p.title) projects)
    (List.map title with_current);
  let absent_current : Settings.flora option =
    Some {id = "nope"; title = "y"}
  in
  Alcotest.(check int)
    "current absent from the list: none selected" 0
    (List.length
       (List.filter
          (fun (c : Is.choice) -> c.selected)
          (Is.choices ~current:absent_current projects)));
  let with_all : Plantnet.project list =
    [{id = "all"; title = "Tout"}; {id = "k-a"; title = "A"}]
  in
  let dropped_all = Is.choices ~current:None with_all in
  Alcotest.(check int) "id = \"all\" is dropped" 2 (List.length dropped_all);
  Alcotest.(check bool)
    "no entry titled \"Tout\"" false
    (List.exists
       (fun (c : Is.choice) -> String.equal (title c) "Tout")
       dropped_all);
  let dup : Plantnet.project list =
    [{id = "k-a"; title = "First"}; {id = "k-a"; title = "Second"}]
  in
  match Is.choices ~current:None dup with
  | [_automatique; only] ->
      Alcotest.(check string)
        "duplicated id keeps the first" "First" (title only)
  | l ->
      Alcotest.failf "expected 2 entries (Automatique + one), got %d"
        (List.length l)

(* ---------- 10. filter ---------- *)

let filter () =
  let all = Is.choices ~current:None (Lazy.force projects_fr) in
  List.iter
    (fun query ->
      Alcotest.(check (list choice_t))
        (Printf.sprintf "blank query %S: unchanged" query)
        all (Is.filter ~query all))
    [""; "   "];
  let europe = Is.filter ~query:"europe" all in
  (match europe with
  | head :: _ ->
      Alcotest.(check string) "Automatique first" "Automatique" (title head)
  | [] -> Alcotest.fail "empty");
  Alcotest.(check (list string))
    "\"europe\": Automatique, then the six titles containing Europe, in the \
     recorded order"
    [
      "Automatique";
      "Europe du Nord";
      "Europe Centrale";
      "Europe du Sud-Ouest";
      "Europe du Sud-Est";
      "Europe de l'Est";
      "Arbres d'Europe";
    ]
    (List.map title europe);
  Alcotest.(check (list choice_t))
    "\"EUROPE\" gives the same result as \"europe\"" europe
    (Is.filter ~query:"EUROPE" all);
  Alcotest.(check (list choice_t))
    "an accent-folded query (\"éurope\") gives the same result as \"europe\""
    europe
    (Is.filter ~query:"éurope" all);
  List.iter
    (fun query ->
      Alcotest.(check (list string))
        (Printf.sprintf "%S: Automatique alone" query)
        ["Automatique"]
        (List.map title (Is.filter ~query all)))
    ["zzz"; "-"; "«"];
  Alcotest.(check (list choice_t))
    "a padded query gives the same result as the trimmed one" europe
    (Is.filter ~query:"  europe " all)

(* ---------- 11. flora_list_error ---------- *)

let flora_list_error () =
  List.iter
    (fun (e, expected) ->
      Alcotest.(check string)
        (Plantnet.error_to_string e)
        expected (Is.flora_list_error e))
    [
      ( Plantnet.Key_refused,
        "Pl@ntNet a refusé la clé : vérifiez-la ci-dessous." );
      ( Plantnet.Quota_used_up,
        "Quota Pl@ntNet du jour atteint : réessayez demain." );
      ( Plantnet.Unreachable Plantnet.Timeout,
        "Pl@ntNet injoignable : réessayez plus tard." );
      ( Plantnet.Unreachable Plantnet.Network,
        "Pl@ntNet injoignable : réessayez plus tard." );
      ( Plantnet.Unreachable (Plantnet.Server 503),
        "Pl@ntNet injoignable : réessayez plus tard." );
      (Plantnet.No_key, "Ajoutez votre clé API Pl@ntNet pour choisir la flore.");
    ];
  List.iter
    (fun e ->
      Alcotest.(check string)
        (Printf.sprintf "%s -> the generic text" (Plantnet.error_to_string e))
        Is.flora_list_generic (Is.flora_list_error e))
    [
      Plantnet.Key_not_exposed;
      Plantnet.Refused_request 400;
      Plantnet.Refused_request 413;
      Plantnet.Malformed "x";
      Plantnet.No_plant;
      Plantnet.No_photo;
    ];
  let every : Plantnet.error list =
    [
      Plantnet.No_key;
      Plantnet.No_photo;
      Plantnet.No_plant;
      Plantnet.Key_refused;
      Plantnet.Key_not_exposed;
      Plantnet.Quota_used_up;
      Plantnet.Refused_request 400;
      Plantnet.Refused_request 413;
      Plantnet.Unreachable Plantnet.Timeout;
      Plantnet.Unreachable Plantnet.Network;
      Plantnet.Unreachable (Plantnet.Server 503);
      Plantnet.Malformed "x";
    ]
  and forbidden = ["cors"; "origin"; "origine"; "localhost"; "expose"] in
  List.iter
    (fun e ->
      let text = String.lowercase_ascii (Is.flora_list_error e) in
      List.iter
        (fun bad ->
          Alcotest.(check bool)
            (Printf.sprintf "%s: no %S" (Plantnet.error_to_string e) bad)
            false
            (Text.contains ~sub:bad text))
        forbidden)
    every;
  List.iter
    (fun text ->
      let lower = String.lowercase_ascii text in
      List.iter
        (fun bad ->
          Alcotest.(check bool)
            (Printf.sprintf "no %S" bad)
            false
            (Text.contains ~sub:bad lower))
        forbidden)
    [Is.flora_list_generic; Is.flora_list_offline]

(* ---------- 12. constant texts ---------- *)

let constants () =
  Alcotest.(check string) "automatic_title" "Automatique" Is.automatic_title;
  Alcotest.(check string)
    "no_key_line"
    "Ajoutez votre clé API Pl@ntNet dans Réglages pour identifier."
    Is.no_key_line;
  Alcotest.(check string) "section_title" "Identification" Is.section_title;
  Alcotest.(check string)
    "on_photo_label" "Identifier dès la photo" Is.on_photo_label;
  Alcotest.(check string)
    "on_photo_detail"
    "Pl@ntNet propose les espèces avant de nommer. En ligne seulement."
    Is.on_photo_detail;
  Alcotest.(check string) "flora_title" "Flore Pl@ntNet" Is.flora_title;
  Alcotest.(check string) "key_title" "Clé API Pl@ntNet" Is.key_title;
  Alcotest.(check string) "key_edit" "Modifier" Is.key_edit;
  Alcotest.(check string)
    "key_placeholder" "Collez votre clé API" Is.key_placeholder;
  Alcotest.(check string) "key_save" "Enregistrer" Is.key_save;
  Alcotest.(check string) "key_cancel" "Annuler" Is.key_cancel;
  Alcotest.(check string)
    "key_not_saved" "Clé non enregistrée sur le téléphone." Is.key_not_saved;
  Alcotest.(check string)
    "key_help_before" "Clé gratuite et personnelle, à créer sur "
    Is.key_help_before;
  Alcotest.(check string) "key_help_link" "my.plantnet.org" Is.key_help_link;
  Alcotest.(check string)
    "key_help_url" "https://my.plantnet.org/" Is.key_help_url;
  Alcotest.(check string)
    "key_help_after"
    ". Dans votre compte Pl@ntNet, cochez « expose my API key » et ajoutez \
     https://localhost aux domaines autorisés."
    Is.key_help_after;
  Alcotest.(check string)
    "footnote"
    "Pl@ntNet ne conserve pas les photos envoyées. Jusqu'à 500 identifications \
     par jour."
    Is.footnote;
  Alcotest.(check string) "search_placeholder" "Flore" Is.search_placeholder;
  Alcotest.(check string) "loading" "Chargement…" Is.loading;
  Alcotest.(check string) "retry" "Réessayer" Is.retry;
  Alcotest.(check string) "selected_meta" "Choisie" Is.selected_meta;
  Alcotest.(check string)
    "flora_list_generic" "La liste des flores n'a pas pu être chargée."
    Is.flora_list_generic;
  Alcotest.(check string)
    "flora_list_offline" "Hors-ligne : la liste des flores demande le réseau."
    Is.flora_list_offline;
  Alcotest.(check string)
    "key_help_before ^ key_help_link ^ key_help_after is the key's help line"
    "Clé gratuite et personnelle, à créer sur my.plantnet.org. Dans votre \
     compte Pl@ntNet, cochez « expose my API key » et ajoutez \
     https://localhost aux domaines autorisés."
    (Is.key_help_before ^ Is.key_help_link ^ Is.key_help_after)

(* ---------- 13. pinned: the recorded CORS 403 ---------- *)

let pinned_cors_403 () =
  let body = Fixture.read "plantnet_projects_origin_refused_403.json" in
  let e = Plantnet.error_of_answer ~route:Plantnet.Projects ~status:403 ~body in
  Alcotest.(check error_t) "Key_not_exposed" Plantnet.Key_not_exposed e;
  Alcotest.(check string)
    "flora_list_error of it is the generic text (no CORS wording reaches the \
     screen)"
    Is.flora_list_generic (Is.flora_list_error e)

(* ---------- suite ---------- *)

let identify_settings =
  [
    Alcotest.test_case "preferences_key = \"plantnet.api_key\"" `Quick
      preferences_key;
    Alcotest.test_case "Key.of_input trims, blanks are None, inner space kept"
      `Quick key_of_input;
    Alcotest.test_case "Key.masked: the four cases, never the key itself" `Quick
      key_masked;
    Alcotest.test_case "key_detail: Loading/Absent/Present" `Quick key_detail;
    Alcotest.test_case
      "key_of_stored: None and blank are Absent, a key is Present trimmed"
      `Quick key_of_stored;
    Alcotest.test_case
      "settings_of_stored: on_photo unset is true, the flora as stored" `Quick
      settings_of_stored;
    Alcotest.test_case
      "gate: the six Loading/Absent/Present × online/offline cases" `Quick gate;
    Alcotest.test_case "opens_on_photo: true only for ~on_photo:true (Ready _)"
      `Quick opens_on_photo;
    Alcotest.test_case "flora_id and flora_detail: None is \"Automatique\"/all"
      `Quick flora_id_and_detail;
    Alcotest.test_case
      "flora_row: Loading/Absent/Present × online/offline, no-key note takes \
       precedence over offline"
      `Quick flora_row;
    Alcotest.test_case
      "choices: Automatique first and selected by default, decoded order, \
       selection by id, \"all\" dropped, duplicated id keeps the first"
      `Quick choices;
    Alcotest.test_case
      "filter: blank unchanged, \"europe\" keeps Automatique and matching \
       titles, case and accents folded"
      `Quick filter;
    Alcotest.test_case
      "flora_list_error: each constructor's text, the generic bucket, no \
       \"cors\"/\"origin\"/\"localhost\"/\"expose\" wording ever"
      `Quick flora_list_error;
    Alcotest.test_case "the constant texts of §2, and the help line verbatim"
      `Quick constants;
    Alcotest.test_case
      "pinned: the recorded 403 is Key_not_exposed, shown as the generic text"
      `Quick pinned_cors_403;
  ]
