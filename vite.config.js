import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import { defineConfig, loadEnv } from 'vite'

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

/**
 * Serve api/ during `npm run dev`.
 *
 * In production these files are Vercel Functions. Locally nothing runs them, so
 * Checkout could only be tried on a deployment. This hands each /api request to
 * the same file with the same Web-standard Request, and gives the handlers the
 * server-side variables from .env.local, which Vite otherwise keeps to itself.
 */
function devApi() {
  return {
    name: 'blurt-dev-api',
    apply: 'serve',
    configureServer(server) {
      for (const [name, value] of Object.entries(loadEnv('development', process.cwd(), ''))) {
        process.env[name] ??= value
      }
      server.middlewares.use(async (req, res, next) => {
        const path = new URL(req.url, 'http://localhost').pathname
        // Lowercase names only, and nothing under _lib: those are not routes.
        if (!/^\/api(\/[a-z][a-z-]*)+$/.test(path)) return next()
        const file = fileURLToPath(new URL(`.${path}.js`, import.meta.url))
        try {
          const handler = existsSync(file) && (await server.ssrLoadModule(file))[req.method]
          if (!handler) {
            res.statusCode = 404
            return res.end()
          }
          const chunks = []
          for await (const chunk of req) chunks.push(chunk)
          const headers = Object.entries(req.headers).filter(([, value]) => typeof value === 'string')
          const response = await handler(
            new Request(`http://${req.headers.host}${req.url}`, {
              method: req.method,
              headers,
              body: ['GET', 'HEAD'].includes(req.method) ? undefined : Buffer.concat(chunks),
            }),
          )
          res.statusCode = response.status
          response.headers.forEach((value, name) => res.setHeader(name, value))
          res.end(Buffer.from(await response.arrayBuffer()))
        } catch (error) {
          console.error(error)
          res.statusCode = 500
          res.end()
        }
      })
    },
  }
}

// https://vite.dev/config/
export default defineConfig({
  plugins: [svelte(), preloadFonts(), devApi()],
  // The prerender step reads this to find the landing page's chunk and CSS.
  build: { manifest: true },
})
