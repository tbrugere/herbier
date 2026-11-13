(** How search text is split and folded: the rules of the store's full-text
    search ([Herbier_store.Search.match_expression] builds its FTS5 query from
    them) and of {!matches}, which runs the same comparison in memory (4b's
    place names, 4m's packs). Pure. *)

val terms : string -> string list
(** The terms of a text:
    + the UTF-8 separators U+0080–U+00BF (but ª µ º: NBSP, « », ·, ¿) and
      U+2000–U+207F (’ “ ” … – —, the narrow NBSP, superscripts) count as
      spaces;
    + terms are the maximal runs of bytes that are ASCII letters, ASCII digits
      or ≥ 0x80 (UTF-8 sequences kept whole); every other byte separates terms
      (spaces, punctuation, ['-'], ['\''], ['"'], ['*'], [':'], parentheses);
    + a term with no ASCII letter or digit and no lead byte of U+00C0–U+07FF,
      U+0800–U+1FFF or U+3000–U+FFFF (only emoji or symbols) is dropped, since
      it would match nothing.

    In text order, not folded. Never raises. *)

val fold : string -> string
(** ASCII is lowercased, and the Latin-1 letters with a diacritic (à á â ã ä å ç
    è é ê ë ì í î ï ñ ò ó ô õ ö ù ú û ü ý ÿ, their capitals, and Ÿ) become their
    base ASCII letter; other bytes are kept (œ, æ, ø and ß stay). *)

val strip_ending : string -> string
(** At most one ending stripped from a folded term, and only if at least 4 bytes
    remain: the first of ["es"; "is"; "us"; "um"; "ae"] that ends it with 4
    bytes left, otherwise the first of ["e"; "s"; "a"; "i"] that does
    ("digitale" → "digital", "digitalis" → "digital", "pourpre" → "pourpr",
    "roses" → "rose"; "rosa" and "lis" stay as they are). *)

val matches : query:string -> string -> bool
(** [matches ~query text]: [true] when every term of [query] ({!terms}, {!fold},
    {!strip_ending}) is a prefix of some term of [text] ({!terms} and {!fold},
    no ending stripped). [false] when [query] has no term. Never raises. *)
