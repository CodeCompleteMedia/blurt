// Light or dark. The teacher chooses; every screen in their room follows.
//
// The choice is remembered in the teacher's browser, and /host copies it onto
// the room (`games.theme`) so the wall and the phones — other devices, which
// cannot see this browser's storage — read it alongside everything else about
// the room. Screens that are not in a room yet (the join page, an idle display)
// have no teacher to follow, so they show the default.
//
// Light is the default everywhere: dark is what someone chooses. index.html
// paints light before any script runs, so no screen opens dark and switches.

const KEY = 'blurt-theme'

function stored() {
  try {
    return localStorage.getItem(KEY) === 'dark' ? 'dark' : 'light'
  } catch {
    // Private windows and locked-down school profiles can refuse storage.
    return 'light'
  }
}

export const theme = $state({ mode: stored() })

/** Light the page as `mode` without remembering it — what a wall or phone does. */
export function showTheme(mode) {
  const root = document.documentElement
  root.dataset.theme = mode === 'dark' ? 'dark' : 'light'
  // The browser chrome on phones and tablets follows this, so it has to match
  // the page rather than stay studio-dark above a light one.
  const stage = getComputedStyle(root).getPropertyValue('--stage').trim()
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', stage)
}

/** The teacher's own screens, in the teacher's own choice. */
export function applyTheme() {
  showTheme(theme.mode)
}

export function setTheme(mode) {
  theme.mode = mode
  try {
    localStorage.setItem(KEY, mode)
  } catch {
    // Still switches for this visit; it just will not be remembered.
  }
  applyTheme()
}
