<script>
  // The wall. It holds no credential and can change nothing — it reads the room
  // by code and renders it big. Everything a student is allowed to see is here,
  // and nothing else is: the database withholds the choices during recall and
  // the correct answer until results, so this view has no secret to leak.
  import AnswerTile from '../components/AnswerTile.svelte'
  import CountdownRing from '../components/CountdownRing.svelte'
  import DistributionBars from '../components/DistributionBars.svelte'
  import Leaderboard from '../components/Leaderboard.svelte'
  import {
    blurter,
    currentQuestion,
    distribution,
    fetchGame,
    fetchPlayers,
    watchGame,
  } from '../lib/api.js'
  import { shapeFor } from '../lib/answers.js'
  import { clockBase, ticker } from '../lib/clock.js'

  let { code = null } = $props()

  let game = $state(null)
  let players = $state([])
  let question = $state(null)
  let counts = $state([])
  let floor = $state(null)
  let problem = $state('')
  let booting = $state(true)
  let now = $state(Date.now())
  let questionBase = $state(null)
  let loadedKey = ''

  let limit = $derived((question?.seconds ?? 20) * 1000)
  let phase = $derived(game?.phase ?? null)
  let counting = $derived(phase === 'recall' || phase === 'question_open')

  async function boot() {
    if (!code) {
      problem = 'No room code. Open this view from the host screen.'
      booting = false
      return
    }
    try {
      game = await fetchGame(code)
      if (!game) problem = `No room called ${code}.`
      else players = await fetchPlayers(game.id)
    } catch (error) {
      problem = error.message
    } finally {
      booting = false
    }
  }

  $effect(() => {
    boot()
  })

  $effect(() => ticker((t) => (now = t)))

  $effect(() => {
    if (!game?.id || !code) return
    const watch = watchGame({
      code,
      gameId: game.id,
      onGame: (row) => (game = row),
      onPlayers: (rows) => (players = rows),
    })
    return watch.stop
  })

  $effect(() => {
    const p = game?.phase
    const index = game?.question_index
    const started = game?.question_started_at
    if (!code || index == null || index < 0) {
      question = null
      counts = []
      floor = null
      loadedKey = ''
      return
    }

    const key = `${p}:${index}:${started}`
    if (key === loadedKey) return
    loadedKey = key
    questionBase = clockBase(started, limit, Date.now())

    void (async () => {
      try {
        question = await currentQuestion(code)
        counts = p === 'results' ? await distribution(code) : []
        floor = p === 'blurt_claimed' ? await blurter(code) : null
      } catch (error) {
        problem = error.message
      }
    })()
  })
</script>

