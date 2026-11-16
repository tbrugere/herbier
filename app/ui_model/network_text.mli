(** The offline texts: the global strip and 4d's pill, 4g's unlinked line, 4i's
    search status (handoff « Hors-ligne »). Pure. *)

val banner : online:bool -> pending:int -> string option
(** [None] when [online]; else ["hors-ligne"] for [pending <= 0],
    ["hors-ligne · <pending> en attente"] otherwise. *)

val unlinked_offline : online:bool -> string
(** 4g, appended after « Aucune espèce de référence liée. »: [""] online,
    [" Hors-ligne : la recherche de noms reviendra avec le réseau."] offline
    (leading space included). *)

val search_status : online:bool -> Ref_search.status -> string
(** 4i's line under the search: [Blank] → [""]; [Found (_ :: _)] → [""] online,
    « Hors-ligne : « + » reviendra avec le réseau. » offline (the rows stay,
    their « + » waits); [Pending] → « Recherche… »; [Found []] → « Aucune espèce
    trouvée dans GBIF. »; [Offline] → « Recherche indisponible hors-ligne. »;
    [Failed _] → « La recherche n'a pas abouti. ». *)
