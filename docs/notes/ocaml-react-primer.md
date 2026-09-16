# ocaml-react primer, for Herbier

Written 2026-09-16 against react 1.2.2 (`react.mli`). A working reference
for the UI layer decided in `../stack.md`. Quoted phrases come from the
library's own documentation.

## 1. The two primitives

react is functional reactive programming (FRP). It models values that vary
over time, with two types.

**A signal, `'a S.t` (alias `'a signal`), has a value at every instant.**
Its meaning is a function of time returning `'a`. Examples in Herbier: the
active tag filter (`tag option signal`), the list of plants
(`plant list signal`), whether we are online (`bool signal`), the current
bottom-sheet offset (`float signal`).

**An event, `'a E.t` (alias `'a event`), occurs at discrete instants and
carries a value when it does.** Its meaning is a function of time returning
`'a option`: `Some v` when it occurs, `None` otherwise. Examples: a tap on a
chip (`tag event`), a Pl@ntNet link arriving through the share sheet
(`string event`), a sync round finishing (`unit event`).

Rule of thumb: state is a signal, a happening is an event. A signal always
has a current value you can read; an event does not.

## 2. Creating and reading

```ocaml
open React

(* a primitive signal and its setter *)
let active_tag, set_active_tag = S.create None
  (* S.create : ?eq:('a -> 'a -> bool) -> 'a -> 'a signal * (?step:step -> 'a -> unit) *)

(* a primitive event and its sender *)
let chip_tapped, send_chip_tapped = E.create ()
  (* E.create : unit -> 'a event * (?step:step -> 'a -> unit) *)

(* reading a signal *)
let current = S.value active_tag
```

`S.create` and `E.create` are the only places where the outside world enters
the system. Everything else is derived from these primitives by combinators.
Calling `set_active_tag (Some t)` "sets the signal's value to `v` at the time
it is called and triggers an update step" (see §4).

`S.value` reads the current value. Its documentation warns: "If executed in
an update step may return a non up-to-date value or raise `Failure` if the
signal is not yet initialized." Read signals from outside the propagation,
or better, do not read them at all and derive instead.

## 3. Deriving: the combinators

Derived signals and events recompute automatically when their inputs change.
You describe the dependency graph once; react maintains it.

**Signal to signal**

```ocaml
S.map  : ?eq -> ('a -> 'b) -> 'a signal -> 'b signal
S.l2   : ?eq -> ('a -> 'b -> 'c) -> 'a signal -> 'b signal -> 'c signal   (* l1..l6 *)
S.app  : ?eq -> ('a -> 'b) signal -> 'a signal -> 'b signal

let visible = S.l2 (fun tag ps -> filter_by_tag tag ps) active_tag plants
let counter = S.map (fun ps -> List.length ps) visible
```

**Event to event**

```ocaml
E.map    : ('a -> 'b) -> 'a event -> 'b event
E.filter : ('a -> bool) -> 'a event -> 'a event
E.fmap   : ('a -> 'b option) -> 'a event -> 'b event
E.select : 'a event list -> 'a event
  (* "the occurrences of every event in el. If more than one event occurs
     simultaneously the leftmost is taken and the others are lost." *)
E.merge  : ('a -> 'b -> 'a) -> 'a -> 'b event list -> 'a event
  (* merges simultaneous occurrences with an accumulator instead of dropping *)
```

**Event to signal, signal to event** (the bridges)

```ocaml
S.hold    : ?eq -> 'a -> 'a event -> 'a signal
  (* "has the value of e's last occurrence or i if there wasn't any" *)
S.accum   : ?eq -> ('a -> 'a) event -> 'a -> 'a signal
  (* apply each occurrence as a function to the accumulated state *)
S.fold    : ?eq -> ('a -> 'b -> 'a) -> 'a -> 'b event -> 'a signal
S.changes : 'a signal -> 'a event
  (* occurs each time the signal's value changes (per eq) *)
S.sample  : ('b -> 'a -> 'c) -> 'b event -> 'a signal -> 'c event
  (* "samples s at e's occurrences": read a signal's value when an event fires *)
E.on      : bool signal -> 'a event -> 'a event
  (* occurrences of e only while the signal is true *)
```

