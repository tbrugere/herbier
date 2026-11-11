module Link = Herbier_domain.Link

let link =
  Alcotest.testable
    (fun ppf l -> Format.pp_print_string ppf (Link.to_string l))
    Link.equal

let check name input expected () =
  Alcotest.check link name expected (Link.classify input)

let case name input expected = (name, `Quick, check name input expected)
let text_case name input = case name input (Link.Text (String.trim input))

let gbif_tests =
  [
    case "gbif species url" "https://www.gbif.org/species/5414463"
      (Link.Gbif 5414463);
    case "gbif species url with language prefix"
      "https://www.gbif.org/fr/species/5414463" (Link.Gbif 5414463);
    case "gbif species url with trailing metrics segment"
      "https://www.gbif.org/species/5414463/metrics" (Link.Gbif 5414463);
    case "gbif species url with language and verbatim segment"
      "https://www.gbif.org/en/species/5414463/verbatim" (Link.Gbif 5414463);
    case "gbif species url with trailing slash"
      "https://www.gbif.org/species/5414463/" (Link.Gbif 5414463);
    text_case "gbif key that is not a number is text"
      "https://www.gbif.org/species/abc";
    text_case "gbif key zero is text" "https://www.gbif.org/species/0";
    text_case "gbif negative key is text" "https://www.gbif.org/species/-5";
    text_case "gbif key overflowing int is text"
      "https://www.gbif.org/species/99999999999999999999999";
    text_case "gbif url without species segment is text"
      "https://www.gbif.org/occurrence/123";
    case "gbif mobile host" "https://m.gbif.org/species/5414463"
      (Link.Gbif 5414463);
    text_case "gbif mobile look-alike host is text"
      "https://m.gbif.org.example.com/species/5414463";
    text_case "gbif mobile prefix look-alike host is text"
      "https://mm.gbif.org/species/5414463";
    case "gbif mobile host behind www" "https://www.m.gbif.org/species/5414463"
      (Link.Gbif 5414463);
  ]

let plantnet_tests =
  [
    case
      "plantnet species with lang prefix and project slug, percent-encoded name"
      "https://identify.plantnet.org/fr/k-southwestern-europe/species/Digitalis%20purpurea%20L./data"
      (Link.Plantnet "Digitalis purpurea L.");
    case "plantnet species without lang prefix"
      "https://identify.plantnet.org/k-world-flora/species/Digitalis%20purpurea%20L."
      (Link.Plantnet "Digitalis purpurea L.");
    case "plantnet species name with plus stays a plus"
      "https://identify.plantnet.org/k-world-flora/species/Mentha+x%20piperita"
      (Link.Plantnet "Mentha+x piperita");
    case "plantnet species inside surrounding text"
      "Digitalis purpurea L. \
       https://identify.plantnet.org/fr/k-southwestern-europe/species/Digitalis%20purpurea%20L./data"
      (Link.Plantnet "Digitalis purpurea L.");
    case "plantnet observation"
      "https://identify.plantnet.org/k-world-flora/observations/1012345678"
      (Link.Plantnet_observation "1012345678");
    case "plantnet observation with lang prefix"
      "https://identify.plantnet.org/fr/k-world-flora/observations/1012345678"
      (Link.Plantnet_observation "1012345678");
    text_case "plantnet url matching neither species nor observations is text"
      "https://identify.plantnet.org/fr/k-world-flora";
  ]

let plantuse_tests =
  [
    case "plantuse page, underscores become spaces"
      "https://plantuse.plantnet.org/fr/Digitalis_purpurea"
      (Link.Plantuse "Digitalis purpurea");
    case "plantuse on the uses.plantnet.org host"
      "https://uses.plantnet.org/en/Digitalis_purpurea"
      (Link.Plantuse "Digitalis purpurea");
    case "plantuse on the old uses.plantnet-project.org host"
      "https://uses.plantnet-project.org/fr/Digitalis_purpurea"
      (Link.Plantuse "Digitalis purpurea");
    text_case "plantuse old host look-alike is text"
      "https://uses.plantnet-project.org.example.com/fr/Digitalis_purpurea";
    text_case "plantuse old host prefix look-alike is text"
      "https://xuses.plantnet-project.org/fr/Digitalis_purpurea";
    case "plantuse page with percent-encoded name"
      "https://plantuse.plantnet.org/fr/Digitalis%20purpurea"
      (Link.Plantuse "Digitalis purpurea");
    text_case "plantuse blank page name is text"
      "https://plantuse.plantnet.org/fr/_";
    text_case "plantuse percent-encoded blank page name is text"
      "https://plantuse.plantnet.org/fr/%20";
    text_case "plantuse index.php is text"
      "https://plantuse.plantnet.org/w/index.php?title=Digitalis_purpurea&action=history";
    text_case "plantuse category page is text"
      "https://plantuse.plantnet.org/fr/Cat%C3%A9gorie:Plantes_m%C3%A9dicinales";
    text_case "plantuse special page is text"
      "https://plantuse.plantnet.org/fr/Sp%C3%A9cial:Recherche";
  ]

let wikipedia_tests =
  [
    case "wikipedia fr with percent-encoded accents and underscores"
      "https://fr.wikipedia.org/wiki/Digitalis_pourpr%C3%A9e"
      (Link.Wikipedia {lang = "fr"; title = "Digitalis pourprée"});
    case "wikipedia en" "https://en.wikipedia.org/wiki/Digitalis_purpurea"
      (Link.Wikipedia {lang = "en"; title = "Digitalis purpurea"});
    case "wikipedia mobile host"
      "https://fr.m.wikipedia.org/wiki/Foug%C3%A8re_aigle"
      (Link.Wikipedia {lang = "fr"; title = "Fougère aigle"});
    case "wikipedia fragment is ignored"
      "https://en.wikipedia.org/wiki/Digitalis_purpurea#Description"
      (Link.Wikipedia {lang = "en"; title = "Digitalis purpurea"});
    text_case "wikipedia url without /wiki/ is text"
      "https://en.wikipedia.org/w/index.php?title=Digitalis";
    text_case "wikipedia url without a title is text"
      "https://en.wikipedia.org/wiki/";
    text_case "wikipedia blank title is text" "https://fr.wikipedia.org/wiki/_";
    case "wikipedia title with a literal slash"
      "https://en.wikipedia.org/wiki/AC/DC"
      (Link.Wikipedia {lang = "en"; title = "AC/DC"});
    case "wikipedia title with an encoded slash"
      "https://en.wikipedia.org/wiki/AC%2FDC"
      (Link.Wikipedia {lang = "en"; title = "AC/DC"});
    case "malformed percent escape kept as written"
      "https://en.wikipedia.org/wiki/Digi%zztalis"
      (Link.Wikipedia {lang = "en"; title = "Digi%zztalis"});
    case "truncated percent escape kept as written"
      "https://en.wikipedia.org/wiki/Digitalis%4"
      (Link.Wikipedia {lang = "en"; title = "Digitalis%4"});
    case "percent escape ending the segment decoded"
      "https://en.wikipedia.org/wiki/Digitalis%41"
      (Link.Wikipedia {lang = "en"; title = "DigitalisA"});
    case "segment decoding to invalid utf-8 kept as written"
      "https://fr.wikipedia.org/wiki/Foug%E8re"
      (Link.Wikipedia {lang = "fr"; title = "Foug%E8re"});
  ]

let inpn_tests =
  [
    case "inpn espece/cd_nom form" "https://inpn.mnhn.fr/espece/cd_nom/123456"
      (Link.Inpn 123456);
    case "inpn explorer/especes form"
      "https://inpn.mnhn.fr/explorer/especes/123456" (Link.Inpn 123456);
    case "inpn espece/cd_nom with trailing segment"
      "https://inpn.mnhn.fr/espece/cd_nom/123456/tab/carte" (Link.Inpn 123456);
    text_case "inpn non-numeric cd_nom is text"
      "https://inpn.mnhn.fr/espece/cd_nom/abc";
  ]

let tela_tests =
  [
    case "tela bdtfx nn" "https://www.tela-botanica.org/bdtfx-nn-12345"
      (Link.Tela 12345);
    case "tela bdtfx nn with synthese suffix"
      "https://www.tela-botanica.org/bdtfx-nn-12345-synthese" (Link.Tela 12345);
    text_case "tela page that is not bdtfx-nn is text"
      "https://www.tela-botanica.org/actualites";
    text_case "tela non-numeric nn is text"
      "https://www.tela-botanica.org/bdtfx-nn-abc";
    text_case "tela zero nn is text" "https://www.tela-botanica.org/bdtfx-nn-0";
  ]

let powo_tests =
  [
    case "powo taxon urn"
      "https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:30000174-2"
      (Link.Powo "urn:lsid:ipni.org:names:30000174-2");
    case "powo taxon urn with percent-encoded colons"
      "https://powo.science.kew.org/taxon/urn%3Alsid%3Aipni.org%3Anames%3A30000174-2"
      (Link.Powo "urn:lsid:ipni.org:names:30000174-2");
    text_case "powo url without taxon is text"
      "https://powo.science.kew.org/results?q=digitalis";
    text_case "powo blank id is text" "https://powo.science.kew.org/taxon/%20";
    text_case "powo mobile host is text"
      "https://m.powo.science.kew.org/taxon/urn:lsid:ipni.org:names:30000174-2";
  ]

let inat_tests =
  [
    case "inat taxa id" "https://www.inaturalist.org/taxa/47604"
      (Link.Inat 47604);
    case "inat taxa id with name suffix"
      "https://www.inaturalist.org/taxa/47604-Digitalis-purpurea"
      (Link.Inat 47604);
    case "inat mobile host" "https://m.inaturalist.org/taxa/47604"
      (Link.Inat 47604);
    text_case "inat mobile look-alike host is text"
      "https://m.inaturalist.org.example.com/taxa/47604";
    text_case "inat mobile prefix look-alike host is text"
      "https://mm.inaturalist.org/taxa/47604";
    case "inat mobile host behind www"
      "https://www.m.inaturalist.org/taxa/47604" (Link.Inat 47604);
    text_case "inat taxa with zero id is text"
      "https://www.inaturalist.org/taxa/0";
    text_case "inat taxa slug without id is text"
      "https://www.inaturalist.org/taxa/Digitalis-purpurea";
  ]

let parsing_tests =
  [
    case "http scheme accepted" "http://www.gbif.org/species/5414463"
      (Link.Gbif 5414463);
    case "uppercase scheme and host" "HTTPS://WWW.GBIF.ORG/species/5414463"
      (Link.Gbif 5414463);
    case "port ignored" "https://www.gbif.org:443/species/5414463"
      (Link.Gbif 5414463);
    case "query ignored" "https://www.gbif.org/species/5414463?q=abc"
      (Link.Gbif 5414463);
    case "fragment ignored" "https://www.gbif.org/species/5414463#top"
      (Link.Gbif 5414463);
    case "trailing dot on host dropped" "https://www.gbif.org./species/5414463"
      (Link.Gbif 5414463);
    case "userinfo dropped" "https://user:pw@www.gbif.org/species/5414463"
      (Link.Gbif 5414463);
    case "url inside surrounding text"
      "Regarde ça https://www.gbif.org/species/5414463 merci"
      (Link.Gbif 5414463);
    case "url alone surrounded by whitespace"
      "  \n https://www.gbif.org/species/5414463 \t" (Link.Gbif 5414463);
    case "trailing period stripped" "voir https://www.gbif.org/species/5414463."
      (Link.Gbif 5414463);
    case "trailing closing parenthesis stripped"
      "(https://www.gbif.org/species/5414463)" (Link.Gbif 5414463);
    case "trailing comma and exclamation stripped"
      "https://www.gbif.org/species/5414463,!" (Link.Gbif 5414463);
    case "trailing guillemet stripped" "«https://www.gbif.org/species/5414463»"
      (Link.Gbif 5414463);
    case "trailing quote stripped" "\"https://www.gbif.org/species/5414463\""
      (Link.Gbif 5414463);
    case "wikipedia disambiguation keeps its closing parenthesis"
      "https://fr.wikipedia.org/wiki/Ail_(plante)"
      (Link.Wikipedia {lang = "fr"; title = "Ail (plante)"});
    case "outer parenthesis around a disambiguated title stripped"
      "(https://fr.wikipedia.org/wiki/Ail_(plante))"
      (Link.Wikipedia {lang = "fr"; title = "Ail (plante)"});
    case "plantnet authorship dot kept after stripped punctuation"
      "(https://identify.plantnet.org/k-world-flora/species/Quercus%20robur%20L.)."
      (Link.Plantnet "Quercus robur L.");
    case "plantnet sentence-final dot after a name without authorship is kept"
      "voir \
       https://identify.plantnet.org/k-world-flora/species/Quercus%20robur."
      (Link.Plantnet "Quercus robur.");
    case "plantnet observation trailing dot stripped"
      "https://identify.plantnet.org/k-world-flora/observations/123."
      (Link.Plantnet_observation "123");
    case "gbif host without www" "https://gbif.org/species/5414463"
      (Link.Gbif 5414463);
    case "inaturalist host without www" "https://inaturalist.org/taxa/56061"
      (Link.Inat 56061);
    text_case "backslash before userinfo ends the host as in a browser"
      "https://evil.com\\@identify.plantnet.org/x/species/Foo";
    case "backslash in the path is a separator"
      "https://www.gbif.org\\species\\5414463" (Link.Gbif 5414463);
    text_case "percent-encoded host matches nothing"
      "https://evil%2ecom\\.wikipedia.org/wiki/Digitalis";
    text_case "wikipedia language must start with a letter"
      "https://2130706433.wikipedia.org/wiki/Digitalis";
    case "wikipedia language with a hyphen"
      "https://zh-min-nan.wikipedia.org/wiki/Digitalis"
      (Link.Wikipedia {lang = "zh-min-nan"; title = "Digitalis"});
    text_case "url with an empty host is text" "https:///species/5414463";
    text_case "www.wikipedia.org is not a language"
      "https://www.wikipedia.org/wiki/Digitalis";
    text_case "plantuse page list is text" "https://plantuse.plantnet.org/fr/";
    case "first url wins"
      "https://www.gbif.org/species/1 https://www.gbif.org/species/2"
      (Link.Gbif 1);
    case "a later url is read when the first matches nothing"
      "https://example.com/x https://www.gbif.org/species/1" (Link.Gbif 1);
    case "no-break spaces inside guillemets end the url"
      "\xc2\xab\xc2\xa0https://www.gbif.org/species/5414463\xc2\xa0\xc2\xbb"
      (Link.Gbif 5414463);
    case "narrow no-break space before an exclamation ends the url"
      "https://www.gbif.org/species/5414463\xe2\x80\xaf!" (Link.Gbif 5414463);
    case "curly double quotes stripped"
      "\xe2\x80\x9chttps://www.gbif.org/species/5414463\xe2\x80\x9d"
      (Link.Gbif 5414463);
    case "curly single quotes stripped"
      "\xe2\x80\x98https://www.gbif.org/species/5414463\xe2\x80\x99"
      (Link.Gbif 5414463);
    case "markdown link whose text is the url"
      "[https://www.gbif.org/species/5414463](https://www.gbif.org/species/5414463)"
      (Link.Gbif 5414463);
    case "trailing semicolon stripped" "https://www.gbif.org/species/1;"
      (Link.Gbif 1);
    case "trailing colon stripped" "https://www.gbif.org/species/1:"
      (Link.Gbif 1);
    case "trailing question mark stripped" "https://www.gbif.org/species/1?"
      (Link.Gbif 1);
    case "trailing angle bracket stripped" "<https://www.gbif.org/species/1>"
      (Link.Gbif 1);
    case "trailing apostrophe stripped" "'https://www.gbif.org/species/1'"
      (Link.Gbif 1);
    case "unbalanced closing square bracket stripped"
      "[https://www.gbif.org/species/1]" (Link.Gbif 1);
    case "balanced square brackets in the path kept"
      "https://fr.wikipedia.org/wiki/Ail_[plante]"
      (Link.Wikipedia {lang = "fr"; title = "Ail [plante]"});
    case "long trailing run of dots stripped"
      ("https://www.gbif.org/species/1" ^ String.make 10_000 '.')
      (Link.Gbif 1);
    case "long trailing run of closing parentheses stripped"
      ("https://www.gbif.org/species/1" ^ String.make 10_000 ')')
      (Link.Gbif 1);
  ]

let text_tests =
  [
    case "non-matching host is text of the whole input"
      "https://example.com/species/5414463"
      (Link.Text "https://example.com/species/5414463");
    case "non-matching host in text is text of the whole trimmed input"
      "  voir https://example.com/page  "
      (Link.Text "voir https://example.com/page");
    case "plain text" "Digitalis purpurea" (Link.Text "Digitalis purpurea");
    case "plain text is trimmed" "  digitale pourpre \n"
      (Link.Text "digitale pourpre");
    case "empty string" "" (Link.Text "");
    case "whitespace only" "  \t\n" (Link.Text "");
    case "ftp scheme is not a url" "ftp://www.gbif.org/species/5414463"
      (Link.Text "ftp://www.gbif.org/species/5414463");
    case "host without scheme is plain text" "www.gbif.org/species/5414463"
      (Link.Text "www.gbif.org/species/5414463");
  ]

let equal_tests =
  [
    ( "equal distinguishes constructors with the same payload text",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "Plantnet x <> Plantuse x" false
          (Link.equal (Link.Plantnet "x") (Link.Plantuse "x")) );
    ( "equal compares payloads",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "Gbif 1 <> Gbif 2" false
          (Link.equal (Link.Gbif 1) (Link.Gbif 2));
        Alcotest.(check bool)
          "Gbif 1 = Gbif 1" true
          (Link.equal (Link.Gbif 1) (Link.Gbif 1)) );
  ]

let tests =
  gbif_tests
  @ plantnet_tests
  @ plantuse_tests
  @ wikipedia_tests
  @ inpn_tests
  @ tela_tests
  @ powo_tests
  @ inat_tests
  @ parsing_tests
  @ text_tests
  @ equal_tests
