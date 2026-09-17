// What this browser remembers: a teacher's host token, or a student's seat.
// Keeping the seat is what will let a phone that locked mid-question come back
// to the same score in Phase 2.
//
// Private browsing and cleared site data both make localStorage throw, so every
// read and write is guarded — a student with storage blocked can still play,
// they just cannot come back.

const HOST_KEY = 'blurt.host'
const SETTINGS_KEY = 'blurt.settings'
const SEAT_KEY = 'blurt.seat'

function read(key) {
  try {
    const raw = localStorage.getItem(key)
    return raw ? JSON.parse(raw) : null
  } catch {
    return null
  }
}

function write(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value))
  } catch {
    // Not fatal: the game runs, it just will not survive a refresh.
  }
}

function clear(key) {
  try {
    localStorage.removeItem(key)
  } catch {
    // As above.
  }
}

export const readHost = () => read(HOST_KEY)
export const writeHost = (value) => write(HOST_KEY, value)
export const clearHost = () => clear(HOST_KEY)

/**
 * How this teacher likes a round to run. Kept in the browser rather than on a
 * game, so it survives into the next room — a preference you have to set again
 * every lesson is not a preference, it is a chore.
 */
export const DEFAULT_SETTINGS = {
  blurtEnabled: true,
  revealImmediately: true,
  autoNextSeconds: 0,
  recallSeconds: 8,
  allowLateJoin: true,
  blurtLockout: true,
  blurtPenalty: 0,
}

export const readSettings = () => ({ ...DEFAULT_SETTINGS, ...(read(SETTINGS_KEY) ?? {}) })
export const writeSettings = (value) => write(SETTINGS_KEY, value)

export const readSeat = () => read(SEAT_KEY)
export const writeSeat = (value) => write(SEAT_KEY, value)
export const clearSeat = () => clear(SEAT_KEY)
