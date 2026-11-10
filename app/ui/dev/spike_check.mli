(** Dev-only page for the UI spike's exit criterion, reached with the URL
    fragment [#dev/spike] over the app's [herbier] database (seed it with
    [#dev/seed] first). Enters and leaves the Collection screen (4a) fifty times
    per round, four rounds, reading the binding count and the JS heap after
    each; then enters and leaves it fifty more times keeping the screens left,
    filters on the first tag, and checks that a screen kept bound (the control)
    changes while none of those left does.

    The result is in [#result]: [data-ok] is [true] when the binding count is
    back to its baseline after every round and no left screen changed. A
    precondition that does not hold (an empty grid, no tag, a filter that does
    not move the control, an exception) is a failure with its reason. The heap
    is reported, not judged: [data-heaps] (bytes, before the first round then
    after each), [data-gc] ([true] when each reading followed a forced GC, i.e.
    Chromium started with [--js-flags=--expose-gc]), and [data-round] while it
    runs. Also [data-live-before], [data-live-rounds], [data-live-after],
    [data-control-ms], [data-stale] (how many left screens changed). A last line
    [done] marks the end, as on the other dev pages.

    In the Android WebView, [performance.memory] is coarse and cached (see
    {!Herbier_bindings.Dev_hook.heap_used}): read the heap with
    [scripts/webview.mjs heap] when [data-round] reaches each value instead. *)

val el : (Herbier_store.Db.t, string) result -> Brr.El.t
