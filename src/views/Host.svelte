<script>
  // The teacher's screen. Not a second projector — a control surface.
  //
  // It holds the host token, which is why it is the machine the room cannot see,
  // and it is the only place `answers` is legible: the roster below comes from a
  // function gated on that token.
  import {
    advanceGame,
    blurter,
    closeGame,
    createGame,
    fetchGame,
    firstQuiz,
    hostQuestion,
    judgeBlurt,
    rosterStats,
    watchGame,
  } from '../lib/api.js'
  import { clockBase, heartbeat, remainingSeconds, ticker } from '../lib/clock.js'
  import { clearHost, readHost, writeHost } from '../lib/session.js'

  let host = $state(null)
  let game = $state(null)
  let roster = $state([])
  let question = $state(null)
  let floor = $state(null)
  let quizTitle = $state('')
  let booting = $state(true)
  let problem = $state('')
  let now = $state(Date.now())
  // Deadlines run off this, not off `now`: a teacher who switches tabs must not
  // stall the room.
  let beat = $state(Date.now())
  let questionBase = $state(null)
  let loadedKey = ''
  let autoLockedKey = ''
  // Kept so a new room can take the projector with it. Lost on a host refresh,
  // which is why /present also watches for the room closing on its own.
  let projector = null

  let phase = $derived(game?.phase ?? null)
  let limit = $derived(
    phase === 'recall' ? (question?.recallSeconds ?? 8) * 1000 : (question?.seconds ?? 20) * 1000,
  )
  let left = $derived(questionBase ? remainingSeconds(questionBase, limit, now) : null)
  let presentUrl = $derived(host ? `/present/${host.code}` : '')
  let answered = $derived(roster.filter((p) => p.answeredCurrent).length)
  let allIn = $derived(roster.length > 0 && answered >= roster.length)

  // The two columns a teacher actually acts on mid-lesson.
  let struggling = $derived(
    roster.filter((p) => p.answered >= 2 && p.correct / p.answered < 0.5).length,
  )
  let quiet = $derived(roster.filter((p) => p.quietFor >= 2).length)

  const PHASE_LABEL = {
    lobby: 'Lobby',
    recall: 'Recall — choices hidden',
    blurt_claimed: 'Blurt claimed',
    question_open: 'Choices up',
    locked: 'Closed',
    results: 'Results',
    final: 'Finished',
  }

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
      roster = await rosterStats(host.hostToken)
    } catch (error) {
      problem = error.message
    } finally {
      booting = false
    }
  }

  async function run(fn) {
    if (!host) return
    try {
      await fn()
      game = await fetchGame(host.code)
      roster = await rosterStats(host.hostToken)
    } catch (error) {
      problem = error.message
    }
  }

  const step = () => run(() => advanceGame(host.hostToken))
  const judge = (correct) => run(() => judgeBlurt(host.hostToken, correct))

  function showProjector() {
    projector = window.open(presentUrl, 'blurt-present')
    return projector
  }

  async function restart() {
    const previous = readHost()
    clearHost()
    host = null
    game = null
    roster = []
    question = null
    booting = true
    problem = ''
    try {
      // Tell the old room it is over before opening a new one, so the wall and
      // every phone still sitting in it find out rather than waiting forever.
      if (previous?.hostToken) {
        try {
          await closeGame(previous.hostToken)
        } catch {
          // A room that cannot be closed is not a reason to block a new one.
        }
      }
      await startNewGame()
      // Carry the projector across if this page opened one and it is still up.
      if (projector && !projector.closed) projector.location.assign(`/present/${host.code}`)
    } catch (error) {
      problem = error.message
    } finally {
      booting = false
    }
  }

  function onkeydown(event) {
    const key = event.key.toLowerCase()
    if (event.target instanceof HTMLInputElement) return

    if (phase === 'blurt_claimed' && (key === 'y' || key === 'n')) {
      event.preventDefault()
      judge(key === 'y')
    } else if (event.key === ' ' || event.key === 'Enter') {
      event.preventDefault()
      step()
    } else if (key === 'r') {
      restart()
    } else if (key === 'p') {
      showProjector()
    }
  }

  $effect(() => {
    boot()
  })

  $effect(() => ticker((t) => (now = t)))

  $effect(() => heartbeat((t) => (beat = t)))

  $effect(() => {
    if (!host?.gameId) return
    const watch = watchGame({
      code: host.code,
      gameId: host.gameId,
      onGame: (row) => (game = row),
      onPlayers: async () => (roster = await rosterStats(host.hostToken)),
    })
    return watch.stop
  })

  $effect(() => {
    const p = game?.phase
    const index = game?.question_index
    const started = game?.question_started_at
    if (!host || index == null || index < 0) {
      question = null
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
        question = await hostQuestion(host.hostToken)
        floor = p === 'blurt_claimed' ? await blurter(host.code) : null
        roster = await rosterStats(host.hostToken)
      } catch (error) {
        problem = error.message
      }
    })()
  })

  // Recall and the answer window both close themselves. The teacher is holding a
  // class, not a stopwatch.
  $effect(() => {
    if (phase !== 'recall' && phase !== 'question_open') return
    if (!questionBase || !host) return
    if (questionBase + limit - beat > 0) return
    const key = `${phase}:${game.question_index}:${questionBase}`
    if (autoLockedKey === key) return
    autoLockedKey = key
    step()
  })

  // `locked` is a beat, not a stop: "time" lands, then the answer goes up on its
  // own. Leaving the room staring at dimmed tiles waiting for a keypress was the
  // reason the reveal never seemed to arrive.
  $effect(() => {
    if (phase !== 'locked' || !host) return
    const key = `locked:${game.question_index}`
    if (autoLockedKey === key) return
    autoLockedKey = key
    const id = setTimeout(step, 1200)
    return () => clearTimeout(id)
  })
