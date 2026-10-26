# Web and shell review

Sass, markup produced from OCaml, the JS facade, Capacitor and the Android project.
`docs/design_handoff_herbier/` is the source of truth for screens and tokens; `stack.md` "UI
components" and `layout.md` §3 to §4 say how they are built.

## Scope

`web/**`, `android/**`, `capacitor.config.ts`, `app/ui/**`.

## Checklist

- **Tokens.** Colours, type sizes, radii and spacing come from the custom properties in
  `web/sass/_tokens.sass` and nowhere else: a hex value or a pixel size in a screen's Sass, an
  inline style set from OCaml with a literal colour, a duplicated token in `ui/theme.ml` beyond
  reading `getComputedStyle`. The handoff token names (`paper`, `sand`, `moss`, `ochre`,
  `danger`, `ink`, `muted`) are the vocabulary.
- **Indented Sass syntax.** Files are `.sass`, not `.scss`; one partial per widget group, one
  file per screen under `sass/screens/` with the handoff id in its header; `@use`, not
  `@import`; mixins for repeated patterns instead of copied blocks.
- **Markup from OCaml.** Class names follow the handoff vocabulary (`.chip`, `.card`,
  `.sheet`); no `innerHTML`; no inline styles except the few signal-bound ones (`transform` on
  the sheet); accessible defaults: buttons are `<button>`, images have `alt`, the tab bar is
  navigation, touch targets around 44 px; text in French as the handoff writes it, no i18n
  layer.
- **CSS-only interactions preferred.** Scroll-snap, sticky, `<dialog>`, View Transitions where
  the handoff behaviour allows it; JS or OCaml driving an animation frame-by-frame is a
  finding unless the design needs it (the sheet drag).
- **Reactive bindings.** A screen creating bindings outside `Rb` (direct `El.set_children` in a
  signal callback), bindings not collected for release, an `RList` rebuilt from scratch on
  every change instead of patched.
- **Build.** `web/dune`'s `@web` rule still produces `dist/` with `app.css`, `vendor.js`,
  `app.js` and the static folders; `scripts/build-web.sh` changes mirrored in the rule's
  `deps`; `www` stays a symlink; new static assets copied by the script.
- **Capacitor.** `webDir` is `www`; plugins added to `package.json` also imported in
  `web/js/vendor.js` and bound in `app/bindings/`; `capacitor.config.ts` plugin options match
  the binding's assumptions (SQLite encryption off, filesystem directories).
- **Android.** Only the manifest, one plugin class and resources are hand-edited
  (`layout.md` §4); intent filters match `architecture.md` §7's host list; `android:exported`
  set explicitly on the activity receiving intents; no cleartext traffic outside debug; the
  app id stays `re.bruge.herbier`.
- **Offline and sun readability** (handoff 5f): contrast on `paper`, no colour-only state,
  loading and empty states present for lists that can be empty or slow.

## Output

Write `.review-report/web.md`:

```
# Web and shell review

## Findings
| Severity | Location | Issue | Suggestion |
| --- | --- | --- | --- |
| blocker/high/medium/low/nit | path:line | what's wrong | concrete fix |

## Questions for the author
- ...
```

Review only; no edits. Cite `file:line`. An empty table is fine.
