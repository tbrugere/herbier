(lang dune 3.24)

(name herbier)
(generate_opam_files true)
(formatting (enabled_for ocaml))

(license MIT)
(authors "Tristan Brugère")
(maintainers "Tristan Brugère")
(source (github tbrugere/herbier))

(package
 (name postgrest)
 (synopsis "Sans-IO PostgREST client: typed columns, rows, filters, requests")
 (depends
  (ocaml (>= 5.3))
  (yojson (>= 2.0))
  (ptime (>= 1.0))
  (alcotest :with-test)))

(package
 (name herbier)
 (synopsis "Personal plant notebook for Android (js_of_ocaml + Capacitor)")
 (depends
  (ocaml (>= 5.3))
  (dune (>= 3.24))
  (js_of_ocaml (>= 6.0))
  (js_of_ocaml-compiler (>= 6.0))
  brr
  react
  reactiveData
  ptime
  uuidm
  yojson
  (postgrest (= :version))
  (alcotest :with-test)
  (ocamlformat (and :with-dev-setup (= 0.29.0)))))
