<script>
  // The phone. It never shows the question text, never learns the correct
  // answer, and never reports how long anything took — it sends a seat token
  // and a choice, and waits to be told what the room is doing.
  import AnswerTile from '../components/AnswerTile.svelte'
  import Leaderboard from '../components/Leaderboard.svelte'
  import { SHAPES } from '../lib/answers.js'
  import { fetchGame, fetchPlayers, submitAnswer, watchGame } from '../lib/api.js'
  import { ordinal } from '../lib/ordinal.js'
  import { clearSeat, readSeat } from '../lib/session.js'

  let seat = $state(null)
  let game = $state(null)
  let gameId = $state(null)
  let players = $state([])
  let picked = $state(null)
  let answeredIndex = $state(null)
  let busy = $state(false)
  let problem = $state('')
  let booting = $state(true)

  let me = $derived(players.find((player) => player.id === seat?.playerId) ?? null)
  let open = $derived(game?.phase === 'question_open')
  let locked = $derived(picked != null && answeredIndex === game?.question_index)

  async function boot() {
    const saved = readSeat()
    if (!saved?.code) {
      window.location.assign('/')
      return
    }
    seat = saved
    try {
      game = await fetchGame(saved.code)
      if (!game) {
        clearSeat()
        window.location.assign('/')
        return
      }
      gameId = game.id
      players = await fetchPlayers(gameId)
    } catch (error) {
      problem = error.message
    } finally {
      booting = false
    }
  }

  async function pick(choice) {
    if (!open || locked || busy) return
    busy = true
    problem = ''
    // Show it locked immediately — a teenager who sees no response taps again.
    picked = choice
    answeredIndex = game.question_index
    try {
      await submitAnswer(seat.playerToken, choice)
    } catch (error) {
      problem = error.message
      picked = null
      answeredIndex = null
    } finally {
      busy = false
    }
  }

  function leave() {
    clearSeat()
    window.location.assign('/')
  }

  $effect(() => {
    boot()
  })

  // Depends only on ids that never change while the game runs. Reading
  // `game.id` here instead would make this effect its own dependency: each
  // update would tear the subscription down and rebuild it.
  $effect(() => {
    if (!gameId || !seat?.code) return
    const watch = watchGame({
      code: seat.code,
      gameId,
      onGame: (row) => (game = row),
      onPlayers: (rows) => (players = rows),
    })
    return watch.stop
  })

  // A new question clears the last answer. Keyed on the index rather than the
  // phase so a re-render mid-question never unlocks a submitted answer.
  $effect(() => {
    const index = game?.question_index
    if (index != null && index !== answeredIndex) picked = null
  })
</script>

<main>
  {#if booting}
    <div class="centred"><p class="muted">Finding your seat…</p></div>
  {:else if problem}
    <div class="centred">
      <p class="muted">{problem}</p>
      <button class="ghost" onclick={leave}>Leave</button>
    </div>
  {:else if game?.phase === 'lobby'}
    <div class="centred">
      <p class="eyebrow">You're in</p>
      <h1>{seat.name}</h1>
      <p class="muted">Look up at the board.</p>
    </div>
  {:else if open && !locked}
    <header><span class="eyebrow">Look up at the board</span></header>
    <div class="pad">
      {#each SHAPES as shape, i}
        <AnswerTile {shape} showText={false} onclick={() => pick(i)} disabled={busy} />
      {/each}
    </div>
  {:else if open || game?.phase === 'locked'}
    <div class="centred">
      <h1 class="accent">Locked in</h1>
      {#if picked != null}<p class="muted">{SHAPES[picked].label}</p>{/if}
    </div>
  {:else if game?.phase === 'results'}
    <div class="centred">
      <p class="eyebrow">Your score</p>
      <h1>{me ? me.score.toLocaleString() : '—'}</h1>
      <p class="muted">{me ? `${ordinal(me.rank)} of ${players.length}` : ''}</p>
    </div>
  {:else if game?.phase === 'final'}
    <div class="final">
      <p class="eyebrow">Final</p>
      <h1>{me ? ordinal(me.rank) : '—'}</h1>
      <Leaderboard standings={players} limit={3} />
      <button class="ghost" onclick={leave}>Leave</button>
    </div>
  {:else}
    <div class="centred"><p class="muted">Waiting…</p></div>
  {/if}
</main>

<style>
  main {
    display: grid;
    grid-template-rows: auto 1fr;
    gap: 14px;
    height: 100%;
    padding: 16px 16px calc(16px + env(safe-area-inset-bottom));
  }

  header {
    text-align: center;
  }

  .centred,
  .final {
    grid-row: 1 / -1;
    display: grid;
    align-content: center;
    justify-items: center;
    gap: 10px;
    text-align: center;
  }

  .final {
    gap: 18px;
    align-content: center;
    width: 100%;
  }

  .final :global(.board) {
    width: 100%;
  }

  h1 {
    font-size: clamp(48px, 18vw, 80px);
  }

  .accent {
    color: var(--accent);
  }

  .muted {
    margin: 0;
    color: var(--muted);
  }

  .pad {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 12px;
  }

  .pad :global(.tile) {
    justify-content: center;
    height: 100%;
    min-height: 0;
  }

  .ghost {
    margin-top: 20px;
    padding: 10px 18px;
    border: 1px solid var(--line);
    border-radius: 999px;
    color: var(--muted);
    font-size: 13px;
  }
</style>
