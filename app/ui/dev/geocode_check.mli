(** Dev-only page for [Herbier_geo.Geocoder]. « Inverse » queues
    [Geocoder.reverse] for five points at once (Col de la Schlucht, the Landes
    forest, Lausanne, Kew, the Atlantic) and logs each request when it starts,
    with its time in ms since the click and its URL, then each point's outcome
    (the « Près de … » phrase, [aucun lieu], or the error), ending with
    [reverse done]: two starts to the same provider must be at least
    [Geocoder.spacing_ms] apart. A text field and « Chercher » run
    [Geocoder.search] biased on the Schlucht point and list name, context and
    coordinates of each place. Reached with the URL fragment [#dev/geocode]. *)

val el : unit -> Brr.El.t
