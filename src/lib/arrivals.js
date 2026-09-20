// Who just walked in.
//
// Import-free on purpose: this is the logic the lobby chirp hangs on, it has
// three ways to be quietly wrong, and a module that imports the Supabase client
// cannot be unit tested. See tests/arrivals.test.js.
//
// The three ways:
//   1. A refreshed projector must not announce a lobby that filled up five
//      minutes ago, so the first roster sets a baseline and says nothing.
//   2. Counting is not enough — one student removed and another joining between
//      two polls leaves the length identical and is still an arrival.
//   3. A poll can deliver a clump. Every arrival counts towards the ladder, but
//      only the first few make a sound.

export const BURST = 3

/**
 * @param {Set<string>|null} known ids the wall has already seen, or null on the first roster
 * @param {{id: string}[]} roster the roster as it stands now
 * @returns {{known: Set<string>, arrived: number, chirps: number, baseline: boolean}}
 */
export function arrivals(known, roster) {
  const ids = new Set((roster ?? []).map((p) => p.id))

  if (known === null) return { known: ids, arrived: 0, chirps: 0, baseline: true }

  let arrived = 0
  for (const id of ids) if (!known.has(id)) arrived += 1

  return { known: ids, arrived, chirps: Math.min(arrived, BURST), baseline: false }
}
