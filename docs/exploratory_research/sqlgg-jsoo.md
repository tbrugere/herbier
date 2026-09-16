# sqlgg for the Herbier store (OCaml + js_of_ocaml + Capacitor SQLite)

Date: 2026-09-16. Sources: https://github.com/ygrek/sqlgg at commit `cec191f`
(2026-09-15), its `doc/`, opam metadata, and third-party repositories cited inline.
Nothing was compiled or executed locally (the `herbier` switch lacks the generator's
build deps); parser claims rest on reading `lib/sql_parser.mly`, `lib/sql_lexer.mll`
and `lib/sql.ml`. Anything not read directly is marked UNVERIFIED.

## Summary

- Verdict: **worth a spike.** sqlgg is alive (release 2026-07-21, commits weekly through
  2026-09-15), the OCaml output is a functor over a trait module we write ourselves, and
  the async variant (`Sqlgg_traits.M_io`, IO = `return`/`>>=`/`bracket`) fits a Brr
  `Fut.t` (or `('a, Jv.Error.t) Fut.result`) with no exceptions crossing the JS boundary.
- Main blocker: none hard. Two SQLite gaps: `RETURNING` is not in the grammar at all, and
  `CREATE VIRTUAL TABLE ... USING fts5` does not parse (only plain `CREATE TABLE`). Both
  have workarounds (`insert_id` from `last_insert_rowid`; `noparse` DDL + a shadow
  `CREATE TABLE` for typing).
- Runtime library: pure OCaml except `integers` (C stubs; `integers_stubs_js` exists,
  UNVERIFIED against current `integers`) and `Unix.gettimeofday` (jsoo provides it).
- Effort for a traits implementation over `@capacitor-community/sqlite`: about
  250-350 lines of OCaml (the shipped sqlite3 impl is ~280 lines and is the template),
  plus ~50 lines of `Jv` bindings. Estimate 1-2 days including a dune rule and a smoke test.

## 1. Status

- Latest release: `20260721`, published 2026-07-22 on GitHub, 2026-07-25 on opam
  (https://github.com/ygrek/sqlgg/releases/tag/20260721, https://opam.ocaml.org/packages/sqlgg/).
  Previous: `20231201`, `20200521`, `0.4.5` (2018).
- OCaml constraint: `>= 4.14.0` in `sqlgg.opam` on master; opam shows `>= 4.13.0` for
  20260721; release CI uses `ocaml-compiler: 4.13.x`. Needs `ppxlib >= 0.36.2`, so it
  should build on 5.x; that it builds on 5.3 specifically is UNVERIFIED.
- Activity: 15 commits between 2026-08-17 and 2026-09-15, mostly by `jongleb` (Ahrefs);
  PRs #312-#328 add Kleene nullability narrowing, an LSP server (`sqlgg-lsp.opam`, needs a
  `sqlgg.json`), foreign keys in XML output. The 2026 release notes list dialect checks,
  `ON CONFLICT`, CTEs, window functions, JSON, nullability tracking, statement cache, ppx.
- License: GPL-2.0 for the generator; `impl/` (traits, DB bindings) and generated code are
  public domain / yours (README).

## 2. How the generated code is parameterised

Generator output (`src/gen_caml.ml`): `-gen caml` emits
`module Sqlgg (T : Sqlgg_traits.M) = struct module IO = Sqlgg_io.Blocking ...`;
`-gen caml_io` emits `module Sqlgg (T : Sqlgg_traits.M_io) = struct module IO = T.IO ...`.
Queries become `T.select db (sql) set_params (fun row -> callback ~col:(T.get_column_int64 row 0) ...)`,
plus `Fold`/`List` (and `Single` for single-row) modules built with `IO.(>>=)`/`IO.return`.

`impl/ocaml/sqlgg_traits.ml` (2026-09-15), the async signature:

```ocaml
module type M_io = sig
  include M                       (* types, get_column_*, set_param_*, Types *)
  module IO : Sqlgg_io.M
  include FNS with type 'a io_future := 'a IO.future
             with type params := params with type result := result
             with type 'a connection := 'a connection with type statement := statement
             with type row := row with type execute_response := execute_response
end
```

with, from `M` and `FNS`:

