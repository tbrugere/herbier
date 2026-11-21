(** Tela Botanica eFlore API (architecture §6, regional layer): the BDTFX name
    bridge (nn and TaxRef id from a scientific name), the taxon record and
    Baseflor. Requests are [Source.Tela], base
    ["https://api.tela-botanica.org/service:eflore:0.1"]; no custom header.

    Decoders follow the field rules of {!Decode}. Keys holding a dot
    (["nom_retenu.id"], ["presence.libelle"]) are literal member names. *)

val base : string
(** ["https://api.tela-botanica.org/service:eflore:0.1"] *)

(** {1 Requests} *)

val names : name:string -> Request.t option
(** [bdtfx/noms?masque=<name>&retour.format=min] (the trimmed [name]; query in
    that order). [None] when the trimmed name is blank. Tela matches [nom_sci]
    exactly and answers 404 for a name it does not know. *)

val taxon : nn:int -> Request.t
(** [bdtfx/taxons/<nn>]. For a synonym nn Tela answers the accepted taxon. *)

val baseflor : nn:int -> Request.t
(** [baseflor/informations/bdtfx.nn:<nn>] (one path segment, so the [:] is sent
    as [%3A]). 404 when Baseflor has no row for the taxon. *)

(** {1 Payloads} *)

type name = {nn : int; nom_sci : string; retenu : bool}

val equal_name : name -> name -> bool
val pp_name : Format.formatter -> name -> unit

val names_of_json : Yojson.Safe.t -> (name list, Decode.error) result
(** The members of the required [resultat] object, in payload order: key = nn
    (all digits and fits an [int]; other keys dropped), required [nom_sci] (an
    element without it dropped), [retenu] = the string ["true"] or the bool
    [true]. [resultat] missing or not an object →
    [Unexpected "/resultat" "object"]. An empty object, or an empty array (an
    empty PHP map) → [Ok []]. *)

val pick : name:string -> name list -> name option
(** The entry whose [nom_sci] equals the trimmed [name] exactly: the first
    [retenu] one, else the first one; [None] when none matches. *)

type taxon = {
  id : int;  (** The accepted nn (Tela answers the accepted taxon). *)
  nom_sci : string;
  cd_nom : int option;  (** TaxRef id; [None] when absent or not all digits. *)
  presence : string option;  (** [presence.libelle] *)
  statut_origine : string option;  (** [statut_origine.libelle] *)
}

val equal_taxon : taxon -> taxon -> bool
val pp_taxon : Format.formatter -> taxon -> unit

val taxon_of_json : Yojson.Safe.t -> (taxon, Decode.error) result
(** Required [id] (a string of digits, or an int) and [nom_sci]; [id] present
    but not digits → [Unexpected "/id" "digits"]. *)

type baseflor = {
  floraison : string option;  (** ["5-9"]; [""] → [None]. *)
  carac_ecolo : string option;
  chorologie : string option;
  type_bio : string option;
      (** [type_bio.detail]["type.principal"][0].libelle when present, else
          [type_bio.libelle]. *)
  lumiere : string option;  (** [ve_lumiere.libelle] *)
  humidite_edaph : string option;  (** [ve_humidite_edaph.libelle] *)
  reaction_sol : string option;  (** [ve_reaction_sol.libelle] *)
  nutriments_sol : string option;  (** [ve_nutriments_sol.libelle] *)
}

val equal_baseflor : baseflor -> baseflor -> bool
val pp_baseflor : Format.formatter -> baseflor -> unit

val baseflor_of_json : Yojson.Safe.t -> (baseflor, Decode.error) result
(** Required [nom_sci] (the root must be an object). *)
