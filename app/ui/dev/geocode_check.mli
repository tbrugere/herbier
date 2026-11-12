(** Dev-only page for [Herbier_geo.Geocoder] and the place-name rule. Reached
    with the URL fragment [#dev/geocode].
    - « Inverse » queues [Place_name.resolve] with both online sources on and
      [online = true] (deliberate requests, dev build only: the switches are not
      read) for five points at once (Col de la Schlucht, the Landes forest,
      Lausanne, Kew, the Atlantic) and logs each request when it starts, with
      its time in ms since the click and its URL, then each point's outcome
      ([Place_name.outcome_to_string], or the error), ending with
      [reverse done]: two starts to the same provider must be at least
      [Geocoder.spacing_ms] apart.
    - A text field and « Chercher » run [Geocoder.search] biased on the Schlucht
      point and list name, context and coordinates of each place (a deliberate
      request: this page does not read the « Photon en ligne » switch).
    - « Noms de lieux » shows {!State.place_sources}, the network and the number
      of geocode requests since the page opened ({!Hooks.geocode_requests}, «
      Inverse » and « Chercher » included). « Observation à la Schlucht » saves
      ({!App.save}) a fresh unlabelled observation without plant at 48.0633,
      7.0081; « Lieu nommé + voisine » saves one labelled « Lieu test » at
      44.2500, -0.8500 then, in a second save, an unlabelled one 200 m north
      (44.2518, -0.8500). After each tap the page polls every second for 15 s
      and shows each created observation's [place_derived] (« Lieu inconnu »
      when it has none) and the requests started since the tap (provider and
      URL). *)

val el : (App.t, string) result -> Brr.El.t
(** A fresh element. Without the app (its error string), the « Noms de lieux »
    block says so; « Inverse » and « Chercher » work either way. *)