```ocaml
type statement   type -'a connection   type params   type row   type result
type execute_response = { affected_rows: int64; insert_id: int64 option }
exception Oops of string
module Types : sig module Bool/Int/UInt64/Float/Text/Blob/Decimal/Datetime/Json/Json_path/One_or_all : sig
    type t  val to_literal : t -> string  (* + one *_to_literal alias each *) end  module Any : Value end
val get_column_Int : row -> int -> Types.Int.t      val get_column_Int_nullable : row -> int -> Types.Int.t option
(* same pair for Bool UInt64 Text Any Float Decimal Datetime Json Json_path One_or_all,
   and lowercase pairs on concrete types: get_column_int64 / _string / _float / _bool / _json ... *)
val start_params : statement -> int -> params
val set_param_null : params -> unit     val set_param_Int : params -> Types.Int.t -> unit   (* etc. *)
module Make_enum : functor (E : Enum) -> sig val get_column : row -> int -> E.t  ... end
val finish_params : params -> result io_future
val no_params : statement -> result io_future
val select : [>`RO] connection -> Query.t -> (statement -> result io_future) -> (row -> unit) -> unit io_future
val select_one_maybe : [>`RO] connection -> Query.t -> (statement -> result io_future) -> (row -> 'b) -> 'b option io_future
val select_one : [>`RO] connection -> Query.t -> (statement -> result io_future) -> (row -> 'b) -> 'b io_future
val execute : [>`WR] connection -> Query.t -> (statement -> result io_future) -> execute_response io_future
val execute_unprepared : [>`WR] connection -> Query.t -> execute_response io_future
```

`Sqlgg_io.M` (`impl/ocaml/sqlgg_io.ml`) is only:

```ocaml
module type M = sig
  type 'a future
  val return : 'a -> 'a future
  val (>>=) : 'a future -> ('a -> 'b future) -> 'b future
  val bracket : 'a future -> ('a -> unit future) -> ('a -> 'b future) -> 'b future
