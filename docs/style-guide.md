# Herbier — OCaml style guide

How code is written. What the app does is decided by the mockup and by
`architecture.md`; nothing here is a feature decision.

Assumed context: OCaml through js_of_ocaml, UI on Brr + ocaml-react +
ReactiveData via our glue module `app/ui/rb.ml`. See `stack.md` and
`notes/ocaml-react-primer.md`.

## 1. Paradigm

**No objects, no classes**, no inheritance, no `#` method calls. The only
exception is an FFI or database binding that forces one; wrap it in a module
and never let the object type escape.

## 2. Avoiding imperative code

2.1 Reach for iteration in this order: (1) `List.map` / `filter_map` /
`fold_left` / `iter` / `exists` and friends (same for `Array`, `Option`,
`Result`, `Seq`); (2) a tail-recursive helper with an accumulator; (3) a
plain recursive function. `for`, `while`, `ref` and mutable fields come
after all three and need a reason.

2.2 `ref` and mutable fields are acceptable in two places:

- a small local scope where the mutation cannot be observed from outside —
  a counter inside one function, a `Buffer`, a table built and consumed in
  the same function;
- state the platform forces on us: a JS library handle (MapLibre map,
  `<video>` element), an `Ev.listener` id we must keep to unlisten, a
  DOM-side cache. Keep it behind a module boundary.

2.3 `ignore` on a non-`unit` value is a smell outside FFI calls. No `@`
inside a loop: build reversed and `List.rev` once, or `List.concat_map`.
Annotate types at module boundaries (the `.mli`); let inference work inside.

2.4 **`Seq` for lazy or potentially large sequences**: paging through pull
results, iterating a database cursor, streaming a file list. Compose with
`Seq.map` / `filter` / `take` / `fold_left` without building intermediate
lists; `List.to_seq` and `Seq.to_list` at the boundaries only. Do not
convert back and forth, and do not use `Seq` where a plain list is small and
already materialised.

## 3. Pattern matching

3.1 **Prefer `match` over `if`.** `if` is for a genuine two-way boolean test
with short branches; three cases, or a scrutinee worth naming, is a `match`.

3.2 **Destructure in the definition** — `function`, or patterns in the
parameter list — rather than binding an argument and immediately matching.

```ocaml
(* no *)  let label t = match t with Wild -> "sauvage" | Cultivated -> "cultivée"
(* yes *) let label = function Wild -> "sauvage" | Cultivated -> "cultivée"
(* yes *) let distance { lat = a; lon = b } { lat = c; lon = d } = ...
```

3.3 **Guarded `match ()` instead of an if/else chain**, when several
independent conditions pick a branch:

```ocaml
match () with
| () when photo.local_path <> None -> Local photo.local_path
| () when photo.drive_id <> None -> Remote photo.drive_id
| () -> Missing
```

3.4 No wildcard `_ ->` on our own variants: listing the cases is what makes
the compiler point at every site when a constructor is added. `_` is fine on
third-party variants. Elsewhere prefer a richer pattern to a `when` guard,
which defeats exhaustiveness checking.

## 4. Abstraction

4.1 **Write the concrete thing.** Do not generalise for a second caller that
does not exist; two similar functions beat one with a mode argument. No
premature `'a`: a function that only ever sees plants should say so.

4.2 When genuine genericity is needed, **use a functor** — not first-class
modules, not a record of functions, not a `~f` bundle.

```ocaml
module Make_store (K : Key.S) : sig
  type t
  val get : t -> K.t -> K.value option
end
```

4.3 First-class modules only when the choice is truly made at runtime (e.g.
which regional data provider is enabled); records of functions only at an
FFI boundary where a JS callback table is what the other side wants.

## 5. Types

5.1 **Make illegal states unrepresentable.** Prefer a variant over a record
whose fields are only meaningful in certain combinations.

```ocaml
(* no  *) type sync = { pending : bool; error : string option; at : float option }
(* yes *) type sync = Pending | Failed of Error.t | Synced of float
```

5.2 Variants and records are the default; a bare tuple only for an obvious
pair with no domain meaning. Wrap identifiers (`Plant_id.t`,
`Observation_id.t`) so they cannot be swapped.

5.3 **Polymorphic variants** when the set is genuinely open or shared
without a common definition — CSS class names, route fragments:

```ocaml
val class_of : [ `Card | `Chip | `Chip_active | `Tab_bar ] -> string
val route : [ `Collection | `Species of Plant_id.t | `Note ] -> string
```

Not as a way to skip declaring a type, and never an inferred row type in an
`.mli`: write the closed list.

5.4 **GADTs** when they buy real safety. Expected here: typed settings keys
and the column types of `Postgrest` (`Ty.t`, `('table, 'a) col`).

```ocaml
type _ key =
  | Offline_tiles : bool key
  | Preview_quality : float key
  | Region : string option key

val get : 'a key -> 'a
```

## 6. Binding operators

6.1 Use `let*` / `let+` / `and+` instead of nested `map`/`bind`. Every
module that offers them defines them in a submodule named `Syntax`.

6.2 For signals: `let+` = `S.map`, `and+` = `S.Pair.pair` (static graph, the
default). There is no `let*` on signals: the only dynamic part of the graph
is navigation, and the router builds each screen with an `S.map ~eq:( == )`
and releases the previous one explicitly (primer §6) instead of `S.bind`.

```ocaml
let header =
  let open Signal.Syntax in
  let+ n = count and+ tag = active_tag in
  Printf.sprintf "%d plantes%s" n
    (match tag with None -> "" | Some t -> " · " ^ t.name)
