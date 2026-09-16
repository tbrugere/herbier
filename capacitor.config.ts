import type { CapacitorConfig } from '@capacitor/cli';

// webDir is a symlink into dune's build directory; run `dune build @web`
// before `npx cap sync`.
const config: CapacitorConfig = {
  appId: 're.bruge.herbier',
  appName: 'Herbier',
  webDir: 'web/dist',
  android: {
    allowMixedContent: false,
  },
  plugins: {
    CapacitorSQLite: {
      androidIsEncryption: false,
    },
  },
};

export default config;
