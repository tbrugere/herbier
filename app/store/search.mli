(** Offline full-text search over plants (architecture §3). An FTS5 table
    [plant_search] ([tokenize = 'unicode61 remove_diacritics 2'], created by
    migration 2 and kept in sync by triggers) holds one document per live plant,
    keyed by its id: its names (display name, scientific name, aliases), the
    names of its live tags, and the [place_label] and [place_derived] of its
    live observations. *)

val match_expression : string -> string option
(** The FTS5 [MATCH] text for what the user typed: each term of
    {!Herbier_domain.Fold.terms}, folded ({!Herbier_domain.Fold.fold}) and with
    one ending stripped ({!Herbier_domain.Fold.strip_ending}), is written
    ["\"" ^ term ^ "\"*"], a quoted prefix query, so FTS5 keywords such as AND,
    OR, NOT and NEAR are plain text. Terms are joined by one space: every term
    must match, in any column. {!Herbier_domain.Fold.matches} runs the same
    comparison in memory.

    [None] when there is no term (empty, blank, punctuation or symbols only).
    Never raises. *)

val plants : string -> Herbier_domain.Plant.t Stmt.query option
(** [None] when [match_expression text] is [None]; the caller then shows the
    unfiltered list. Otherwise the query returns each live plant whose document
    matches, once, in {!Plants.order_by} (not by rank), decoded with
    {!Plants.row}. *)

val plants_by_name : string -> Herbier_domain.Plant.t Stmt.query option
(** {!plants} on the names and tags only: a plant is not found through the
    places it was seen at. The map (4b) matches a place on its own name with
    {!Herbier_domain.Fold.matches}; through the places column, « lisi » would
    also admit the observations made elsewhere of every plant ever seen at «
    Lisière ». *)

val plants_or_all : string -> Herbier_domain.Plant.t Stmt.query
(** {!plants}, or {!Plants.list} when the text has no term. *)