```

6.3 The same operators exist for `Option`, `Result` and `Fut`/`Lwt` where we
use them, with the usual meaning (`let*` = bind, `let+` = map).
`Postgrest.Row.Syntax` is applicative only: `let+` / `and+`, no `let*`.

6.4 **Disambiguate by opening `Syntax` locally**, inside the function that
needs it. Never open one at module top level, never two in the same scope;
if a function needs both (a `Fut` inside a signal derivation), split it.

```ocaml
let load id =
  let open Fut.Syntax in
  let* row = Db.find id in
  let+ photos = Photos.of_plant id in
  { row with photos }
```

6.5 `and+` on signals defaults to structural equality; when a side carries
closures or JS objects use `S.l2 ~eq:( == )` explicitly instead.

## 7. Modules

7.1 One concern per file; small modules over big ones. Splitting is cheap.
**An `.mli` for every non-trivial module.** The signature documents
intent: smallest surface that works, main type abstract unless callers
genuinely need the fields.

7.2 The main type of a module is `t`, and functions read as `Plant.name`,
`Plant.create`, `Plant.to_json` — no redundant prefix inside the module.

7.3 `snake_case` for values, types, fields and files; `Capitalised_snake`
for modules. No top-level `open` of project modules; use `let open ... in`
or `M.(...)`.

## 8. Errors

8.1 Recoverable failure is `('a, Error.t) result` with a project-local
variant. Strings are not an error type.

```ocaml
type t = Network of { status : int option } | Not_found
       | Original_missing | Parse of string
```

8.2 Exceptions are for bugs and broken invariants, and are caught only at
the top-level screen boundary, where they are logged and shown once.

8.3 **No `Option.get`, `List.hd`, `List.nth`, `Hashtbl.find` or
`int_of_string`** on data from the network, the database, the filesystem, a
URL or the DOM. Use the `_opt` variants and match.

8.4 A remote payload that fails to parse degrades that field, never the
screen.

## 9. Reactive code

9.1 State is a signal, a happening is an event; never keep state in an
event.

9.2 Functions given to `S.map`, `E.map`, `S.l2` … are **pure**. No setter
call inside an update step — `set` and `send` raise there. If a reaction
must cause a change, derive it (`S.hold`, `S.sample`, `S.accum`).

9.3 Setters are called only from outside the graph: DOM callbacks, promise
resolutions, plugin callbacks, timers. Primitives that change together share
one `Step`.

9.4 Every binding a screen creates is collected in that screen's list,
which stays reachable until the screen is torn down (the router holds the
current screen's: js_of_ocaml 6 implements weak arrays with `WeakRef`, so an
unreferenced binding is collected and silently stops, primer §5), and is
released on teardown with `S.stop ~strong:true` / `E.stop ~strong:true`
(there is no `S.keep`). Strongly stop your own leaf bindings only, never a
shared intermediate signal.

9.5 Signals of closures, elements or JS objects carry `~eq:( == )`. List
signals feeding the DOM go through `ReactiveData.RList` with an `eq`
comparing ids and `updated_at`, not whole records.

## 10. FFI

10.1 All `Jv` and raw interop lives in dedicated binding modules
(`app/bindings/maplibre.ml`, `app/bindings/cap_*.ml`), one per JS library or
plugin, each with an `.mli` even when the implementation is three lines.

10.2 The binding converts at the boundary: plain OCaml types and `result`
in and out. **`Jv.t` never appears in a domain module's signature.**
`Brr.El.t` is allowed in UI modules only.

## 11. Formatting

`ocamlformat` decides layout. `.ocamlformat` is checked in:

```
version = 0.29.0
profile = default
margin = 80
```

No hand alignment, no formatting-only diffs, no `[@@@ocamlformat]` override
without a comment saying why. CI runs `dune build @fmt`.

## 12. Tests

12.1 `dune test` with **alcotest** (decided), one test executable per
library that has no Brr dependency (`domain`, `postgrest`, `refs`) under
`test/`. Browser-side tests only if the UI spike's leak check fails.

12.2 Worth testing: pure domain logic (distances, filters, dates/seasons);
**sync merge rules** — outbox ordering, last-write-wins, soft delete, clock
skew, where silent data loss lives; parsers and mappers (GBIF/Wikidata/Tela
payloads, shared-link interception, EXIF); and the `Error.t` paths, not only
the happy one.

12.3 Not worth testing: DOM rendering, react's own semantics, third-party
APIs. Mappers run against small fixtures in `test/fixtures/`, never the live
network.

## 13. Comments and docs

13.1 Doc comments (`(** ... *)`) live in the `.mli`, on the module and on
each exported value that is not self-explanatory: what it guarantees, what
it does on failure.

13.2 `(* ... *)` in `.ml` files explains **why** — an invariant, a WebView
workaround, a link to the source doc — never what. Code needing a "what"
comment should be renamed or split. Mark a deliberate deviation from this
guide with `(* style: ... because ... *)`.
