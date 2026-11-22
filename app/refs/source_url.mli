(** The canonical page URL of a taxon at each source, from the id
    [Herbier_domain.Link.classify] reads back out of it: 4f's derived links
    ({!Projection}) and 5a's pasted ones (app/ui_model/ref_paste.ml) are built
    here. Pure; the ids are not checked. [encode] is {!Herbier_net.Url.encode}.
*)

val taxref : int -> string
(** ["https://inpn.mnhn.fr/espece/cd_nom/<cd>"]. *)

val tela : int -> string
(** ["https://www.tela-botanica.org/bdtfx-nn-<nn>"]. *)

val inat : int -> string
(** ["https://www.inaturalist.org/taxa/<id>"]. *)

val powo : string -> string
(** ["https://powo.science.kew.org/taxon/" ^ id] when [id] is an IPNI lsid
    (["urn:lsid:ipni.org:names:"] then digits and ['-']), written as POWO and
    Wikidata write it; any other id is appended as [encode id]. *)

val is_ipni_lsid : string -> bool
(** ["urn:lsid:ipni.org:names:"] followed by at least one digit or ['-'], and
    nothing else. *)

val plantnet : string -> string
(** ["https://identify.plantnet.org/k-world-flora/species/" ^ encode name ^
     "/data"]. *)

val wikipedia : lang:string -> string -> string
(** [wikipedia ~lang title]:
    ["https://" ^ lang ^ ".wikipedia.org/wiki/" ^ encode title], the spaces of
    [title] written ['_'] before encoding. *)

val eppo : string -> string
(** ["https://gd.eppo.int/taxon/<code>"]. *)

val plantuse_wiki : string
(** ["https://plantuse.plantnet.org/fr"]: Pl@ntUse's French wiki, its pages and
    its [api.php]. *)

val plantuse : string -> string
(** [plantuse title]: ["https://plantuse.plantnet.org/fr/" ^ encode title], the
    spaces of [title] written ['_'] before encoding; the French Pl@ntUse wiki's
    page, which [Link.classify] reads back as [Plantuse title]. *)