A Herbier example, the search box: the DOM `input` event becomes an event of
strings, which we hold into a signal, which derives the visible plants.

```ocaml
let query_changed : string event = (* from the DOM, see rb.ml *)
let query = S.hold "" query_changed
let visible = S.l3 filter_plants query active_tag plants
```

And the reverse, "Vues ici" in the Noter screen: when the GPS fix event
arrives, sample the current plant list to compute nearby plants.

```ocaml
let nearby = S.sample (fun fix ps -> plants_within 500. fix ps) gps_fix plants
```

**Dynamic graphs: switch and bind**

```ocaml
S.switch : ?eq -> 'a signal signal -> 'a signal   (* "the inner signal of ss" *)
S.bind   : ?eq -> 'a signal -> ('a -> 'b signal) -> 'b signal
  (* "bind s sf is switch (map ~eq:( == ) sf s)" *)
E.switch : 'a event -> 'a event event -> 'a event
```

These let the graph itself change over time. Screen navigation is the
typical use: `screen : screen signal`, and the content is
`S.bind screen (function Collection -> collection_view | Species id -> species_view id)`.
Each time `screen` changes, the previous inner signal is abandoned and the new
one becomes current.

**Feedback loops: fix**

```ocaml
S.fix : ?eq -> 'a -> ('a signal -> 'a signal * 'b) -> 'b
E.fix : ('a event -> 'a event * 'b) -> 'b
```

"Allows to refer to the value a signal had an infinitesimal amount of time
before." Needed when a signal depends on its own past, for example a
pagination cursor that depends on the previous cursor. Rare in UI code;
`S.accum` and `S.fold` cover most cases.

## 3b. map vs bind, and binding operators

Unlike Lwt, where `map` is defined from `bind`, react defines `bind` from
`map`: "`bind s sf` is `switch (map ~eq:( == ) sf s)`". The two operations
mean different things in a dataflow graph:

- `map`, `l2`, `app`, `pair`: a **static** graph. Dependencies are fixed at
  construction, ranked once, updated in order. Signals are an applicative
  functor (`S.app` "holds the value of `sf` applied to the value of `s`").
  Use this by default.
- `bind`, `switch`: a **dynamic** graph. Each change of the outer signal
  runs your function, builds a new inner graph and abandons the old one
  (a switch may trigger a further update step in the same instant). Use it
  for structural changes only, in practice screen navigation. On
  js_of_ocaml the abandoned inner graph is not collected by itself, so a
  `bind` on a frequently changing value leaks one graph per change unless
  its bindings are released; at screen granularity that is one `release`
  per navigation.

react 1.2.2 ships no binding operators or infix module. Define them once:

```ocaml
module Syntax = struct
  let ( let+ ) s f = S.map f s          (* applicative, static *)
  let ( and+ ) a b = S.Pair.pair a b    (* ('a * 'b) signal; structural eq by default *)
  let ( let* ) s f = S.bind s f         (* monadic, dynamic: screen level only *)
end

let counter_label =
  let+ n = counter
  and+ tag = active_tag in
  Printf.sprintf "%d plantes%s" n
    (match tag with None -> "" | Some t -> " · " ^ t.name)
```

`let+ ... and+ ...` desugars to a `map` over a `pair`: still static and
cheap. A `let*` outside navigation code is a smell. `S.Pair.pair` defaults
to structural equality on the tuple, so pass `~eq:( == )` explicitly when a
side holds closures or JS objects instead of using `and+`.

## 4. Update steps and simultaneity

When a setter is called, react runs an **update step**: it "automatically
updates events and signals that transitively depend on the updated
primitive". Properties you can rely on:

- **Glitch-free.** Within a step every node is updated at most once, in
  dependency order. If `counter` depends on `visible` which depends on both
  `query` and `plants`, and both change in one step, `counter` is computed
  once with the final values, never with a half-updated pair.
