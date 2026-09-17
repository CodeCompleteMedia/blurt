<script>
  // The phone. It never shows the question text, never learns the correct
  // answer, and never reports how long anything took.
  //
  // During recall it shows one button. Hitting it is a bet: right and it is
  // worth more than any tapped answer, wrong and this question is over for you.
  import AnswerTile from '../components/AnswerTile.svelte'
  import Leaderboard from '../components/Leaderboard.svelte'
  import { SHAPES } from '../lib/answers.js'
  import {
    blurt,
    fetchGame,
    fetchPlayers,
    myResult,
    mySeat,
    submitAnswer,
    submitTextAnswer,
    watchGame,
  } from '../lib/api.js'
  import { ordinal } from '../lib/ordinal.js'
  import { clearSeat, readSeat, writeSeat } from '../lib/session.js'

  let seat = $state(null)
  let game = $state(null)
  let gameId = $state(null)
  let players = $state([])
  let picked = $state(null)
  let answeredIndex = $state(null)
  let busy = $state(false)
  let missed = $state(false)
  let tooSlow = $state(false)
  let draft = $state('')
  let problem = $state('')
  let booting = $state(true)
  let result = $state(null)
  let resultKey = ''
  // What the server says about this seat. It outlives a refresh, which local
  // state does not — a phone that reloads mid-question must not be offered the
  // answer pad again for a question it has already answered.
  let standing = $state(null)
  let standingKey = ''

  // By id normally; by name for a seat written before ids were stored, so an
  // older phone shows a score rather than a dash.
  let me = $derived(
    players.find((player) => player.id === seat?.playerId) ??
      players.find((player) => player.name === seat?.name) ??
      null,
  )
  let phase = $derived(game?.phase ?? null)
  let locked = $derived(
    (picked != null && answeredIndex === game?.question_index) || Boolean(standing?.answeredCurrent),
  )
  let paused = $derived(Boolean(game?.paused_at))

  // Straight from the game row rather than from local state: the server decides
  // who holds the floor, and the phone just reads it.
  let iHaveTheFloor = $derived(game?.blurted_by === seat?.playerId)
  // Only when the room plays with the lockout. With it off, a wrong blurt still
  // gets the choices like everyone else.
  let lockedOut = $derived(
    Boolean(game?.blurt_lockout) && iHaveTheFloor && phase === 'question_open',
  )

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

  async function claim() {
    if (phase !== 'recall' || busy) return
    busy = true
    missed = false
    try {
      const got = await blurt(seat.playerToken)
      // Someone was a fraction faster. Say so plainly rather than leaving the
      // button looking broken.
      if (!got) missed = true
    } catch (error) {
      problem = error.message
    } finally {
      busy = false
    }
  }

  async function pick(choice) {
    if (phase !== 'question_open' || locked || lockedOut || busy) return
    busy = true
    problem = ''
    picked = choice
    answeredIndex = game.question_index
    try {
      await submitAnswer(seat.playerToken, choice)
    } catch (error) {
      picked = null
      answeredIndex = null
      // Missing the deadline is an ordinary thing that happens in a game, not a
      // fault. It gets a sentence, not an error screen with a way out.
      if (/too late|not taking/i.test(error.message)) tooSlow = true
      else problem = error.message
    } finally {
      busy = false
    }
  }

  async function sendText(event) {
    event.preventDefault()
    const text = draft.trim()
    if (!text || phase !== 'question_open' || locked || lockedOut || busy) return
    busy = true
    picked = -1
    answeredIndex = game.question_index
    try {
      await submitTextAnswer(seat.playerToken, text)
      draft = ''
    } catch (error) {
      picked = null
      answeredIndex = null
      if (/too late|not taking/i.test(error.message)) tooSlow = true
      else problem = error.message
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

  // Ask the server where this seat stands whenever the game moves. One small
  // call per phase change, and it is also how a removed player finds out: the
  // token stops resolving.
  $effect(() => {
    const key = `${game?.phase}:${game?.question_index}:${players.length}`
    if (!seat?.playerToken || !game || key === standingKey) return
    standingKey = key
    void (async () => {
      try {
        standing = await mySeat(seat.playerToken)
        if (standing && !seat.playerId) {
          seat = { ...seat, playerId: standing.playerId }
          writeSeat(seat)
        }
      } catch (error) {
        if (/not in this game/i.test(error.message)) {
          clearSeat()
          window.location.assign('/?removed=1')
        }
      }
    })()
  })

  // The host closed this room. A student has nothing to do here and no way to
  // find the new code, so send them back to the join screen with a clean seat.
  $effect(() => {
    if (!game?.closed_at) return
    clearSeat()
    window.location.assign('/')
  })

  $effect(() => {
    const index = game?.question_index
    if (index != null && index !== answeredIndex) {
      picked = null
      missed = false
      tooSlow = false
    }
  })

  // Your own result, and only yours. The database returns nothing until the room
  // reaches results, so this cannot be used to peek mid-question.
  $effect(() => {
    const p = game?.phase
    const index = game?.question_index
    if (!seat?.playerToken || (p !== 'results' && p !== 'final')) {
      result = null
      resultKey = ''
      return
    }
    const key = `${p}:${index}`
    if (key === resultKey) return
    resultKey = key
    void (async () => {
      try {
        result = await myResult(seat.playerToken)
      } catch {
        result = null
      }
    })()
  })
</script>

<main class="surface">
  {#if booting}
    <div class="centred"><p class="muted">Finding your seat…</p></div>
  {:else if problem}
    <div class="centred">
      <p class="muted">{problem}</p>
      <button class="ghost" onclick={leave}>Leave</button>
    </div>
  {:else if phase === 'lobby'}
    <div class="centred">
      <p class="eyebrow">You're in</p>
      <h1>{seat.name}</h1>
      <p class="muted">Look up at the board.</p>
    </div>
  {:else if paused && (phase === 'recall' || phase === 'question_open')}
    <div class="centred">
      <p class="eyebrow">Hold on</p>
      <h1 class="hush">Paused</h1>
      <p class="muted">Your teacher has stopped the clock.</p>
    </div>
  {:else if phase === 'recall'}
    <div class="blurt-wrap">
      {#if missed}
        <p class="eyebrow">Someone beat you to it</p>
      {:else}
        <p class="eyebrow">Know it?</p>
      {/if}
      <button class="blurt" onclick={claim} disabled={busy || missed}>BLURT</button>
      <p class="muted small">Right, it's worth more. Wrong, you're out this round.</p>
    </div>
  {:else if phase === 'blurt_claimed'}
    <div class="centred">
      {#if iHaveTheFloor}
        <p class="eyebrow">You have the floor</p>
        <h1 class="accent">Say it</h1>
        <p class="muted">Out loud, to the room.</p>
      {:else}
        <p class="eyebrow">Someone's blurting</p>
        <h1 class="hush">Listen</h1>
      {/if}
    </div>
  {:else if lockedOut}
    <div class="centred">
      <p class="eyebrow">You blurted</p>
      <h1 class="hush">Sit this one out</h1>
      <p class="muted">Back in on the next question.</p>
    </div>
  {:else if tooSlow && (phase === 'question_open' || phase === 'locked')}
    <div class="centred">
      <p class="eyebrow">Time ran out</p>
      <h1 class="hush">Too slow</h1>
      <p class="muted">Next one's yours.</p>
    </div>
  {:else if phase === 'question_open' && !locked && standing?.questionKind === 'text'}
    <form class="typing" onsubmit={sendText}>
      <label class="eyebrow" for="typed-answer">Type your answer</label>
      <!-- svelte-ignore a11y_autofocus -->
      <input
        id="typed-answer"
        bind:value={draft}
        maxlength="80"
        autocomplete="off"
        autocapitalize="off"
        autocorrect="off"
        spellcheck="false"
        enterkeyhint="send"
        autofocus
      />
      <button type="submit" disabled={busy || !draft.trim()}>Lock it in</button>
      <p class="muted small">Spelling counts. Capitals and punctuation don't.</p>
    </form>
  {:else if phase === 'question_open' && !locked}
    <header><span class="eyebrow">Look up at the board</span></header>
    <!-- As many shapes as the question has choices: two for true or false. -->
    <div class="pad" class:pair={(standing?.choiceCount ?? 4) === 2}>
      {#each SHAPES.slice(0, standing?.choiceCount || 4) as shape, i}
        <AnswerTile {shape} showText={false} onclick={() => pick(i)} disabled={busy} />
      {/each}
    </div>
  {:else if phase === 'question_open' || phase === 'locked'}
    <div class="centred">
      <h1 class="accent">Locked in</h1>
      {#if picked != null && picked >= 0}<p class="muted">{SHAPES[picked].label}</p>{/if}
    </div>
  {:else if phase === 'results'}
    <div class="centred verdict" class:right={result?.correct} class:wrong={result && !result.correct}>
      {#if result?.correct}
        <p class="eyebrow">{result.blurted ? 'You blurted it' : 'Correct'}</p>
        <h1 class="good">+{result.awarded.toLocaleString()}</h1>
        {#if result.streak > 1}<p class="muted">{result.streak} in a row</p>{/if}
      {:else if result?.answered}
        <p class="eyebrow">{result.blurted ? 'Not this time' : 'Wrong answer'}</p>
        <h1 class="bad">+0</h1>
        <p class="muted">Look up — the answer's on the board.</p>
      {:else}
        <p class="eyebrow">No answer</p>
        <h1 class="bad">+0</h1>
        <p class="muted">Get in on the next one.</p>
      {/if}
      <p class="total">
        {me ? me.score.toLocaleString() : '—'}
        <span class="muted">· {me ? ordinal(me.rank) : '—'} of {players.length}</span>
      </p>
    </div>
  {:else if phase === 'final'}
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
  }

  header {
    text-align: center;
  }

  .centred,
  .final,
  .blurt-wrap {
    grid-row: 1 / -1;
    display: grid;
    align-content: center;
    justify-items: center;
    gap: 10px;
    text-align: center;
  }

  .final {
    gap: 18px;
    width: 100%;
  }

  .final :global(.board) {
    width: 100%;
  }

  h1 {
    font-size: clamp(42px, 14vw, 68px);
  }

  .accent {
    color: var(--accent);
  }

  /* The one screen where the phone owes the player a plain answer: right or
     wrong, and what it was worth. */
  .verdict {
    gap: 6px;
  }

  .good {
    color: #4fd39a;
  }

  .bad {
    color: var(--muted);
  }

  .total {
    margin-top: 26px;
    font-family: var(--display);
    font-size: 30px;
    font-variant-numeric: tabular-nums;
  }

  .total .muted {
    font-family: var(--body);
    font-size: 14px;
  }

  .hush {
    color: var(--muted);
  }

  .muted {
    margin: 0;
    color: var(--muted);
  }

  .small {
    font-size: 13px;
    max-width: 24ch;
  }

  /* One button, as big as the phone allows. */
  .blurt-wrap {
    gap: 22px;
  }

  .blurt {
    width: min(78vw, 300px);
    aspect-ratio: 1;
    border-radius: 50%;
    background: var(--accent);
    color: #1a0d07;
    font-family: var(--display);
    font-size: clamp(40px, 12vw, 56px);
    font-weight: 400;
    letter-spacing: 0.01em;
    box-shadow: 0 10px 0 #a33d22;
    transition: transform 0.08s ease, box-shadow 0.08s ease;
  }

  .blurt:active:not(:disabled) {
    transform: translateY(8px);
    box-shadow: 0 2px 0 #a33d22;
  }

  .blurt:disabled {
    background: var(--surface-2);
    color: var(--muted);
    box-shadow: none;
    cursor: default;
  }

  .pad {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 12px;
  }

  /* True or false: two tall targets rather than two squat ones. */
  .pad.pair {
    grid-template-columns: 1fr;
  }

  .typing {
    grid-row: 1 / -1;
    display: grid;
    align-content: center;
    gap: 12px;
    width: 100%;
    max-width: 420px;
    margin: 0 auto;
    min-width: 0;
  }

  .typing input {
    width: 100%;
    min-width: 0;
    padding: 18px;
    border: 1px solid var(--line);
    border-radius: 10px;
    background: var(--surface);
    color: var(--ink);
    font: inherit;
    /* 16px or more, or iOS zooms the page when the field takes focus. */
    font-size: 22px;
    text-align: center;
  }

  .typing button {
    padding: 18px;
    border-radius: 10px;
    background: var(--accent);
    color: #1a0d07;
    font-size: 18px;
    font-weight: 700;
  }

  .typing button:disabled {
    background: var(--surface-2);
    color: var(--muted);
  }

  .typing .small {
    text-align: center;
    max-width: none;
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
