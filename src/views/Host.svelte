<script>
  // The projector. It owns nothing: the database decides the phase, the timing
  // and the scores, and this view renders whatever comes back. The teacher's
  // spacebar is a request to advance, not the advance itself.
  import AnswerTile from '../components/AnswerTile.svelte'
  import CountdownRing from '../components/CountdownRing.svelte'
  import DistributionBars from '../components/DistributionBars.svelte'
  import Leaderboard from '../components/Leaderboard.svelte'
  import {
    advanceGame,
    createGame,
    currentQuestion,
    distribution,
    fetchGame,
    fetchPlayers,
    firstQuiz,
    watchGame,
  } from '../lib/api.js'
  import { shapeFor } from '../lib/answers.js'
  import { clockBase, remainingFraction, ticker } from '../lib/clock.js'
  import { clearHost, readHost, writeHost } from '../lib/session.js'

  let host = $state(null)
  let game = $state(null)
  let players = $state([])
  let question = $state(null)
  let counts = $state([])
  let quizTitle = $state('')
  let booting = $state(true)
  let problem = $state('')
  let now = $state(Date.now())
  let questionBase = $state(null)

  // The poll replaces `game` every few seconds even when nothing changed, so
  // the reloads below are keyed to the question rather than to the object.
  let loadedKey = ''
  let autoLockedKey = ''

  let joinUrl = $derived(
    typeof location === 'undefined' ? '' : location.host.replace(/^www\./, ''),
  )
  let limit = $derived((question?.seconds ?? 20) * 1000)
  let answering = $derived(game?.phase === 'question_open')
  let total = $derived(players.length)

  async function startNewGame() {
    const quiz = await firstQuiz()
    if (!quiz) throw new Error('No quiz in the database. Run `npx supabase db push`.')
    quizTitle = quiz.title
    const { code, hostToken } = await createGame(quiz.id)
    const row = await fetchGame(code)
    host = { code, hostToken, gameId: row.id }
    writeHost(host)
    game = row
  }

  async function boot() {
    try {
      const saved = readHost()
      if (saved?.code) {
        const row = await fetchGame(saved.code)
        if (row && row.phase !== 'final') {
          host = saved
          game = row
          quizTitle = (await firstQuiz())?.title ?? ''
        }
      }
      if (!host) await startNewGame()
      players = await fetchPlayers(host.gameId)
    } catch (error) {
      problem = error.message
    } finally {
      booting = false
    }
  }

  async function step() {
    if (!host) return
    try {
      await advanceGame(host.hostToken)
      game = await fetchGame(host.code)
    } catch (error) {
      problem = error.message
    }
  }

  async function restart() {
    clearHost()
    host = null
    game = null
    players = []
    question = null
    booting = true
    problem = ''
    try {
      await startNewGame()
    } catch (error) {
      problem = error.message
    } finally {
      booting = false
    }
  }

  function onkeydown(event) {
    if (event.key === ' ' || event.key === 'Enter') {
      event.preventDefault()
      step()
    } else if (event.key.toLowerCase() === 'r') {
      restart()
    }
  }

  $effect(() => {
    boot()
  })

  $effect(() => ticker((t) => (now = t)))

  // Follow the game. Realtime pushes; the poll underneath covers school wifi.
  $effect(() => {
    if (!host?.gameId) return
    const watch = watchGame({
      code: host.code,
      gameId: host.gameId,
      onGame: (row) => (game = row),
      onPlayers: (rows) => (players = rows),
    })
    return watch.stop
  })

  // Each new question is a fresh read: the text always, the correct answer and
  // the distribution only once the database is willing to part with them.
  $effect(() => {
    const phase = game?.phase
    const index = game?.question_index
    const started = game?.question_started_at
    if (!host || index == null || index < 0) {
      question = null
      counts = []
      loadedKey = ''
      return
    }

    const key = `${phase}:${index}:${started}`
    if (key === loadedKey) return
    loadedKey = key
    questionBase = clockBase(started, limit, Date.now())

    void (async () => {
      try {
        question = await currentQuestion(host.code)
        counts = phase === 'results' ? await distribution(host.code) : []
      } catch (error) {
        problem = error.message
      }
    })()
  })

  // The projector holds the host token, so it is the thing that can close a
  // question when the clock runs out. Without this the board sits at zero with
  // the tiles still lit, looking broken, until someone touches the keyboard.
  $effect(() => {
    if (game?.phase !== 'question_open' || !questionBase || !host) return
    if (questionBase + limit - now > 0) return
    // `now` ticks every frame, so this guard — not a timer — is what keeps the
    // deadline from firing repeatedly.
    const key = `${game.question_index}:${questionBase}`
    if (autoLockedKey === key) return
    autoLockedKey = key
    step()
  })
