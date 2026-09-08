// Build de assets. Espeja innk_r5: esbuild directo (no jsbundling-rails), un
// `build()` por bucket, salida a app/assets/builds/ que Sprockets sirve.
//
// Dos buckets:
//   1. packs/*  -> una isla Vue por archivo. El glob las toma automáticamente:
//                  agregar app/javascript/packs/foo.js alcanza, no hay registro.
//   2. application.js / application.scss -> el chrome compartido.
const esBuild = require('esbuild');
const vuePlugin = require('esbuild-plugin-vue-next');

const sourcemap = process.env.NODE_ENV !== 'production';

const vueFlags = {
  'process.env.NODE_ENV': JSON.stringify('production'),
  // OJO: en 'false' Vue descarta data/computed/methods de los componentes que
  // usan Options API — y lo hace EN SILENCIO. El síntoma es un
  // "Cannot read properties of undefined (reading 'length')" al renderizar,
  // porque el template ve props y estado sin inicializar. Las islas de este
  // repo usan Options API (igual que innk_r5), así que va en 'true'.
  __VUE_OPTIONS_API__: 'true',
  __VUE_PROD_DEVTOOLS__: 'false',
  __VUE_PROD_HYDRATION_MISMATCH_DETAILS__: 'false'
};

esBuild.build({
  entryPoints: ['./app/javascript/packs/*.*'],
  bundle: true,
  minify: true,
  sourcemap,
  logLevel: 'info',
  outdir: 'app/assets/builds/packs',
  plugins: [vuePlugin()],
  define: vueFlags
});

esBuild.build({
  entryPoints: ['./app/javascript/application.js'],
  bundle: true,
  minify: true,
  sourcemap,
  logLevel: 'info',
  outfile: 'app/assets/builds/application-build.js',
  define: { 'process.env.NODE_ENV': JSON.stringify('production') }
});
