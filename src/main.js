import { mount } from 'svelte'
import './app.css'
import App from './App.svelte'

const target = document.getElementById('app')

// / arrives pre-rendered (scripts/prerender.mjs). Load the landing page's code
// before clearing that HTML, so the swap to the live page happens in one go
// instead of showing a blank screen while the chunk downloads.
if (target.hasAttribute('data-prerendered')) {
  await import('./views/Landing.svelte')
  target.replaceChildren()
  target.removeAttribute('data-prerendered')
  for (const node of document.head.querySelectorAll('[data-prerendered]')) node.remove()
}

const app = mount(App, { target })

export default app
