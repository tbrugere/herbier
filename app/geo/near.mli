(** The stored [place_derived] phrases of a place name, « Près de … » and « À …
    ». Pure. *)

val phrase : string -> string option
(** The stored [place_derived] phrase for a place name near the point (handoff
    4c « Près de Colmar »), French contraction applied to the trimmed name:
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

val inside : string -> string option
(** The phrase for a commune known to contain the point (« À Figeac »), by the
    rule of {!phrase} with « à »: ["Le X"] → ["Au X"], ["Les X"] → ["Aux X"],
    ["La X"] → ["À la X"], ["L'X"] or ["L’X"] → ["À l’X"], else ["À " ^ name] (a
    vowel elides nothing; an article alone → ["À L'"]). [None] for a blank name.
    Never raises. *)