</script>

<svelte:window {onkeydown} />

<main class="dash surface">
  {#if booting}
    <p class="muted">Opening a room…</p>
  {:else if problem}
    <div class="panel warn">
      <p>{problem}</p>
      <button onclick={restart}>Start a new room</button>
    </div>
  {:else}
    <header>
      <div>
        <span class="eyebrow">Room</span>
        <strong class="code">{host.code}</strong>
      </div>
      <div>
        <span class="eyebrow">Phase</span>
        <strong>{phase === 'locked' && allIn ? 'All in' : (PHASE_LABEL[phase] ?? phase)}</strong>
        {#if left != null && (phase === 'recall' || phase === 'question_open')}
          <span class="secs">{left}s</span>
        {/if}
      </div>
      <div class="grow">
        <span class="eyebrow">Quiz</span>
        <strong>{quizTitle}</strong>
      </div>
      <button class="ghost" onclick={showProjector}>
        Open projector ↗
      </button>
    </header>

    {#if phase === 'blurt_claimed'}
      <!-- The one moment the teacher has to act rather than observe. -->
      <div class="panel claim">
        <div>
          <span class="eyebrow">Has the floor</span>
          <strong class="who">{floor?.name ?? '…'}</strong>
        </div>
        <p class="answer">Answer: <strong>{question?.choices?.[question?.correctIndex] ?? '—'}</strong></p>
        <div class="verdict">
          <button class="yes" onclick={() => judge(true)}>Correct <kbd>Y</kbd></button>
          <button class="no" onclick={() => judge(false)}>Wrong <kbd>N</kbd></button>
        </div>
      </div>
    {:else if question && phase !== 'lobby' && phase !== 'final'}
      <div class="panel q">
        <p class="qtext">{question.text}</p>
        <p class="answer">
          Answer: <strong>{question.choices?.[question.correctIndex] ?? '—'}</strong>
          {#if phase === 'recall'}<span class="muted"> · hidden from the room</span>{/if}
        </p>
      </div>
    {/if}

    <div class="tiles">
      <div class="tile"><span class="n">{answered}<small>/{roster.length}</small></span><span class="eyebrow">answered</span></div>
      <div class="tile" class:flag={struggling > 0}><span class="n">{struggling}</span><span class="eyebrow">under 50%</span></div>
      <div class="tile" class:flag={quiet > 0}><span class="n">{quiet}</span><span class="eyebrow">gone quiet</span></div>
    </div>

    {#if roster.length}
      <div class="scroll">
        <table>
          <thead>
            <tr>
              <th>#</th><th>Name</th><th class="r">Score</th><th class="r">Right</th>
              <th class="r">Streak</th><th class="r">Blurts</th><th class="r">Avg</th><th>State</th>
            </tr>
          </thead>
          <tbody>
            {#each roster as p (p.id)}
              <tr class:quiet={p.quietFor >= 2}>
                <td class="muted">{p.rank}</td>
                <td class="name">{p.name}</td>
                <td class="r">{p.score.toLocaleString()}</td>
                <td class="r">{p.answered ? `${p.correct}/${p.answered}` : '—'}</td>
                <td class="r">{p.streak || '—'}</td>
                <td class="r">{p.blurtWins || '—'}</td>
                <td class="r">{p.avgMs ? `${(p.avgMs / 1000).toFixed(1)}s` : '—'}</td>
                <td>
                  {#if p.answeredCurrent}
                    <span class="pill in">in</span>
                  {:else if p.quietFor >= 2}
                    <span class="pill out">quiet {p.quietFor}</span>
                  {:else}
                    <span class="pill wait">waiting</span>
                  {/if}
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {:else}
      <p class="muted">Nobody has joined yet. Students go to <strong>/</strong> and enter {host.code}.</p>
    {/if}

    <footer class="eyebrow">
      Space advances · Y/N judges a blurt · P opens the projector · R new room
    </footer>
  {/if}
</main>

<style>
  .dash {
    display: grid;
    grid-template-rows: auto auto auto 1fr auto;
    gap: 14px;
    align-content: start;
    height: 100%;
    max-width: 1100px;
    margin: 0 auto;
    width: 100%;
  }

  header {
    display: flex;
    flex-wrap: wrap;
    gap: 12px 28px;
    align-items: center;
    padding-bottom: 14px;
    border-bottom: 1px solid var(--line);
  }

  header div {
    display: grid;
    gap: 1px;
  }

  .grow {
    flex: 1;
  }

  .code {
    font-family: var(--display);
    font-size: 30px;
    letter-spacing: 0.06em;
  }

  .secs {
    color: var(--accent);
    font-variant-numeric: tabular-nums;
  }

  .muted {
    color: var(--muted);
    margin: 0;
  }

  .panel {
    padding: 16px 18px;
    border: 1px solid var(--line);
    border-radius: 10px;
    background: var(--surface);
    display: grid;
    gap: 10px;
  }

  .panel.warn {
    border-left: 3px solid var(--accent);
  }

  .panel.claim {
    border-color: var(--accent);
    background: var(--surface-2);
    grid-template-columns: 1fr auto;
    align-items: center;
    gap: 12px 20px;
  }

  .who {
    font-family: var(--display);
    font-size: 40px;
    color: var(--accent);
  }

  .qtext {
    margin: 0;
    font-size: 17px;
    font-weight: 600;
  }

  .answer {
    margin: 0;
    font-size: 14px;
    color: var(--muted);
  }

  .answer strong {
    color: var(--ink);
  }

  .verdict {
    display: flex;
    gap: 10px;
    grid-column: 2;
    grid-row: 1 / span 2;
  }

  .verdict button {
    padding: 14px 22px;
    border-radius: 10px;
    font-size: 16px;
    font-weight: 700;
    color: #10151b;
  }

  .yes {
    background: #3fbf87;
  }

  .no {
    background: #e0664a;
  }

  kbd {
    display: inline-block;
    margin-left: 8px;
    padding: 1px 6px;
    border-radius: 4px;
    background: rgba(16, 21, 27, 0.25);
    font: inherit;
    font-size: 12px;
  }

  .tiles {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 10px;
  }

  .tile {
    display: grid;
    gap: 2px;
    padding: 12px 14px;
    border-radius: 10px;
    background: var(--surface);
    border: 1px solid var(--line);
  }

  .tile.flag {
    border-color: var(--accent);
  }

  .tile .n {
    font-family: var(--display);
    font-size: 30px;
    line-height: 1;
    font-variant-numeric: tabular-nums;
  }

  .tile small {
    font-size: 16px;
    color: var(--muted);
  }

  .scroll {
    overflow: auto;
    min-height: 0;
    border: 1px solid var(--line);
    border-radius: 10px;
  }

  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 14px;
  }

  thead th {
    position: sticky;
    top: 0;
    background: var(--surface-2);
    text-align: left;
    font-size: 11px;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--muted);
    font-weight: 500;
    padding: 9px 12px;
  }

  td {
    padding: 9px 12px;
    border-top: 1px solid var(--line);
    font-variant-numeric: tabular-nums;
  }

  .r {
    text-align: right;
  }

  .name {
    font-weight: 600;
  }

  tr.quiet .name {
    color: var(--muted);
  }

  .pill {
    display: inline-block;
    padding: 2px 9px;
    border-radius: 999px;
    font-size: 11px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .pill.in {
    background: rgba(63, 191, 135, 0.16);
    color: #6fd7ac;
  }

  .pill.wait {
    background: var(--surface-2);
    color: var(--muted);
  }

  .pill.out {
    background: rgba(224, 102, 74, 0.16);
    color: #f09070;
  }

  .ghost {
    padding: 9px 14px;
    border: 1px solid var(--line);
    border-radius: 999px;
    color: var(--ink);
    font-size: 13px;
  }

  button:not(.ghost):not(.yes):not(.no) {
    justify-self: start;
    padding: 10px 16px;
    border-radius: 8px;
    background: var(--accent);
    color: #1a0d07;
    font-weight: 600;
  }

  @media (max-width: 640px) {
    .panel.claim {
      grid-template-columns: 1fr;
    }

    .verdict {
      grid-column: 1;
      grid-row: auto;
    }

    .verdict button {
      flex: 1;
    }
  }
</style>
