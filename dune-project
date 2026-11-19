(lang dune 3.24)

(name herbier)
(generate_opam_files true)
(formatting (enabled_for ocaml))

(license CECILL-B)
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
  ppx_string
  (uri (>= 4.0))
  (alcotest :with-test)))

(package
 (name postgrest-codegen)
 (synopsis "Generates postgrest column declarations from a Postgres catalog")
 (description
  "postgrest-codegen reads the Postgres catalog of a database's tables (the
output of its catalog.sql) and prints the Postgrest.Col declarations of
those tables as OCaml. A build-time tool, separate from the postgrest
library so that the library does not depend on ppxlib.")
 (depends
  (ocaml (>= 5.3))
  (postgrest (= :version))
  (yojson (>= 2.0))
  (ppxlib (>= 0.36))
  (ppx_deriving_yojson (>= 3.10))
  (alcotest :with-test)
  (fmt :with-test)))

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
  (ppx_deriving (>= 6.2))
  (ppx_deriving_yojson (>= 3.10))
  (uri (>= 4.0))
  (postgrest (= :version))
  (postgrest-codegen (and :with-test (= :version)))
  (alcotest :with-test)
  (ocamlformat (and :with-dev-setup (= 0.29.0)))))