- **Instantaneous.** "The update step takes no time, it is instantaneous"
  (the synchrony hypothesis). "Two event occurrences are simultaneous if they
  occur in the same update step."
- **Effects exactly once.** "Effectful events and signals perform their side
  effect exactly once in each update step in which there is an update of at
  least one of the event or signal it depends on." This is what makes a
  DOM-binding signal safe: it writes the DOM once per step, not once per
  input.

**Setting several primitives at once.** By default each setter call is its
own step. To change two primitives simultaneously (so derived signals see
both at once), create a step:

```ocaml
let step = Step.create () in
set_plants ~step new_plants;
set_active_tag ~step None;
Step.execute step
```

**The one rule that raises.** "`set` must not be executed inside an update
step" (same for `send`). That is, do not call a setter from inside a
function passed to `S.map`, `E.map` etc. If a reaction must trigger another
primitive, defer it: schedule it with `Fut.tick` / `setTimeout 0` / a
`requestAnimationFrame`, or express it as a derivation instead of a setter.
In UI code this comes up when a DOM binding wants to notify "I scrolled"
while it is being updated; the fix is always to derive rather than to set.

**Equality.** "Most signal combinators have an optional `eq` parameter that
defaults to structural equality." A derived signal only propagates when
its new value differs per `eq`. Two consequences:

- A signal of functions, or of anything containing closures or JS objects
  (a `Brr.El.t`, a MapLibre map), must use `~eq:( == )` or a custom
  comparison. Structural `(=)` on a closure raises at runtime.
- Choosing `eq` is also an optimisation: with a good `eq`, a recomputed list
  equal to the previous one stops propagation and the DOM is not touched.

## 5. Memory: the part that decides how the glue is written

react does not own its graph. The documentation says: "It is important to
keep references on effectful events and signals. Otherwise they may be
reclaimed by the garbage collector." Its own example:

```ocaml
let x, set_x = S.create 1
let () = ignore (S.map print_int x)
let () = Gc.full_major (); List.iter set_x [2; 2; 3]
(* prints only "1": the mapped signal was collected *)
```

On native OCaml, a primitive holds its dependents through **weak** references,
so a derived signal nobody references is collected and silently stops.

**On js_of_ocaml this reverses.** JavaScript has no weak arrays, so
js_of_ocaml gives weak arrays strong semantics. The documentation of `stop`
says so: "The `strong` argument should only be used on platforms where weak
arrays have a strong semantics (i.e. JavaScript)." Consequences for Herbier:

- Nothing is ever collected by accident. A derived signal keeps updating as
  long as its source exists, even if nothing else references it. Silent
  stops are not our bug class.
- **Leaks are.** Every binding created for a screen keeps running, and keeps
  its DOM nodes alive, after the screen is gone, unless stopped explicitly:

```ocaml
S.stop : ?strong:bool -> 'a signal -> unit
E.stop : ?strong:bool -> 'a event -> unit
```

  "`stop s` stops updating `s`. It conceptually becomes const with the
  signal's last value and cannot be restarted." With `~strong:true` it also
  "walks over the list of events and signals that it depends on and
  unregisters itself from these ones as a dependent", which is what actually
  frees memory on JS.

- Caveat from the docs: "if direct references are kept on an intermediate
  event or signal of the reactive system it may suddenly stop updating if
  all its dependents were strongly stopped." So strongly stop only the leaf
  bindings you created for a screen, never a shared intermediate signal.

