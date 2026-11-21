(** Dev-only page for [Herbier_geo_io.Geocoder] and the place-name rule. Reached
    with the URL fragment [#dev/geocode].
    - « Inverse » queues [Place_name.resolve] with both online sources on (not «
      IGN hors-ligne », no pack) and [online = true] (deliberate requests, dev
      build only: the switches are not read) for eight points at once (Col de la
      Schlucht, Figeac 44.6020, 2.0300, Pélégri 44.6300, 1.9835, Balveurche
      48.0653, 6.9946, the Landes forest, Lausanne, Kew, the Atlantic) and logs
      each request when it starts, with its time in ms since the click and its
      URL, then each point's outcome ([Place_name.outcome_to_string], or the
      error), ending with [reverse done]: two starts to the same provider must
      be at least [Geocoder.spacing_ms] apart.
    - A text field and « Chercher » run [Geocoder.search] biased on the Schlucht
      point and list name, context and coordinates of each place (a deliberate
      request: this page does not read the « Photon en ligne » switch).
    - « Noms de lieux » shows {!State.place_sources}, the codes of {!App.packs}
      (and the unreadable ones), the network and the number of geocode requests
      since the page opened ({!Hooks.geocode_requests}, « Inverse » and «
      Chercher » included), and on the next line the number of rows of
      [place_renames] (both refreshed by « Rafraîchir »). « Observation à la
      Schlucht » saves ({!App.save}) a fresh unlabelled observation without
      plant at 48.0633, 7.0081; « Observation à Belfort » the same at 47.6380,
      6.8628 (in pack 90); « Observation à Figeac » at 44.6020, 2.0300 and «
      Observation à Pélégri » at 44.6300, 1.9835; « Lieu nommé + voisine » saves
      one labelled « Lieu test » at 44.2500, -0.8500 then, in a second save, an
      unlabelled one 200 m north (44.2518, -0.8500). « Observations dans toute
      la France » saves eleven unlabelled ones: Brest 48.3904, -4.4861 (29);
      Lille 50.6292, 3.0573 (59); Strasbourg 48.5734, 7.7521 (67); Paris
      48.8566, 2.3522 (75); Perpignan 42.6887, 2.8948 (66); Ajaccio 41.9192,
      8.7386 (2A); Pointe-à-Pitre 16.2411, -61.5331 (971); Fort-de-France
      14.6161, -61.0588 (972); Cayenne 4.9224, -52.3135 (973); Saint-Denis
      -20.8823, 55.4504 (974); Mamoudzou -12.7806, 45.2279 (976). After each tap
      the page polls every second for 15 s and shows each created observation's
      [place_derived] (« Lieu inconnu » when it has none), followed by
      [" / <place_detail>"] when it has a detail, and the requests started since
      the tap (provider and URL). *)

val el : (App.t, string) result -> Brr.El.t
(** A fresh element. Without the app (its error string), the « Noms de lieux »
    block says so; « Inverse » and « Chercher » work either way. *)
