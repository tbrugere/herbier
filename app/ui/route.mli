(** Where the app is: the URL fragment, parsed. Screens navigate with {!go} and
    {!back}; {!Router} follows the fragment. *)

(** Full-screen modals over the tabs (no tab bar). *)
type modal =
  | Tags  (** 4l *)
  | Plant of Herbier_domain.Ids.Plant_id.t  (** the fiche, 4f/4g *)
  | Edit_plant of Herbier_domain.Ids.Plant_id.t  (** 5a *)
  | New_plant  (** 5a, creating *)
  | Observation of Herbier_domain.Ids.Observation_id.t  (** 4h *)
  | Change_species of Herbier_domain.Ids.Observation_id.t  (** 5c *)
  | Move_point of Herbier_domain.Ids.Observation_id.t  (** 5b *)
  | Identify of Herbier_domain.Ids.Observation_id.t  (** 4k *)
  | Record  (** 4d *)
  | Recorded of {
      observation : Herbier_domain.Ids.Observation_id.t;
      identify : bool;
    }
      (** 4h right after 4d's Enregistrer; [identify]: ask 4h to open the
          identification layer at arrival. 4h rewrites the URL to
          [Observation observation]'s at once ({!canonicalize}). *)
  | Viewer of Herbier_domain.Ids.Photo_id.t  (** 5e *)
  | Reference_photo of {
      plant : Herbier_domain.Ids.Plant_id.t;
      organ : Herbier_domain.Reference.Organ.t;
    }  (** 5e read-only over 4f's organ photos *)
  | Search of string  (** 4i, prefilled with this query (may be [""]) *)
  | Link_species of Herbier_domain.Ids.Plant_id.t
      (** 4i for one plant: 4g « Lier », 5a « Changer › » *)
  | Intercepted of {text : string; outside : bool}
      (** 4j for [text], never blank: a link or share from another app
          ([outside], {!Intake}), or one given inside Herbier *)
  | Drive_folder  (** 4m « Dossier Drive »: the Drive account and folder *)

type t = Tab of Widgets.Tab_bar.tab | Modal of modal | Dev of string

val of_fragment : string -> t
(** [""], ["collection"] → [Tab Collection]; ["carte"], ["journal"],
    ["reglages"]; ["tags"] → [Modal Tags]; ["reglages/dossier-drive"] →
    [Modal Drive_folder]; ["plante/<id>"] → [Modal (Plant id)];
    ["plante/<id>/modifier"] → [Modal (Edit_plant id)]; ["plante/nouvelle"] →
    [Modal New_plant]; ["observation/<id>"], ["observation/<id>/espece"],
    ["observation/<id>/position"], ["a-identifier/<id>"] → [Observation],
    [Change_species], [Move_point], [Identify]; ["noter"] → [Modal Record];
    ["noter/enregistre/<id>"] →
    [Modal (Recorded {observation = id; identify = false})];
    ["noter/enregistre/<id>/identifier"] → the same with [identify = true];
    ["photo/<id>"] → [Modal (Viewer id)]; ["plante/<id>/reference/<organ>"] →
    [Modal (Reference_photo {plant = id; organ})] ([Organ.of_string]:
    ["flower"], ["leaf"], ["fruit"], ["habit"]; any other [<organ>] is
    [Tab Collection]); ["chercher"] → [Modal (Search "")]; ["chercher/<q>"] →
    [Modal (Search q)], [q] percent-decoded (undecodable: as is);
    ["plante/<id>/lier"] → [Modal (Link_species id)]; ["lien/<t>"] →
    [Modal (Intercepted {text = t; outside = true})], [t] percent-decoded as [q]
    is and taken whole (it may hold ['/']), when it is not blank; ["coller/<t>"]
    → the same with [outside = false]; ["dev/<name>"] → [Dev name]. Anything
    else (an id that is not a UUID, ["lien"], a blank ["lien/<t>"] or
    ["coller/<t>"] too) is [Tab Collection]. *)

val to_fragment : t -> string
(** Inverse of {!of_fragment} on its canonical forms ([Tab Collection] is
    ["collection"], [Search ""] is ["chercher"], [Search q] is ["chercher/"]
    then [q] as [encodeURIComponent] gives it; [Intercepted {text; outside}] is
    ["lien/"] when [outside], else ["coller/"], then [text] encoded the same
    way). *)

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
