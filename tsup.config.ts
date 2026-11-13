import { cpSync } from 'node:fs';

import { defineConfig } from 'tsup';

export default defineConfig({
  // vps: only the real entry points (all of src/ as entries peaks at ~1.2 GB)
  entry: ['src/main.ts', 'src/index.ts'],
  outDir: 'dist',
  splitting: false,
  sourcemap: true,
  clean: true,
  minify: true,
  format: ['cjs'],
  onSuccess: async () => {
    cpSync('src/utils/translations', 'dist/translations', { recursive: true });
  },
  loader: {
    '.json': 'file',
    '.yml': 'file',
  },
});
