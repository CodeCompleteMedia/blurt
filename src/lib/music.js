// The bed under the wall.
//
// The only audio *file* in the project. Everything in sound.js is synthesised
// arithmetic for good reasons that still hold — but a music bed is not something
// you can synthesise without it grating, so this one is a real track, and it is
// the wall's alone. Thirty phones playing music in a classroom is a fire drill.
//
// Source: slimeyfox, "arcade 80s era" (Pixabay, id 481352), re-encoded from
// 256kbps to 128kbps — 2.6MB to 1.3MB, which the projector's laptop fetches once
// and then has cached. It is a background bed on classroom speakers; the extra
// bitrate bought nothing audible and cost half the download.
import track from '../assets/music/arcade-80s.mp3'

const KEY = 'blurt.music'

// Under the room, not over it. The track masters to -3dB, so this sits it well
// below a teacher's speaking voice.
const BED = 0.22
// Someone has the floor and is saying the answer out loud. That is the one
// moment the room has to hear a person, so the music gets out of the way.
const DUCKED = 0.05

let el = null
let on = true
try {
  on = localStorage.getItem(KEY) !== '0'
} catch {
  // Private browsing: music simply starts on, which is the default anyway.
}

export const isMusicOn = () => on

function element() {
  if (el) return el
  el = new Audio(track)
  el.loop = true
  el.volume = BED
  el.preload = 'auto'
  return el
}

/**
 * Start, or stop, according to what the wall currently wants.
 * Safe to call as often as you like; it only acts on a real change.
 *
 * `allowed` is the same gate the synth uses: a browser will not make noise
 * until the page has been touched, and muting silences the bed along with
 * everything else.
 */
export function syncMusic(allowed) {
  const should = allowed && on
  const audio = should ? element() : el
  if (!audio) return

  if (should && audio.paused) {
    // A rejected play() is not worth interrupting a lesson over — the teacher
    // still has a button, and the game does not depend on this.
    audio.play().catch(() => {})
  } else if (!should && !audio.paused) {
    audio.pause()
  }
}

export function setMusicOn(value, allowed = true) {
  on = value
  try {
    localStorage.setItem(KEY, value ? '1' : '0')
  } catch {
    // As above.
  }
  syncMusic(allowed)
}

/** Drop under a spoken answer, and come back up afterwards. */
export function duckMusic(down) {
  if (!el) return
  el.volume = down ? DUCKED : BED
}
