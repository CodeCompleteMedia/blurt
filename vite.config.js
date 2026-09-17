import { svelte } from '@sveltejs/vite-plugin-svelte'
import { defineConfig } from 'vite'

/**
 * Preload the fonts the app actually uses.
 *
 * Without this the browser only discovers a font after it has fetched and parsed
 * the stylesheet, which is late enough to paint one frame in the fallback face
 * and then swap — the flicker. A preload hint in the HTML starts the download at
 * parse time instead, in parallel with the CSS, so the face is normally ready
 * before the first paint.
 *
 * The hints cannot be hand-written into index.html because Vite hashes the font
 * filenames at build time, so they are injected from the real bundle.
 *
 * The pattern matches every latin .woff2 the build emits, which today is exactly
 * the two faces src/app.css declares. If extended latin is ever added back — see
 * "Decisions worth revisiting" in the README — it will be preloaded automatically
 * unless this pattern is narrowed, and preloading 19KB for a handful of glyphs is
 * a separate decision from bundling it.
 */
function preloadFonts(match = /latin[^/]*\.woff2$/) {
  return {
    name: 'blurt-preload-fonts',
    apply: 'build',
    enforce: 'post',
    generateBundle(_options, bundle) {
      const html = bundle['index.html']
      const fonts = Object.keys(bundle).filter((name) => match.test(name))
      if (!html || fonts.length === 0) return

      const links = fonts
        .map((f) => `<link rel="preload" href="/${f}" as="font" type="font/woff2" crossorigin>`)
        .join('\n    ')

      html.source = String(html.source).replace('</head>', `  ${links}\n  </head>`)
    },
  }
}

// https://vite.dev/config/
export default defineConfig({
  plugins: [svelte(), preloadFonts()],
})
