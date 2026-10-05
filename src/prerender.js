// Server-side entry, used only at build time: renders the landing page to HTML
// so / arrives as a real page (readable by search engines and link previews,
// and painted before any script runs) rather than an empty <div>.
import { render } from 'svelte/server'
import Landing from './views/Landing.svelte'

export function renderLanding() {
  return render(Landing)
}
