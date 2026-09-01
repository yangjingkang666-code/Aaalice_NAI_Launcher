import { build } from 'esbuild'

await build({
  entryPoints: {
    index: 'src/index.ts',
    client: 'src/client.ts',
  },
  outdir: 'lib',
  bundle: true,
  format: 'esm',
  platform: 'node',
  target: 'node20',
  external: ['@deepseek-ai/*'],
  sourcemap: true,
  logLevel: 'info',
})
