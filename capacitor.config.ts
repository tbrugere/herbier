import type { CapacitorConfig } from '@capacitor/cli';

// www/ is a symlink into dune's build directory; run `dune build @web`
// before `npx cap sync`.
const config: CapacitorConfig = {
  appId: 're.bruge.herbier',
  appName: 'Herbier',
  webDir: 'www',
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
