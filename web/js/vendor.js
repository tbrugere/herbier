// esbuild entry (web/dune → dist/vendor.js). Exposes the Capacitor plugins on
// globalThis.herbier, where the OCaml bindings in app/bindings/ read them,
// with the MapLibre facade (map.js). Importing MapLibre's CSS makes esbuild
// emit dist/vendor.css next to vendor.js.
import { CapacitorSQLite, SQLiteConnection } from '@capacitor-community/sqlite';
import { Capacitor, CapacitorHttp, registerPlugin } from '@capacitor/core';
import { Filesystem } from '@capacitor/filesystem';
import { Preferences } from '@capacitor/preferences';
import { App } from '@capacitor/app';
import { BackgroundRunner } from '@capacitor/background-runner';
import { Camera } from '@capacitor/camera';
import { Geolocation } from '@capacitor/geolocation';
import { SocialLogin } from '@capgo/capacitor-social-login';
import { CapacitorShareTarget } from '@capgo/capacitor-share-target';
import exifr from 'exifr';
import 'maplibre-gl/dist/maplibre-gl.css';
import * as map from './map.js';

globalThis.herbier = {
  sqlite: new SQLiteConnection(CapacitorSQLite),
  filesystem: Filesystem,
  preferences: Preferences,
  app: App,
  // Its web implementation throws on every call: absent there, so that the
  // binding reports it Unavailable (no keep-alive job in a browser).
  backgroundRunner: Capacitor.isNativePlatform() ? BackgroundRunner : undefined,
  camera: Camera,
  geolocation: Geolocation,
  shareTarget: CapacitorShareTarget,
  http: CapacitorHttp,
  socialLogin: SocialLogin,
  // Herbier's own plugin (android/…/GoogleAuthorizationPlugin.java): absent
  // in a browser, so that the binding reports it Unavailable.
  googleAuthorization: Capacitor.isNativePlatform()
    ? registerPlugin('GoogleAuthorization')
    : undefined,
  exifr,
  map,
};
