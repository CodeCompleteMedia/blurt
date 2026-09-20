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
 * Every latin .woff2 the build emits, minus the ones listed in `skip`.
 *
 * Bungee Inline is skipped deliberately. It is 20KB and it sets one word — the
 * wordmark — so preloading it would put a fifth of the critical path behind a
 * single logo. Its fallback is Bungee, which IS preloaded, so the worst case is
 * that word painting solid for a frame before it goes inline: the same family,
 * the same metrics, on six letters. That is the trade already made for extended
 * latin, where 19KB for a handful of accented glyphs was judged not worth every
 * phone paying on every load — see "Decisions worth revisiting" in the README.
 *
 * Anything new matching `latin*.woff2` is preloaded automatically, which is the
 * right default: opting out should be the decision that needs a reason.
 */
function preloadFonts(match = /latin[^/]*\.woff2$/, skip = [/bungee-inline/]) {
  return {
    name: 'blurt-preload-fonts',
    apply: 'build',
    enforce: 'post',
    generateBundle(_options, bundle) {
      const html = bundle['index.html']
      const fonts = Object.keys(bundle).filter(
        (name) => match.test(name) && !skip.some((re) => re.test(name)),
      )
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