<main class="stage">
  <header>
    <span class="eyebrow">blurt</span>
    {#if game && game.question_index >= 0 && phase !== 'final'}
      <span class="eyebrow">Question {game.question_index + 1}</span>
    {/if}
    {#if code}<span class="eyebrow code">{code}</span>{/if}
  </header>

  {#if booting}
    <section class="centred"><p class="muted">Finding the room…</p></section>
  {:else if problem}
    <section class="centred"><p class="muted">{problem}</p></section>
  {:else if phase === 'lobby'}
    <section class="lobby">
      <p class="eyebrow">Room code</p>
      <h1 class="code-big">{code}</h1>
      {#if players.length}
        <ul class="roster">
          {#each players as player (player.id)}<li>{player.name}</li>{/each}
        </ul>
      {:else}
        <p class="muted waiting">Waiting for the first phone…</p>
      {/if}
    </section>
  {:else if phase === 'recall' && question}
    <!-- No choices on screen and none in the payload. Knowing it beats
         recognising it, and that is the whole point of the window. -->
    <section class="recall">
      <h2 class="big-q">{question.text}</h2>
      <div class="recall-foot">
        <p class="prompt">Know it? <strong>Blurt.</strong></p>
        <CountdownRing startedAt={questionBase} {limit} size={96} />
      </div>
    </section>
  {:else if phase === 'blurt_claimed'}
    <section class="claimed">
      <p class="eyebrow">Has the floor</p>
      <h1 class="who">{floor?.name ?? '…'}</h1>
      <p class="sub">Say it out loud</p>
    </section>
  {:else if question && (phase === 'question_open' || phase === 'locked')}
    <section class="question">
      <div class="q-head">
        <h2>{question.text}</h2>
        {#if counting}
          <CountdownRing startedAt={questionBase} {limit} />
        {:else}
          <div class="times-up"><span>Time</span></div>
        {/if}
      </div>
      <div class="tiles">
        {#each question.choices ?? [] as choice, i}
          <AnswerTile
            shape={shapeFor(i)}
            text={choice}
            state={phase === 'locked' ? 'dimmed' : 'idle'}
          />
        {/each}
      </div>
      <p class="answered">{game.answered_count} of {players.length} answered</p>
    </section>
  {:else if phase === 'results' && question}
    <section class="results">
      <div class="left">
        <p class="eyebrow">The class said</p>
        <DistributionBars {counts} correctIndex={question.correctIndex ?? 0} />
        <p class="correct-line">
          Correct: <strong>{question.choices?.[question.correctIndex] ?? '—'}</strong>
        </p>
      </div>
      <div class="right">
        <p class="eyebrow">Standings</p>
        <Leaderboard standings={players} />
      </div>
    </section>
  {:else if phase === 'final'}
    <section class="final">
      <p class="eyebrow">Final</p>
      <h1>{players[0]?.name ?? 'Nobody'} wins</h1>
      <Leaderboard standings={players} limit={5} />
    </section>
  {:else}
    <section class="centred"><p class="muted">…</p></section>
  {/if}
</main>

<style>
  .stage {
    display: grid;
    grid-template-rows: auto 1fr;
    gap: 24px;
    height: 100%;
    padding: 28px clamp(24px, 4vw, 56px) 32px;
  }

  header {
    display: flex;
    flex-wrap: wrap;
    gap: 10px 28px;
    align-items: baseline;
  }

  header .code {
    margin-left: auto;
    color: var(--ink);
    font-size: 15px;
    letter-spacing: 0.3em;
  }

  section {
    min-height: 0;
  }

  .centred,
  .lobby,
  .claimed {
    display: grid;
    align-content: center;
    justify-items: center;
    gap: 10px;
    text-align: center;
  }

  .muted {
    margin: 0;
    color: var(--muted);
    font-size: clamp(16px, 1.8vw, 22px);
  }

  .code-big {
    font-size: clamp(90px, 20vw, 260px);
    letter-spacing: 0.02em;
  }

  .waiting {
    margin-top: 20px;
  }

  .roster {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 10px;
    margin: 24px 0 0;
    padding: 0;
    list-style: none;
  }

  .roster li {
    padding: 8px 18px;
    border-radius: 999px;
    background: var(--surface);
    font-size: clamp(16px, 1.6vw, 22px);
  }

  /* Recall — the question alone, as large as it will go */
  .recall {
    display: grid;
    grid-template-rows: 1fr auto;
    gap: 28px;
    align-items: center;
  }

  .big-q {
    font-family: var(--body);
    font-size: clamp(36px, 6.5vw, 96px);
    font-weight: 600;
    line-height: 1.05;
    text-transform: none;
    text-wrap: balance;
    align-self: center;
  }

  .recall-foot {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 24px;
  }

  .prompt {
    margin: 0;
    font-size: clamp(18px, 2.4vw, 32px);
    color: var(--muted);
  }

  .prompt strong {
    color: var(--accent);
  }

  .who {
    font-size: clamp(64px, 14vw, 180px);
    color: var(--accent);
  }

  .claimed .sub {
    margin: 0;
    font-size: clamp(20px, 2.6vw, 34px);
    color: var(--muted);
  }

  /* Multiple choice */
  .question {
    display: grid;
    grid-template-rows: auto 1fr auto;
    gap: 22px;
  }

  .q-head {
    display: flex;
    gap: 32px;
    align-items: center;
    justify-content: space-between;
  }

  .q-head h2 {
    font-family: var(--body);
    font-size: clamp(28px, 4vw, 54px);
    font-weight: 600;
    line-height: 1.1;
    text-transform: none;
    text-wrap: balance;
  }

  .times-up {
    display: grid;
    place-items: center;
    width: 120px;
    height: 120px;
    border: 4px solid var(--accent);
    border-radius: 50%;
    font-family: var(--display);
    font-size: 34px;
    color: var(--accent);
    text-transform: uppercase;
  }

  .tiles {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 16px;
    align-content: center;
  }

  .answered {
    margin: 0;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
  }

  .results {
    display: grid;
    grid-template-columns: 1.2fr 1fr;
    gap: 40px;
  }

  .left,
  .right {
    display: grid;
    grid-template-rows: auto 1fr auto;
    gap: 16px;
    min-height: 0;
  }

  .correct-line {
    margin: 0;
    font-size: clamp(18px, 2vw, 26px);
    color: var(--muted);
  }

  .correct-line strong {
    color: var(--ink);
  }

  .final {
    display: grid;
    align-content: center;
    gap: 18px;
    max-width: 760px;
    margin: 0 auto;
    width: 100%;
  }

  .final h1 {
    font-size: clamp(52px, 9vw, 120px);
  }

  @media (max-width: 900px) {
    .results,
    .tiles {
      grid-template-columns: 1fr;
    }
  }
</style>
