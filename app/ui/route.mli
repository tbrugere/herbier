(** Where the app is: the URL fragment, parsed. Screens navigate with {!go} and
    {!back}; {!Router} follows the fragment. *)

(** Full-screen modals over the tabs (no tab bar): 4l and 5d. *)
type modal = Tags | Manage_tags

type t = Tab of Widgets.Tab_bar.tab | Modal of modal | Dev of string

val of_fragment : string -> t
(** [""], ["collection"] → [Tab Collection]; ["carte"], ["journal"],
    ["reglages"]; ["tags"] → [Modal Tags]; ["tags/gerer"] → [Modal Manage_tags];
    ["dev/<name>"] → [Dev name]. Anything else is [Tab Collection]. *)

val to_fragment : t -> string
(** Inverse of {!of_fragment} on its canonical forms ([Tab Collection] is
    ["collection"]). *)

val current : unit -> t
(** The route of the current fragment. *)

val go : t -> unit
(** Sets the fragment, which pushes a history entry; the router follows on
    [hashchange]. *)

val replace : t -> unit
(** Like {!go} but replaces the current history entry. *)

val canonicalize : t -> unit
(** Rewrites the URL to [t]'s canonical fragment when it differs, without a
    history entry or [hashchange]. *)

val back : unit -> unit
(** [history.back()]: a modal's ← and its Android back button do the same. *)
