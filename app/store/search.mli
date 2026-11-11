(** Offline full-text search over plants (architecture §3). An FTS5 table
    [plant_search] ([tokenize = 'unicode61 remove_diacritics 2'], created by
    migration 2 and kept in sync by triggers) holds one document per live plant,
    keyed by its id: its names (display name, scientific name, aliases), the
    names of its live tags, and the [place_label] and [place_derived] of its
    live observations. *)

val match_expression : string -> string option
(** The FTS5 [MATCH] text for what the user typed:
    + the UTF-8 separators U+0080–U+00BF (but ª µ º: NBSP, « », ·, ¿) and
      U+2000–U+207F (’ “ ” … – —, the narrow NBSP, superscripts) count as
      spaces;
    + terms are the maximal runs of bytes that are ASCII letters, ASCII digits
      or ≥ 0x80 (UTF-8 sequences kept whole); every other byte separates terms
      (spaces, punctuation, ['-'], ['\''], ['"'], ['*'], [':'], parentheses); a
      term with no ASCII letter or digit and no lead byte of U+00C0–U+07FF,
      U+0800–U+1FFF or U+3000–U+FFFF (only emoji or symbols) is dropped, since
      it would match nothing;
    + each term is folded: ASCII is lowercased, and the Latin-1 letters with a
      diacritic (à á â ã ä å ç è é ê ë ì í î ï ñ ò ó ô õ ö ù ú û ü ý ÿ, their
      capitals, and Ÿ) become their base ASCII letter; other bytes are kept (œ,
      æ, ø and ß stay);
    + at most one ending is stripped from the folded term, and only if at least
      4 bytes remain: the first of ["es"; "is"; "us"; "um"; "ae"] that ends it
      with 4 bytes left, otherwise the first of ["e"; "s"; "a"; "i"] that does
      ("digitale" → "digital", "digitalis" → "digital", "pourpre" → "pourpr",
      "roses" → "rose"; "rosa" and "lis" stay as they are);
    + each term is written ["\"" ^ term ^ "\"*"], a quoted prefix query, so FTS5
      keywords such as AND, OR, NOT and NEAR are plain text. Terms are joined by
      one space: every term must match, in any column.

    [None] when there is no term (empty, blank, punctuation or symbols only).
    Never raises. *)

val plants : string -> Herbier_domain.Plant.t Stmt.query option
(** [None] when [match_expression text] is [None]; the caller then shows the
    unfiltered list. Otherwise the query returns each live plant whose document
    matches, once, in {!Plants.order_by} (not by rank), decoded with
    {!Plants.row}. *)

val plants_or_all : string -> Herbier_domain.Plant.t Stmt.query
(** {!plants}, or {!Plants.list} when the text has no term. *)
