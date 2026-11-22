module Url = Herbier_net.Url

let taxref cd = "https://inpn.mnhn.fr/espece/cd_nom/" ^ string_of_int cd
let tela nn = "https://www.tela-botanica.org/bdtfx-nn-" ^ string_of_int nn
let inat id = "https://www.inaturalist.org/taxa/" ^ string_of_int id
let lsid_prefix = "urn:lsid:ipni.org:names:"

let is_ipni_lsid id =
  let p = String.length lsid_prefix in
  String.starts_with ~prefix:lsid_prefix id
  && String.length id > p
  && String.for_all
       (function '0' .. '9' | '-' -> true | _ -> false)
       (String.sub id p (String.length id - p))

let powo id =
  "https://powo.science.kew.org/taxon/"
  ^ match is_ipni_lsid id with true -> id | false -> Url.encode id

let plantnet name =
  "https://identify.plantnet.org/k-world-flora/species/"
  ^ Url.encode name
  ^ "/data"

let wikipedia ~lang title =
  "https://"
  ^ lang
  ^ ".wikipedia.org/wiki/"
  ^ Url.encode (String.map (function ' ' -> '_' | c -> c) title)

let eppo code = "https://gd.eppo.int/taxon/" ^ code
let plantuse_wiki = "https://plantuse.plantnet.org/fr"

let plantuse title =
  plantuse_wiki
  ^ "/"
  ^ Url.encode (String.map (function ' ' -> '_' | c -> c) title)
