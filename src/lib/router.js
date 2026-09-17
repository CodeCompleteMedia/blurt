// Five surfaces, the fifth being the teacher's quiz editor at /edit. The app never navigates after load — a phone stays on /play and
// a wall stays on /present all lesson — so there is no router library here.
//
// /present carries the room code because it holds no credential: it is a screen,
// not a session. The host token lives on /host instead, which is the machine the
// room cannot see.

const CODE = '[A-Za-z0-9]{4,8}'

export function routeFor(pathname = window.location.pathname) {
  const path = pathname.replace(/\/+$/, '') || '/'

  if (path === '/play') return { view: 'play' }
  if (path === '/host') return { view: 'host' }

  const edit = path.match(/^\/edit(?:\/([0-9a-f-]{36}))?$/i)
  if (edit) return { view: 'edit', quizId: edit[1]?.toLowerCase() ?? null }

  const present = path.match(new RegExp(`^/present(?:/(${CODE}))?$`))
  if (present) return { view: 'present', code: present[1]?.toUpperCase() ?? null }

  return { view: 'join' }
}