**Therefore the glue rule is:** every DOM binding returns a handle, the
screen collects its handles, and leaving the screen calls
`S.stop ~strong:true` / `E.stop ~strong:true` on each. That is the `keep`
and teardown in `rb.ml`. (`S.retain` exists but only "keeps a reference to
the closure `c` in `e`"; it is a native-side trick and not what we need.)

## 6. How the glue module maps onto this

```ocaml
(* app/ui/rb.ml — react over Brr *)
type binding                      (* opaque: the stoppable node *)
val text     : El.t -> string signal -> binding
val attr     : El.t -> At.name -> string signal -> binding
val class_   : El.t -> string -> bool signal -> binding
val style    : El.t -> string -> string signal -> binding
val children : El.t -> El.t list signal -> binding
val rlist    : El.t -> ('a -> El.t) -> 'a ReactiveData.RList.t -> binding
val ev       : El.t -> 'a Ev.type' -> 'a Ev.t event * binding
val release  : binding list -> unit      (* strong stop, in one place *)
```

Each of `text`, `attr`, `class_`, `style`, `children` is `S.map` with a Brr
call as the side effect, returning the mapped signal as the binding. `ev`
is `E.create` whose sender is called from a Brr `Ev.listen` callback; the
listener id is kept in the binding so `release` can `Ev.unlisten` too.
`rlist` consumes ReactiveData patches (`I` insert, `R` remove, `U` update,
`X` move) and applies them with `El.insert_siblings` / `El.remove`.

A screen is a function that builds its DOM, creates its bindings, and
returns the root element plus the binding list. Navigation is
`S.bind screen (...)` at the top, and the top-level code releases the
previous screen's bindings when the inner signal switches.

## 6b. ReactiveData: patches for collections

A `plant list signal` is opaque to consumers: one added plant is "a new
list", so a DOM binding would rebuild every card. ReactiveData (Ocsigen,
built on react) carries **patches** next to the value:

```ocaml
type 'a p =
  | I of int * 'a     (* insert v at position i *)
  | R of int          (* remove position i *)
  | U of int * 'a     (* replace position i with v *)
  | X of int * int    (* swap i and j *)
type 'a patch = 'a p list   (* sequential; indices relative to the state after the previous step *)
```

API in the order you meet it:

- `RList.create : 'a list -> 'a t * 'a handle`; the handle has `cons`,
  `snoc`, `insert v i`, `remove i`, `update v i`, `move i offset`, `set`,
  `patch`. Same split as `S.create`: the `'a t` is read and derived from,
  the handle mutates.
- `RList.map f l`: "`f` is applied only on the new or modified elements".
  `RList.map plant_card visible` runs `plant_card` once per inserted plant.
  Also `filter`, `concat`, `rev`, `singleton_s` (a signal as a one-element
  list, to mix a header with a dynamic list in one child sequence).
- Bridges: `RList.signal l : 'a list signal` (value only, e.g. for a
  counter), `RList.event l : 'a msg event` (the patch stream the `rlist`
  binding subscribes to), `RList.fold`.
- `RList.from_signal ?eq (s : 'a list signal)`: diffs consecutive values
  into patches, "downstream computation only on the new and modified
  elements". Keep computing `visible` with `S.l3 filter_plants ...` and
  wrap it once. Pass an `eq` that compares ids and `updated_at`, not full
  records with thumbnails.

Two feeding styles will both appear: handle-driven when the code knows the
structural change (outbox result "plant X inserted" → `RList.insert`), and
`from_signal` for derived, filtered, sorted lists (Collection, Journal,
chips). Patches are positional, so re-sorting yields removes and inserts
rather than moves; fine for the DOM. Reactive lists are react nodes
underneath, so the lifetime rule of §5 applies unchanged. `RMap` (keyed,
`Add`/`Del` patches) exists for map-shaped stores; not needed for the
screens we have.

## 7. Mental model checklist

- State → signal. Happening → event. Never store state in an event.
- Derive, don't set. If you feel the need to call a setter from inside a
  reaction, express it as `S.map`/`S.hold`/`S.sample` instead.
- Setters only from the outside: DOM callbacks, promise resolutions, plugin
  callbacks, timers.
- Several setters at once → one `Step`.
- Signals of closures or JS objects → `~eq:( == )`.
- Every binding is released on screen teardown with a strong stop. On
  js_of_ocaml, forgetting this leaks; it never silently stops.
- Read `S.value` only outside propagation, and rarely.

## 8. Further reading

- `react.mli` in the package: the semantics section is short and precise.
- ReactiveData (`RList`) for incremental lists:
  https://github.com/ocsigen/reactiveData
- Brr `El`, `At`, `Ev` modules: https://erratique.ch/software/brr/doc/
