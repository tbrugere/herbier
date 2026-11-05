// esbuild entry (web/dune → dist/vendor.js). Exposes the Capacitor plugins on
// globalThis.herbier, where the OCaml bindings in app/bindings/ read them.
import { CapacitorSQLite, SQLiteConnection } from '@capacitor-community/sqlite';
import { Filesystem } from '@capacitor/filesystem';
import { Preferences } from '@capacitor/preferences';
import { App } from '@capacitor/app';

globalThis.herbier = {
  sqlite: new SQLiteConnection(CapacitorSQLite),
  filesystem: Filesystem,
  preferences: Preferences,
  app: App,
};
