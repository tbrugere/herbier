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
  },
};

export default config;
