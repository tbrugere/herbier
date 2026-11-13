(** A parked outbox entry as 4m lists it (ui/screens/settings/pending.ml). *)

type t = {title : string; detail : string}

val describe :
  table_name:string -> payload:Yojson.Safe.t -> last_error:string -> t
(** [title]: plants → « Plante « <display_name> » », tags → « Étiquette « <name>
    » », observations → « Observation », photos → « Photo », plant_tags → «
    Étiquette d’une plante », plant_refs → « Lien de référence », reference → «
    Référence <source> » (the table matched on {!Herbier_sync_core.Synced.name},
    the name field read under its [Tables] column name); a missing or non-string
    name field, or a payload that is no object → the bare label (« Plante »); an
    unknown table → the table name. [detail], through
    {!Herbier_sync_core.Cycle.Last_error.of_string}: [Rejected n] → « Refusée
    par le serveur (<n>) »; [Invalid _] → « Entrée illisible »; [Other] → the
    text as is. Never raises. *)