</script>

<svelte:window {onkeydown} />

<main class="stage">
  <header>
    <span class="eyebrow">blurt</span>
    {#if game && game.question_index >= 0 && game.phase !== 'final'}
      <span class="eyebrow">Question {game.question_index + 1}</span>
    {/if}
    {#if host}
      <span class="eyebrow code">Join at {joinUrl} &middot; {host.code}</span>
    {/if}
  </header>

  {#if booting}
    <section class="centred"><p class="muted">Opening a room…</p></section>
  {:else if problem}
    <section class="centred">
      <h2>Something went wrong</h2>
      <p class="muted">{problem}</p>
      <p class="muted small">Press R to start a new room.</p>
    </section>
  {:else if game?.phase === 'lobby'}
    <section class="lobby">
      <p class="eyebrow">Room code</p>
      <h1 class="code-big">{host.code}</h1>
      <p class="sub">{quizTitle}</p>
      {#if players.length}
        <ul class="roster">
          {#each players as player (player.id)}
            <li>{player.name}</li>
          {/each}
        </ul>
      {:else}
        <p class="muted waiting">Waiting for the first phone…</p>
      {/if}
    </section>
  {:else if question && (game.phase === 'question_open' || game.phase === 'locked')}
    <section class="question">
      <div class="q-head">
        <h2>{question.text}</h2>
        {#if answering}
          <CountdownRing startedAt={questionBase} {limit} />
        {:else}
          <div class="times-up"><span>Time</span></div>
        {/if}
      </div>
      <div class="tiles">
        {#each question.choices as choice, i}
          <AnswerTile
            shape={shapeFor(i)}
            text={choice}
            state={game.phase === 'locked' ? 'dimmed' : 'idle'}
          />
        {/each}
      </div>
      <p class="answered">{game.answered_count} of {total} answered</p>
    </section>
  {:else if game?.phase === 'results' && question}
    <section class="results">
      <div class="left">
        <p class="eyebrow">The class said</p>
        <DistributionBars {counts} correctIndex={question.correctIndex ?? 0} />
        <p class="correct-line">
          Correct: <strong>{question.choices[question.correctIndex] ?? '—'}</strong>
        </p>
      </div>
      <div class="right">
        <p class="eyebrow">Standings</p>
        <Leaderboard standings={players} />
      </div>
    </section>
  {:else if game?.phase === 'final'}
    <section class="final">
      <p class="eyebrow">Final</p>
      <h1>{players[0]?.name ?? 'Nobody'} wins</h1>
      <Leaderboard standings={players} limit={5} />
      <p class="muted small">Press R for a new room</p>
    </section>
  {:else}
    <section class="centred"><p class="muted">Loading the question…</p></section>
  {/if}

  <footer class="eyebrow">Space advances &middot; R opens a new room</footer>
</main>

<style>
  .stage {
    display: grid;
    grid-template-rows: auto 1fr auto;
    gap: 24px;
    height: 100%;
    padding: 28px clamp(24px, 4vw, 56px) 20px;
  }

  header,
  footer {
    display: flex;
    flex-wrap: wrap;
    gap: 10px 28px;
    align-items: baseline;
  }

  header .code {
    margin-left: auto;
    color: var(--ink);
  }

  section {
    min-height: 0;
  }

  .centred {
    display: grid;
    align-content: center;
    justify-items: center;
    gap: 10px;
    text-align: center;
  }

  .muted {
    margin: 0;
    color: var(--muted);
    font-size: clamp(16px, 1.6vw, 20px);
  }

  .small {
    font-size: 14px;
  }

  /* Lobby */
  .lobby {
    display: grid;
    align-content: center;
    justify-items: center;
    gap: 10px;
    text-align: center;
  }

  .code-big {
    font-size: clamp(90px, 20vw, 260px);
    letter-spacing: 0.02em;
  }

  .sub {
    margin: 0;
    font-size: clamp(18px, 2vw, 26px);
    color: var(--muted);
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
    padding: 8px 16px;
    border-radius: 999px;
    background: var(--surface);
    font-size: 18px;
  }

  /* Question */
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

  /* Results */
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

  /* Final */
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
    .results {
      grid-template-columns: 1fr;
    }

    .tiles {
      grid-template-columns: 1fr;
    }
  }
</style>
