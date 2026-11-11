(** Where the app is: the URL fragment, parsed. Screens navigate with {!go} and
    {!back}; {!Router} follows the fragment. *)

(** Full-screen modals over the tabs (no tab bar). *)
type modal =
  | Tags  (** 4l *)
  | Manage_tags  (** 5d *)
  | Plant of Herbier_domain.Ids.Plant_id.t  (** the fiche, 4f/4g *)
  | Edit_plant of Herbier_domain.Ids.Plant_id.t  (** 5a *)
  | New_plant  (** 5a, creating *)
  | Observation of Herbier_domain.Ids.Observation_id.t  (** 4h *)
  | Change_species of Herbier_domain.Ids.Observation_id.t  (** 5c *)
  | Identify of Herbier_domain.Ids.Observation_id.t  (** 4k *)

type t = Tab of Widgets.Tab_bar.tab | Modal of modal | Dev of string

val of_fragment : string -> t
(** [""], ["collection"] → [Tab Collection]; ["carte"], ["journal"],
    ["reglages"]; ["tags"] → [Modal Tags]; ["tags/gerer"] → [Modal Manage_tags];
    ["plante/<id>"] → [Modal (Plant id)]; ["plante/<id>/modifier"] →
    [Modal (Edit_plant id)]; ["plante/nouvelle"] → [Modal New_plant];
    ["observation/<id>"], ["observation/<id>/espece"], ["a-identifier/<id>"] →
    [Observation], [Change_species], [Identify]; ["dev/<name>"] → [Dev name].
    Anything else (an id that is not a UUID too) is [Tab Collection]. *)

val to_fragment : t -> string
(** Inverse of {!of_fragment} on its canonical forms ([Tab Collection] is
    ["collection"]). *)

val current : unit -> t
(** The route of the current fragment. *)

val go : t -> unit
(** Sets the fragment, which pushes a history entry; the router follows on
    [hashchange]. *)

val replace : t -> unit
(** Like {!go} but replaces the current history entry: after a delete or a
    creation, ← does not come back to the form, and a tab switch adds none. *)

val canonicalize : t -> unit
(** Rewrites the URL to [t]'s canonical fragment when it differs, without a
    history entry or [hashchange]. *)

val back : unit -> unit
(** [history.back()]: a modal's ← and its Android back button do the same. *)
