// Seven surfaces. Three are the teacher's: the room, the quiz editor, and the
// reports at /games. The app never navigates after load — a phone stays on /play and
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

  const games = path.match(/^\/games(?:\/([0-9a-f-]{36}))?$/i)
  if (games) return { view: 'games', gameId: games[1]?.toLowerCase() ?? null }

  const edit = path.match(/^\/edit(?:\/([0-9a-f-]{36}))?$/i)
  if (edit) return { view: 'edit', quizId: edit[1]?.toLowerCase() ?? null }

  // A display is a uuid, not a room code: it is a screen a teacher paired once,
  // and the room it shows is pushed to it rather than typed.
  const wall = path.match(/^\/wall(?:\/([0-9a-f-]{36}))?$/i)
  if (wall) return { view: 'wall', wallId: wall[1]?.toLowerCase() ?? null }

  // What a QR on the wall points at. The code is in the path so a student who
  // scans it never types one — they land on the name field with the room
  // already decided.
  const scanned = path.match(new RegExp(`^/j/(${CODE})$`))
  if (scanned) return { view: 'join', code: scanned[1].toUpperCase() }

  const present = path.match(new RegExp(`^/present(?:/(${CODE}))?$`))
  if (present) return { view: 'present', code: present[1]?.toUpperCase() ?? null }

  return { view: 'join' }
}
