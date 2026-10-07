// Runs after the client and SSR builds (see `npm run build`).
//
// dist/index.html becomes the pre-rendered landing page, served only at /.
// Every other route gets dist/app.html, the untouched app shell, through the
// rewrite in vercel.json — so /host or /play never flashes the landing page.
//
// The landing page's CSS is linked in the head, so the HTML is styled from the
// first paint; its script chunk is preloaded, so the app takes over quickly.
// Svelte scopes CSS by hashing it, and both builds compile the same files, so
// the class names in this HTML match the stylesheet the client build emitted.
import { readFileSync, writeFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

const dist = new URL('../dist/', import.meta.url)
const shell = readFileSync(new URL('index.html', dist), 'utf8')
const manifest = JSON.parse(readFileSync(new URL('.vite/manifest.json', dist), 'utf8'))

const entry = manifest['src/views/Landing.svelte']
if (!entry) throw new Error('prerender: no Landing chunk in the client manifest')

// The landing chunk, every chunk it imports, and all of their CSS.
const chunks = new Set()
const css = new Set()
const walk = (key) => {
  const chunk = manifest[key]
  if (!chunk || chunks.has(chunk.file)) return
  chunks.add(chunk.file)
  for (const file of chunk.css ?? []) css.add(file)
  for (const next of chunk.imports ?? []) walk(next)
}
walk('src/views/Landing.svelte')

const ssr = await import(pathToFileURL(new URL('../dist-ssr/prerender.js', import.meta.url).pathname).href)
const { head, body } = ssr.renderLanding()

// Marked so the client can drop them before it mounts and writes its own,
// rather than leaving a second <title> behind.
const markedHead = head.replace(/<(title|meta|link)\b/g, '<$1 data-prerendered')

const links = [
  ...[...css].map((f) => `<link rel="stylesheet" href="/${f}">`),
  ...[...chunks].map((f) => `<link rel="modulepreload" href="/${f}">`),
].join('\n    ')

if (!shell.includes('<div id="app"></div>')) throw new Error('prerender: no empty #app in index.html')

const page = shell
  .replace('<title>Blurt</title>', '')
  .replace('</head>', `  ${markedHead}\n    ${links}\n  </head>`)
  .replace('<div id="app"></div>', `<div id="app" data-prerendered>${body}</div>`)

writeFileSync(new URL('app.html', dist), shell)
writeFileSync(new URL('index.html', dist), page)
console.log(`prerendered / (${Math.round(body.length / 1024)} KB of HTML, ${css.size} stylesheets)`)
