(** 4m « Identification » (6h), the first section under the account card: what
    goes under its title ({!Herbier_ui_model.Identify_settings.section_title},
    the section itself is 4m's), one sand card:
    - the switch « Identifier dès la photo » ({!App.identify_on_photo},
      {!App.set_identify_on_photo}); togglable without a key (the setting is
      kept; it then does nothing);
    - the button row « Flore Pl@ntNet » with
      {!Herbier_ui_model.Identify_settings.flora_row}'s detail and note and a
      chevron; [aria-disabled] and inert when not enabled; [aria-expanded]. A
      tap opens a list right under the row, inside the card, like the
      département picker: « Chargement… », then a search field
      ({!Herbier_ui_model.Identify_settings.search_placeholder}, focused) and
      one {!Widgets.List_row} per {!Herbier_ui_model.Identify_settings.filter}ed
      {!Herbier_ui_model.Identify_settings.choices} (meta « Choisie » and
      [aria-current="true"] on the selected one); a tap on a row →
      {!App.set_plantnet_flora}, the list closes and its search is cleared; a
      second tap on the flora row closes it. A failure of {!App.floras} shows
      {!Herbier_ui_model.Identify_settings.flora_list_error} ([Plantnet e]) or
      {!Herbier_ui_model.Identify_settings.flora_list_offline}
      ([Identify_offline]) with « Réessayer » (asks again: the list is free).
      The list is asked with the key of {!App.identify_gate}'s [Ready k] only;
      it closes when the row becomes disabled (offline, key cleared);
    - the row « Clé API Pl@ntNet » with
      {!Herbier_ui_model.Identify_settings.key_detail} and « Modifier »
      ([aria-disabled] while [Loading]); « Modifier » shows a password field
      (empty: the stored key is never shown back nor prefilled;
      [type="password"], [autocomplete="off"], [autocapitalize="off"],
      [autocorrect="off"], [spellcheck="false"]), « Enregistrer » (also Enter) →
      {!App.set_plantnet_key} with the field's text (blank clears the key),
      inert while it runs; Ok → the editor closes and its text is dropped; Error
      → {!Herbier_ui_model.Identify_settings.key_not_saved} ([role="alert"]),
      editor kept; « Annuler » closes it and drops the text;
    - under the key row, always, the help line: [key_help_before], a link
      [key_help_link] to [key_help_url] ([target="_blank"],
      [rel="noopener noreferrer"], opened outside the app as 4m's dashboard
      link), [key_help_after].

    A failed write of the switch or of a flora choice shows
    {!Herbier_ui_model.Settings_text.not_saved} ([role="alert"]) under the card,
    cleared by the next successful one. Under the card, the footnote
    {!Herbier_ui_model.Identify_settings.footnote}. No value of this section
    reaches the console. *)

type t = {
  els : Brr.El.t list;  (** the card, the error line, the footnote *)
  bindings : Rb.binding list;
}

val v : App.t -> t
