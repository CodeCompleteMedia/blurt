// Every sound the wall makes, synthesised.
//
// No audio files: nothing to license, nothing for the projector's laptop to fetch
// over school wifi at the moment it matters, and the whole kit is a few hundred
// bytes of arithmetic. Only the wall ever calls this. Thirty phones chirping in a
// classroom is a different product.
//
// Browsers will not let a page make noise until someone has touched it, and the
// wall is usually opened by the host screen rather than clicked on. So sound
// starts locked, the wall shows a speaker to click, and `unlock` is what that
// click does. Muting is remembered; a teacher who silences it once stays silenced.

const KEY = 'blurt.muted'

let ctx = null
let muted = false
try {
  muted = localStorage.getItem(KEY) === '1'
} catch {
  // Private browsing: sound simply starts unmuted each time.
}

export const isMuted = () => muted
export const isUnlocked = () => ctx?.state === 'running'

export function setMuted(value) {
  muted = value
  try {
    localStorage.setItem(KEY, value ? '1' : '0')
  } catch {
    // As above.
  }
}

/** Call from a click or a keypress; anywhere else the browser refuses. */
export async function unlock() {
  try {
    ctx ??= new (window.AudioContext || window.webkitAudioContext)()
    if (ctx.state !== 'running') await ctx.resume()
  } catch {
    ctx = null
  }
  return isUnlocked()
}

// One enveloped oscillator. Everything below is arrangements of this.
function note(freq, at, length, { type = 'sine', gain = 0.16, slideTo = null } = {}) {
  if (!ctx || muted || ctx.state !== 'running') return
  const t = ctx.currentTime + at
  const osc = ctx.createOscillator()
  const amp = ctx.createGain()
  osc.type = type
  osc.frequency.setValueAtTime(freq, t)
  if (slideTo) osc.frequency.exponentialRampToValueAtTime(slideTo, t + length)
  amp.gain.setValueAtTime(0.0001, t)
  amp.gain.exponentialRampToValueAtTime(gain, t + 0.012)
  amp.gain.exponentialRampToValueAtTime(0.0001, t + length)
  osc.connect(amp).connect(ctx.destination)
  osc.start(t)
  osc.stop(t + length + 0.02)
}

// C major, because nothing about a quiz should sound ominous.
const C5 = 523.25, E5 = 659.25, G5 = 783.99, C6 = 1046.5, E6 = 1318.5, G4 = 392, A4 = 440
const D5 = 587.33, A5 = 880

export const sounds = {
  /** The last few seconds of a clock. Higher as it runs out. */
  tick(secondsLeft) {
    note(secondsLeft <= 2 ? 1320 : 990, 0, 0.06, { type: 'square', gain: 0.05 })
  },

  /**
   * A phone arriving in the lobby.
   *
   * This one fires more than every other sound here put together — thirty of
   * them inside a minute at the start of a lesson — so it is quieter than
   * everything except the clock tick, and it climbs a pentatonic ladder as the
   * room fills. Thirty of the same blip is a smoke alarm; thirty rising ones sound
   * like something filling up, and pentatonic means any two that land on top of
   * each other still agree.
   */
  join(nth = 0, at = 0) {
    const ladder = [C5, D5, E5, G5, A5, C6]
    const f = ladder[nth % ladder.length]
    note(f, at, 0.09, { type: 'triangle', gain: 0.07, slideTo: f * 1.5 })
  },

  /** A question arriving. */
  open() {
    note(G4, 0, 0.09, { type: 'triangle' })
    note(C5, 0.07, 0.14, { type: 'triangle' })
  },

  /** Someone has claimed the floor — the moment the mechanic exists for. */
  sting() {
    ;[C5, E5, G5].forEach((f, i) => note(f, i * 0.055, 0.1, { type: 'sawtooth', gain: 0.09 }))
    note(C6, 0.17, 0.5, { type: 'sawtooth', gain: 0.11 })
    note(C5 / 2, 0.17, 0.5, { type: 'triangle', gain: 0.14 })
  },

  /** The clock ran out. */
  time() {
    note(A4, 0, 0.16, { type: 'triangle' })
    note(A4 * 0.75, 0.13, 0.3, { type: 'triangle' })
  },

  /** The answer going up. */
  reveal() {
    ;[C5, E5, G5, C6].forEach((f, i) => note(f, i * 0.07, 0.32, { type: 'triangle', gain: 0.12 }))
  },

  /** Third and second place stepping up. */
  step(place) {
    note(place === 3 ? E5 : G5, 0, 0.25, { type: 'triangle', gain: 0.13 })
  },

  /** First place. */
  fanfare() {
    const run = [C5, C5, G5, E5, G5, C6]
    const at = [0, 0.12, 0.24, 0.42, 0.54, 0.7]
    run.forEach((f, i) => note(f, at[i], i === 5 ? 0.9 : 0.16, { type: 'sawtooth', gain: 0.1 }))
    note(E6, 0.7, 0.9, { type: 'triangle', gain: 0.08 })
    note(C5 / 2, 0.7, 0.9, { type: 'triangle', gain: 0.14 })
  },
}
