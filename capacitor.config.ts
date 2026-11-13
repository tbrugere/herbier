import type { CapacitorConfig } from '@capacitor/cli';

// dune builds the web shell there; run `dune build @web`
// before `npx cap sync`.
const config: CapacitorConfig = {
  appId: 're.bruge.herbier',
  appName: 'Herbier',
  webDir: '_build/default/web/dist',
  android: {
    allowMixedContent: false,
  },
  plugins: {
    // Only CapacitorHttp's plugin methods are called (bindings/cap_http.ml):
    // the global fetch patch stays off.
    CapacitorHttp: {
      enabled: false,
    },
    CapacitorSQLite: {
      androidIsEncryption: false,
    },
    // The keep-alive job (architecture §4): web/runner/keepalive.js, copied
    // to dist/runner/ by scripts/build-web.sh. label and event are
    // Keepalive.Wire.label and event_to_string Run; interval (minutes) is
    // Keepalive.Wire.interval_minutes: keep them equal. WorkManager runs it
    // that long after the app goes to the background, then periodically,
    // when a network is up.
    BackgroundRunner: {
      label: 're.bruge.herbier.keepalive',
      src: 'runner/keepalive.js',
      event: 'keepAlive',
      repeat: true,
      interval: 720,
      autoStart: true,
    },
  },
};

export default config;
