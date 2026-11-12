// esbuild entry (web/dune → dist/vendor.js). Exposes the Capacitor plugins on
// globalThis.herbier, where the OCaml bindings in app/bindings/ read them,
// with the MapLibre facade (map.js). Importing MapLibre's CSS makes esbuild
// emit dist/vendor.css next to vendor.js.
import { CapacitorSQLite, SQLiteConnection } from '@capacitor-community/sqlite';
import { CapacitorHttp } from '@capacitor/core';
import { Filesystem } from '@capacitor/filesystem';
import { Preferences } from '@capacitor/preferences';
import { App } from '@capacitor/app';
import { Camera } from '@capacitor/camera';
import { Geolocation } from '@capacitor/geolocation';
import exifr from 'exifr';
import 'maplibre-gl/dist/maplibre-gl.css';
import * as map from './map.js';

globalThis.herbier = {
  sqlite: new SQLiteConnection(CapacitorSQLite),
  filesystem: Filesystem,
  preferences: Preferences,
  app: App,
  camera: Camera,
  geolocation: Geolocation,
  http: CapacitorHttp,
  exifr,
  map,
};
