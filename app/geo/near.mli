(** The stored [place_derived] phrase of a place name, « Près de … ». Pure. *)

val phrase : string -> string option
(** The stored [place_derived] phrase for a place name (handoff 4c « Près de
    Colmar »), French contraction applied to the trimmed name:
    - ["Le X"] → ["Près du X"], ["Les X"] → ["Près des X"], ["La X"] →
      ["Près de la X"], ["L'X"] or ["L’X"] → ["Près de l’X"]: the article
      matched case-insensitively (ASCII) and followed by a space (the apostrophe
      forms by nothing), replaced by the contracted form;
    - else a name starting with a vowel (ASCII [AEIOUY], either case, or one of
      [À Â Ä É È Ê Ë Î Ï Ô Ö Ù Û Ü Œ Æ] and their lower case) →
      ["Près d’" ^ name] (no elision before h);
    - else ["Près de " ^ name], also for a name made only of an article (["L'"]
      → ["Près de L'"]).

    [None] for a blank name. The apostrophe written is always [’] (U+2019).
    Never raises. *)
