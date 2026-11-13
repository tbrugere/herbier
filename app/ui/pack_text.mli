(** 4m « IGN hors-ligne » texts of a downloaded commune pack. Pure. *)

val size : int -> string
(** French, SI units, decimal comma: below 1000 → ["<n> o"]; else
    [round(n/1000)] when below 1000 → ["<round(n/1000)> ko"]; else one decimal,
    ["1,0 Mo"] (999_500 included), ["1,2 Mo"], ["12,0 Mo"]. A negative size →
    ["0 o"]. *)

val title : code:string -> name:string -> string
(** ["90 · Territoire de Belfort"] *)

val detail : size_bytes:int -> communes:int -> string
(** ["<size> · <n> commune(s)"] through [Fr_text.plural]:
    ["89 ko · 101 communes"], ["1 ko · 1 commune"]. *)

val unreadable : string
(** ["Fichier illisible : supprimez puis retéléchargez."] *)

val no_pack : string
(** ["Aucun département téléchargé : « IGN hors-ligne » ne nomme rien."] *)

val attribution : string
(** ["Limites communales : IGN, Admin Express COG carto (Licence Ouverte 2.0)"]
*)
