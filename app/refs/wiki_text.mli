(** MediaWiki text, read without a parser: the heading-delimited sections of a
    wikitext or of a TextExtracts plain text ([exsectionformat=wiki]), inline
    wikitext turned into plain text, and the named parameters of a template.
    Shared by the Pl@ntUse decoder ({!Sources.Plantuse}) and the Wikipedia uses
    rule ({!Sources.Wikipedia.uses_line}). Pure; nothing here raises.

    "Code points" are UTF-8 characters (bytes that are not continuation bytes).
*)

type section = {level : int; title : string; body : string}
(** [level] 2..6, the number of ['='] around the title; [title] trimmed, as
    written; [body] the lines after the heading up to the next heading line of
    any level (not included), joined with ['\n'], untouched (not trimmed). *)

val equal_section : section -> section -> bool
val pp_section : Format.formatter -> section -> unit

val sections : string -> string * section list
(** The lead (the text before the first heading) and the sections in document
    order. A heading line is a line that, trimmed, starts with [n] ['='] and
    ends with [n] ['='] (2 <= n <= 6, the same [n] both sides, at least one
    character that is not ['='] in between): ["== Usages =="] is level 2, title
    ["Usages"]; ["=== Medicinal use ==="] is level 3; ["= T ="] and ["== T ="]
    are not headings. Lines are split on ['\n'], a ['\r'] before it dropped. No
    heading → [(whole text, [])]. *)

val strip : string -> string
(** Inline wikitext → plain text, then whitespace runs collapsed to one space
    and trimmed. In this order:
    - [<ref …>…</ref>] and [<ref …/>] removed; HTML comments removed;
    - templates [{{…}}] removed, nested ones included (an unclosed [{{] keeps
      the rest of the text as is);
    - [[[File:…]]], [[[Fichier:…]]], [[[Image:…]]], [[[Category:…]]],
      [[[Catégorie:…]]] removed (prefix case-insensitive);
    - [[[target|label]]] → label, [[[target]]] → target;
    - [[http… label]] → label, [[http…]] → removed;
    - ['''] and [''] removed; any other tag [<…>] removed, its content kept;
    - entities [&nbsp;] → space, [&amp;] → ['&'], [&lt;] → ['<'], [&gt;] →
      ['>'], [&quot;] → ['"'], [&#39;] → ['\''].

    [strip "''Urtica dioica'' est [[ortie|une ortie]]<ref>x</ref>."] is
    ["Urtica dioica est une ortie."]. *)

val templates : name:string -> string -> (string * string) list list
(** Every occurrence of the template [{{name …}}] (the name compared after
    trimming, the case of its first letter ignored as MediaWiki does), in
    document order, as its named parameters: the text between the outer braces
    split on the ['|'] that are not inside a nested [{{…}}] or [[[…]]]; the
    first piece is the name; each later piece containing ['='] gives (trimmed
    text before the first ['='], trimmed text after it); pieces without ['=']
    are dropped. An unclosed template is ignored. *)

val bullets : string -> string list
(** The lines that, trimmed, start with ['*'] (one or more), without the stars,
    {!strip}ped, blank ones dropped, in order. *)

val first_sentences : n:int -> string -> string
(** The first [n] sentences of the trimmed text (a sentence ends after ['.'],
    ['!'] or ['?'] followed by a space or the end, except a ['.'] after a lone
    capital letter as in ["L. "]), as written, trimmed; the whole text when it
    has fewer. [n <= 0] → [""]. *)

val initial : string -> int -> bool
(** [initial s i]: the ['.'] at [i] follows a lone capital letter (at the start,
    or after a space or ['\n']), an author's initial as in
    ["Digitalis purpurea L. est"], not the end of a sentence. *)

val pieces : string -> string list
(** [s] split on the ['|'] that are not inside a [{{…}}] or a [[[…]]]:
    ["a|[[b|c]]||d"] → [["a"; "[[b|c]]"; ""; "d"]]. *)

val find : string -> string -> int -> int option
(** [find s sub i]: the first index [>= i] where [sub] starts in [s]. *)

val code_points : string -> int
(** The UTF-8 characters of a string. *)
