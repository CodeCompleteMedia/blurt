// How things move — and that some people would rather they did not.
//
// CSS animations are already switched off by the reduced-motion rule in app.css.
// Svelte's transitions run in JavaScript and never see that rule, so they ask
// here. Under reduced motion everything still *happens* — the podium still
// reveals third, second, first — it just arrives instead of travelling.

import { cubicOut } from 'svelte/easing'

export const calm =
  typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches

export const ms = (n) => (calm ? 0 : n)

/** A name or a number landing: big, then settling. For moments, not for lists. */
export function slam(node, { delay = 0, duration = 420, from = 1.5 } = {}) {
  return {
    delay: ms(delay),
    duration: ms(duration),
    easing: cubicOut,
    css: (t) => `opacity: ${Math.min(1, t * 2)}; transform: scale(${from - (from - 1) * t});`,
  }
}

/** Rising into place. The default way for a row or a tile to arrive. */
export function rise(node, { delay = 0, duration = 360, y = 18 } = {}) {
  return {
    delay: ms(delay),
    duration: ms(duration),
    easing: cubicOut,
    css: (t) => `opacity: ${t}; transform: translateY(${(1 - t) * y}px);`,
  }
}
