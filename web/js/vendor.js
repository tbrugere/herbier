// esbuild entry (web/dune → dist/vendor.js). Exposes the Capacitor plugins on
// globalThis.herbier, where the OCaml bindings in app/bindings/ read them,
// with the MapLibre facade (map.js). Importing MapLibre's CSS makes esbuild
// emit dist/vendor.css next to vendor.js.
import { CapacitorSQLite, SQLiteConnection } from '@capacitor-community/sqlite';
import { Capacitor, CapacitorHttp, SystemBars, registerPlugin } from '@capacitor/core';
import { Filesystem } from '@capacitor/filesystem';
import { Preferences } from '@capacitor/preferences';
import { App } from '@capacitor/app';
import { BackgroundRunner } from '@capacitor/background-runner';
import { Camera } from '@capacitor/camera';
import { Geolocation } from '@capacitor/geolocation';
import { Network } from '@capacitor/network';
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
  network: Network,
  shareTarget: CapacitorShareTarget,
  http: CapacitorHttp,
  socialLogin: SocialLogin,
  // Herbier's own plugin (android/…/GoogleAuthorizationPlugin.java): absent
  // in a browser, so that the binding reports it Unavailable.
  googleAuthorization: Capacitor.isNativePlatform()
    ? registerPlugin('GoogleAuthorization')
    : undefined,
  // Herbier's own plugin (android/…/UploaderPlugin.java, WorkManager): absent
  // in a browser, so that the binding reports it Unavailable.
  uploader: Capacitor.isNativePlatform() ? registerPlugin('Uploader') : undefined,
  // Capacitor's core plugin (system-bar icon style): its web implementation
  // rejects every call, so a browser gets none and the binding reports it
  // Unavailable.
  systemBars: Capacitor.isNativePlatform() ? SystemBars : undefined,
  // Herbier's own plugin (android/…/ForegroundRunPlugin.java, a dataSync
  // foreground service): absent in a browser, so that the binding reports it
  // Unavailable.
  foregroundRun: Capacitor.isNativePlatform()
    ? registerPlugin('ForegroundRun')
    : undefined,
  // Herbier's own plugin (android/…/VolumeKeyPlugin.java, volume down as 4d's
  // shutter): absent in a browser, so that the binding reports it
  // Unavailable.
  volumeKey: Capacitor.isNativePlatform() ? registerPlugin('VolumeKey') : undefined,
  exifr,
  map,
};
