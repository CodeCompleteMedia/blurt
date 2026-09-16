// Three surfaces, three paths. No router library: the app never navigates after
// load, because a phone stays on /play and a projector stays on /host all lesson.

const ROUTES = {
  '/': 'join',
  '/play': 'play',
  '/host': 'host',
}

export function viewFor(pathname = window.location.pathname) {
  const path = pathname.replace(/\/+$/, '') || '/'
  return ROUTES[path] ?? 'join'
}
