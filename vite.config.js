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
 * filenames at build time, so they are injected from the real bundle. Only the
 * latin subsets are hinted: the others are emitted by Fontsource's stylesheet but
 * no `unicode-range` in this app will ever request them, and preloading a file
 * nothing asks for is worse than not preloading at all.
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