end
```

(`M_control` adds `catch`/`try_bind`/`async`/`List.iter_s`; only needed for the optional
statement cache.) `Query.t` is `{ sql; name; kind; filename }`.

Fit with the Capacitor plugin: `'a future` is abstract, so `type 'a future = ('a, Jv.Error.t) Fut.result`
works, with `return = Fut.ok` and `>>=` short-circuiting on `Error`. The row callback is
synchronous (`row -> unit`), so `select` awaits `query()` once, then iterates the returned
array; `Oops` raised by `get_column_*` inside the callback is caught in `select` and turned
into `Error`. `statement` can simply be the SQL string, `params` a growable JS array
(`start_params stmt n` allocates it, `set_param_*` push in order since sqlgg emits `?` for
sqlite), `finish_params` returns it, and `execute` reads `changes.changes`/`changes.lastId`
from `run()` (plugin API: `query(): Promise<capSQLiteValues>`, `run(): Promise<capSQLiteChanges>`,
https://github.com/capacitor-community/sqlite/blob/master/docs/API.md). One wrinkle: the
traits read columns by index while the plugin returns rows as objects keyed by name;
`Object.values` preserves insertion order for non-integer-like keys, so index access works
as long as no column alias is a numeral and no two result columns share a name (sqlgg's
labeled callbacks already force distinct names). The two shipped non-sqlite impls
(`impl/ocaml/mariadb/sqlgg_mariadb.ml`, Lwt-capable via a functor over `Sqlgg_io.M`) and
the ~280-line `impl/ocaml/sqlite3/sqlgg_sqlite3.ml` are the templates.

## 3. Does it compile under js_of_ocaml?

The generator is a build-time native binary; only `sqlgg.traits` is linked into the app.
`impl/ocaml/dune`: `(libraries integers sqlgg_json_path unix)`.

- `sqlgg_json_path`: menhir/ocamllex, pure OCaml.
- `unix`: used once, `Unix.gettimeofday` in `Sqlgg_stmt_cache.Make`; jsoo's runtime
  defines `caml_unix_gettimeofday` (`runtime/js/unix.js`), and `Make_with_clock` lets us
  supply a clock anyway.
- `integers`: `Unsigned.UInt64.t` appears in the `M` signature (`get_column_UInt64`,
  `set_param_uint64`), so every implementation links `integers`, which has C stubs.
  `integers_stubs_js` 1.0 (2020-09, O(1) Labs, deps `js_of_ocaml >= 3.6`, `zarith_stubs_js`)
  provides JS stubs; whether it covers the primitives of current `integers` (0.7.x) is
  UNVERIFIED. SQLite has no unsigned type, so those functions can `failwith` as the shipped
  sqlite3 impl does; the only question is linking.
- No C stubs, no `Str`, no threads in the traits library. `Sqlgg_trait_types.json` is a
  polymorphic variant compatible with `Yojson.Safe.t` without depending on yojson.

## 4. SQLite dialect coverage (parser reading, not executed)

`-dialect sqlite` exists (`lib/dialect.ml`: MySQL, PostgreSQL, SQLite, TiDB) and only checks
a list of feature flags (collation, on_conflict, autoincrement, ...); it does not add syntax.

| Construct | Status | Evidence |
|---|---|---|
| `INSERT ... ON CONFLICT (cols) DO UPDATE SET x = excluded.x` / `DO NOTHING` | supported | `conflict_clause` rule, `excluded` handled in `syntax.ml:1734`; changelog 20260721 |
| `RETURNING` | **not supported** | token absent from lexer and grammar; use `execute_response.insert_id` (= `lastId`) |
| `CREATE VIRTUAL TABLE ... USING fts5(...)` | **does not parse** | only `CREATE [TEMPORARY] TABLE [IF NOT EXISTS]` and `CREATE TABLE/VIEW AS SELECT` rules; `VIRTUAL` token is for generated columns |
| `col MATCH @q` | parses | lexer maps `match`/`glob`/`regexp` to `LIKE_OP`, param typed Text |
| CTEs incl. `WITH RECURSIVE`, reusable CTEs | supported | `cte_with` rule; `doc/sql/cte.md` |
| Window functions (`OVER`, `lag`, `lead`, `first_value`, `last_value`, `nth_value`) | supported | parser lines 613-636; `test/window.sql` |
| `row_number()`/`rank()` `OVER` | parses, typing UNVERIFIED | goes through `Function.lookup_agg`; names not found in `sql.ml` |
| `strftime`, `date`, `julianday` | typed | `sql.ml:1297-1301`; `unixepoch` absent (warning, untyped) |
| `json_extract`, `->`, `->>` | typed | `sql.ml:1415`, parser 528-529 |
| `INSERT ... VALUES @list`, `IN @list`, `(a,b) IN @pairs`, `{ ... }?` optional clauses, `@choice` | supported | `doc/ocaml/specifics.md` |

Unknown functions are not errors: `sql.ml:1248` prints `W: unknown function ... treating as
untyped` and the result becomes `Any` (string). Unsupported *statements* have an escape hatch:
`-- [sqlgg] noparse` marks a statement `Verbatim` (`lib/props.ml`, `lib/compile.ml`), and
`src/main.ml:95` emits it as kind `Other` with no schema and no params, i.e. a function that
runs the raw text. So FTS5 DDL goes in as `noparse`, and a shadow
`CREATE TABLE plant_fts (name TEXT, ...)` in a file passed with `-open` gives the typer the
columns without generating code for it. No per-statement manual type override exists;
`@param :: TYPE [NULL]` annotates parameters and `[sqlgg] module=` wraps column types.

## 5. Schema, nullability, dune

- Schema: `CREATE TABLE` statements are parsed in order and build the typing environment;
  they may live in the same `.sql` as queries or in separate files: `sqlgg -gen none ddl.sql
  -gen caml dml.sql`, or `-open schema.sql` to load definitions without generating code
  (`doc/sql/ddl.md`, `doc/_cli-options.md`). `ALTER TABLE` updates the schema for later
  statements. `-migrate`/`-diff` generate migrations from schema diffs (`doc/migrations.md`).
- Nullability (`doc/sql/nullability.md`): `PRIMARY KEY`/`NOT NULL` strict, otherwise
  nullable; nullable propagates through expressions, LEFT JOIN right side, scalar subqueries,
  aggregates without GROUP BY; `COALESCE` removes it. Nullable columns become `'a option`
  read via `get_column_*_nullable`; nullable params (`@x :: TEXT NULL`, or `{ clause }?`)
  become `'a option` and emit `match ... None -> T.set_param_null`. `-allow-write-notnull-null`
  relaxes writes. Single-row detection (`LIMIT 1`, PK equality) selects `select_one_maybe`.
- Dune rule (`doc/getting-started.md`, `doc/ocaml/traits.md`):

```lisp
(rule
 (target sql_file.ml)
 (mode promote)
 (action (with-stdout-to %{target}
   (run sqlgg -gen caml_io -dialect sqlite -params unnamed -static-header %{deps})))
 (deps file.sql))
```

  and the consuming library lists `sqlgg.traits`. `-params unnamed` is the sqlite default.
- Extras: `sqlgg.ppx` (`[@@deriving sqlgg]`) maps results to records; `dynamic_select=true`
  picks columns at runtime; `[sqlgg] module=Ship_id` wraps a column in a domain type.

## 6. Prior art with non-C / custom backends

- `test/cram/print_impl.ml` (in-repo): a mock `Sqlgg_traits.M` with no database at all,
  used by the cram tests; proof the trait boundary is self-contained.
- https://github.com/AngelVI13/unto `lib/db/turso.ml` (2025): `Sqlgg_traits.M` over Turso's
  HTTP pipeline API (JSON rows via `ezcurl`), copied from the sqlite3 impl. Native, blocking.
- https://github.com/ProgramingIsTheFuture/ocaml-immudb `examples/sqlgg_demo/immudb_trait.ml`:
  `Sqlgg_traits.M` over immudb's HTTP API (cohttp-lwt run under `Lwt_main.run`).
- https://github.com/Niols/dancelor `src/server/database/sqlgg_postgresql.mli`: a custom
  `M_io` with `type 'a IO.future = 'a Lwt.t` over the `postgresql` library, showing the
  `M_io with type ... IO.future = ...` constraint pattern we would use for `Fut`.
- No js_of_ocaml or Brr implementation was found (GitHub code search for sqlgg with jsoo,
  Brr, Fut returned nothing relevant). The Capacitor traits would be the first; the JSON-row
  HTTP backends above are the closest analogue and are small.

## Open points for the spike

1. Link check: `sqlgg.traits` + `integers` + `integers_stubs_js` under jsoo on OCaml 5.3.
2. Confirm `Object.values` column ordering assumption on Android (or read column names
   from `capSQLiteValues` when the platform supplies them) and decide how `row` is typed.
3. Try the FTS5 `noparse` + shadow-table trick and a `MATCH` query end to end.
4. Datetime mapping: `Types.Datetime.t` is ours to choose (ISO-8601 string is natural for
   SQLite); check that `strftime` on such a column typechecks as Text.
