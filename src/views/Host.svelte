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
    copySampleQuiz,
    listQuizzes,
    quizTitle as fetchQuizTitle,
    hostQuestion,
    extendQuestion,
    judgeBlurt,
    kickPlayer,
    renamePlayer,
    rosterStats,
    setPaused,
    updateGameSettings,
    watchGame,
  } from '../lib/api.js'
  import { clockBase, heartbeat, remainingSeconds, ticker } from '../lib/clock.js'
  import { clearHost, readHost, readSettings, writeHost, writeSettings } from '../lib/session.js'

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
  // No room yet: the teacher is choosing which quiz to run.
  let picking = $state(false)
  let notice = $state('')
  let quizzes = $state([])
  // Kept so a new room can take the projector with it. Lost on a host refresh,
  // which is why /present also watches for the room closing on its own.
  let projector = null
  let settings = $state(readSettings())
  let showSettings = $state(false)
  let autoNextKey = ''

  const RECALL_CHOICES = [5, 8, 12, 15, 20, 30]
  const AUTO_NEXT_CHOICES = [0, 3, 5, 8, 12]
  const PENALTY_CHOICES = [0, 100, 250, 500]

  async function applySettings(patch) {
    settings = { ...settings, ...patch }
    writeSettings(settings)
    if (!host) return
    try {
      await updateGameSettings(host.hostToken, settings)
      game = await fetchGame(host.code)
    } catch (error) {
      problem = error.message
    }
  }

  let phase = $derived(game?.phase ?? null)
  let limit = $derived(
    phase === 'recall' ? (question?.recallSeconds ?? 8) * 1000 : (question?.seconds ?? 20) * 1000,
  )
  let left = $derived(questionBase ? remainingSeconds(questionBase, limit, now) : null)
  let presentUrl = $derived(host ? `/present/${host.code}` : '')
  let answered = $derived(roster.filter((p) => p.answeredCurrent).length)
  let clockRunning = $derived(phase === 'recall' || phase === 'question_open')
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

  async function startNewGame(quiz) {
    quizTitle = quiz.title
    const { code, hostToken } = await createGame(quiz.id)
    // Carry this teacher's preferences into the new room before anyone joins.
    await updateGameSettings(hostToken, settings)
    const row = await fetchGame(code)
    host = { code, hostToken, gameId: row.id }
    writeHost(host)
    game = row
    picking = false
    // Carry the projector across if this page opened one and it is still up.
    if (projector && !projector.closed) projector.location.assign(`/present/${code}`)
  }

  async function choose(quiz) {
    booting = true
    problem = ''
    try {
      await startNewGame(quiz)
      roster = await rosterStats(host.hostToken)
    } catch (error) {
      problem = error.message
    } finally {
      booting = false
    }
  }

  async function useSample() {
    booting = true
    try {
      await copySampleQuiz()
      quizzes = await listQuizzes()
    } catch (error) {
      problem = error.message
    } finally {
      booting = false
    }
  }

  async function boot() {
    try {
      const saved = readHost()
      if (saved?.code) {
        const row = await fetchGame(saved.code)
        if (row && row.phase !== 'final' && !row.closed_at) {
          host = saved
          game = row
          quizTitle = await fetchQuizTitle(row.quiz_id)
        } else {
          // Finished or closed: forget it, or the bar goes on advertising a room
          // that no longer exists.
          clearHost()
        }
      }
      const wanted = new URLSearchParams(window.location.search).get('quiz')
      if (host) {
        roster = await rosterStats(host.hostToken)
        // Asked to host one quiz while a room on another is still open. Closing a
        // live room is not something to do on a guess, so say so and let them.
        if (wanted && wanted !== game.quiz_id) {
          notice = `Room ${host.code} is still open on “${quizTitle}”. Press R to close it, then choose the other quiz.`
        }
        if (wanted) history.replaceState(null, '', '/host')
      } else {
        quizzes = await listQuizzes()
        // Arriving from "Host this quiz" in the editor: skip the list.
        const quiz = wanted && quizzes.find((q) => q.id === wanted && q.questionCount > 0)
        if (quiz) {
          history.replaceState(null, '', '/host')
          await startNewGame(quiz)
          roster = await rosterStats(host.hostToken)
        } else {
          picking = true
        }
      }
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
  const extend = () => run(() => extendQuestion(host.hostToken, 15))
  const togglePause = () => run(() => setPaused(host.hostToken, !game?.paused_at))

  // Removing someone takes two taps on purpose. It deletes their score, and the
  // button sits in a table a teacher is jabbing at mid-lesson.
  let confirming = $state(null)
  let renaming = $state(null)
  let draftName = $state('')

  function askKick(id) {
    confirming = id
    setTimeout(() => {
      if (confirming === id) confirming = null
    }, 3000)
  }

  async function kick(id) {
    confirming = null
    await run(() => kickPlayer(host.hostToken, id))
  }

  function startRename(p) {
    renaming = p.id
    draftName = p.name
  }

  async function commitRename(event) {
    event.preventDefault()
    const id = renaming
    const name = draftName.trim()
    renaming = null
    if (id && name.length >= 2) await run(() => renamePlayer(host.hostToken, id, name))
  }

  function showProjector() {
    projector = window.open(presentUrl, 'blurt-present')
    return projector
  }

  // Ending the celebration without ending the lesson. The podium stays on the
  // wall — the class still wants to see who won — but the confetti and the
  // fanfare stop, and nothing is waiting on the teacher to close a tab.
  async function wrapUp() {
    if (!host?.hostToken) return
    try {
      await closeGame(host.hostToken)
      game = await fetchGame(host.code)
    } catch (error) {
      problem = error.message
    }
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
      // Back to the quiz list rather than straight into another room: the next
      // class is rarely running the same quiz as the last one.
      quizzes = await listQuizzes()
      picking = true
    } catch (error) {
      problem = error.message
    } finally {
      booting = false
    }
  }

  function onkeydown(event) {
    const key = event.key.toLowerCase()
    // Typing a name, or type-ahead inside a dropdown, is not a shortcut.
    if (event.target instanceof HTMLInputElement || event.target instanceof HTMLSelectElement) return

    if (phase === 'blurt_claimed' && (key === 'y' || key === 'n')) {
      event.preventDefault()
      judge(key === 'y')
    } else if (event.key === ' ' || event.key === 'Enter') {
      event.preventDefault()
      step()
    } else if (key === 'w' && phase === 'final' && !game?.closed_at) {
      wrapUp()
    } else if (key === 'r') {
      restart()
    } else if (key === 'p') {
      showProjector()
    } else if (key === 's') {
      showSettings = !showSettings
    } else if (key === 'e' && clockRunning) {
      extend()
    } else if (key === 'h' && clockRunning) {
      togglePause()
    }
  }

  $effect(() => {
    boot()
  })

  $effect(() => ticker((t) => (now = t)))

  $effect(() => heartbeat((t) => (beat = t)))

  $effect(() => {
    if (!host?.code) return
    const watch = watchGame({
      code: host.code,
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
    // The extension is part of the key: more time means a new limit to fetch.
    const key = `${p}:${index}:${started}:${game?.extra_seconds}`
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
    if (!questionBase || !host || game?.paused_at) return
    if (questionBase + limit - beat > 0) return
    const key = `${phase}:${game.question_index}:${questionBase}`
    if (autoLockedKey === key) return
    autoLockedKey = key
    step()
  })

  // Move on without a keypress, for a teacher who would rather not stand at the
  // laptop. Off by default: most want to talk over the results.
  $effect(() => {
    const seconds = game?.auto_next_seconds ?? 0
    if (phase !== 'results' || seconds <= 0 || !host) return
    const key = `next:${game.question_index}`
    if (autoNextKey === key) return
    autoNextKey = key
    const id = setTimeout(step, seconds * 1000)
    return () => clearTimeout(id)
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
  {:else if picking}
    <div class="picker">
      <header>
        <div class="grow">
          <span class="eyebrow">Open a room</span>
          <strong class="code">Which quiz?</strong>
        </div>
      </header>

      {#if quizzes.length}
        <ul class="quizzes">
          {#each quizzes as quiz (quiz.id)}
            <li>
              <div>
                <strong>{quiz.title}</strong>
                <span class="muted">{quiz.questionCount} question{quiz.questionCount === 1 ? '' : 's'}</span>
              </div>
              <button onclick={() => choose(quiz)} disabled={quiz.questionCount === 0}>
                Open a room
              </button>
            </li>
          {/each}
        </ul>
      {:else}
        <div class="panel">
          <p>You have no quizzes yet.</p>
          <div class="clock-controls">
            <button onclick={useSample}>Start from the sample quiz</button>
            <a class="ghost" href="/edit">Write your own</a>
          </div>
        </div>
      {/if}
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
      <button class="ghost" onclick={() => (showSettings = !showSettings)} aria-expanded={showSettings}>
        Settings
      </button>
      <button class="ghost" onclick={showProjector}>
        Open projector ↗
      </button>
    </header>

    {#if showSettings}
      <div class="panel settings">
        <div class="setting">
          <div>
            <strong>Blurt round</strong>
            <span>Each question opens with its choices hidden.</span>
          </div>
          <button
            class="toggle" class:on={settings.blurtEnabled}
            aria-pressed={settings.blurtEnabled}
            onclick={() => applySettings({ blurtEnabled: !settings.blurtEnabled })}
          >{settings.blurtEnabled ? 'On' : 'Off'}</button>
        </div>

        <div class="setting" class:disabled={!settings.blurtEnabled}>
          <div>
            <strong>Recall window</strong>
            <span>How long the room gets before the choices appear.</span>
          </div>
          <select
            value={settings.recallSeconds}
            disabled={!settings.blurtEnabled}
            onchange={(e) => applySettings({ recallSeconds: Number(e.currentTarget.value) })}
          >
            {#each RECALL_CHOICES as n}<option value={n}>{n}s</option>{/each}
          </select>
        </div>

        <div class="setting" class:disabled={!settings.blurtEnabled}>
          <div>
            <strong>A wrong blurt</strong>
            <span>Whether missing costs you the rest of the question.</span>
          </div>
          <button
            class="toggle" class:on={settings.blurtLockout}
            aria-pressed={settings.blurtLockout}
            disabled={!settings.blurtEnabled}
            onclick={() => applySettings({ blurtLockout: !settings.blurtLockout })}
          >{settings.blurtLockout ? 'Out of it' : 'Stays in'}</button>
        </div>

        <div class="setting" class:disabled={!settings.blurtEnabled}>
          <div>
            <strong>And costs</strong>
            <span>Points lost for a miss. Nobody is taken below zero.</span>
          </div>
          <select
            value={settings.blurtPenalty}
            disabled={!settings.blurtEnabled}
            onchange={(e) => applySettings({ blurtPenalty: Number(e.currentTarget.value) })}
          >
            {#each PENALTY_CHOICES as n}
              <option value={n}>{n === 0 ? 'Nothing' : `${n} points`}</option>
            {/each}
          </select>
        </div>

        <div class="setting">
          <div>
            <strong>Streak bonus</strong>
            <span>+100 for each right answer in a row, up to +500. Skipping breaks a run.</span>
          </div>
          <button
            class="toggle" class:on={settings.streakBonus}
            aria-pressed={settings.streakBonus}
            onclick={() => applySettings({ streakBonus: !settings.streakBonus })}
          >{settings.streakBonus ? 'On' : 'Off'}</button>
        </div>

        <div class="setting">
          <div>
            <strong>Reveal when everyone's in</strong>
            <span>Straight to the answer, or pause on "All in" first.</span>
          </div>
          <button
            class="toggle" class:on={settings.revealImmediately}
            aria-pressed={settings.revealImmediately}
            onclick={() => applySettings({ revealImmediately: !settings.revealImmediately })}
          >{settings.revealImmediately ? 'Straight away' : 'Pause first'}</button>
        </div>

        <div class="setting">
          <div>
            <strong>Move on by itself</strong>
            <span>Advance from the results screen without a keypress.</span>
          </div>
          <select
            value={settings.autoNextSeconds}
            onchange={(e) => applySettings({ autoNextSeconds: Number(e.currentTarget.value) })}
          >
            {#each AUTO_NEXT_CHOICES as n}
              <option value={n}>{n === 0 ? 'Wait for me' : `After ${n}s`}</option>
            {/each}
          </select>
        </div>

        <div class="setting">
          <div>
            <strong>Late join</strong>
            <span>Let someone in after the first question has started.</span>
          </div>
          <button
            class="toggle" class:on={settings.allowLateJoin}
            aria-pressed={settings.allowLateJoin}
            onclick={() => applySettings({ allowLateJoin: !settings.allowLateJoin })}
          >{settings.allowLateJoin ? 'On' : 'Off'}</button>
        </div>

        <p class="note">Changes apply from the next question, and are remembered for your next room.</p>
      </div>
    {/if}

    {#if phase === 'final'}
      <div class="panel done">
        <p><strong>That's the game.</strong> {roster[0]?.name ?? 'Nobody'} won with {(roster[0]?.score ?? 0).toLocaleString()}.</p>
        <div class="clock-controls">
          {#if game?.closed_at}
            <span class="wrapped">Wrapped up — the wall is showing the result, quietly.</span>
          {:else}
            <button class="ghost" onclick={wrapUp}>Wrap up <kbd>W</kbd></button>
          {/if}
          <a class="ghost" href="/games/{host.gameId}">See what they knew</a>
          <button class="ghost" onclick={restart}>New room <kbd>R</kbd></button>
        </div>
      </div>
    {/if}

    {#if notice}
      <div class="panel warn">
        <p>{notice}</p>
        <button class="ghost" onclick={() => (notice = '')}>Carry on with this room</button>
      </div>
    {/if}

    {#if phase === 'blurt_claimed'}
      <!-- The one moment the teacher has to act rather than observe. -->
      <div class="panel claim">
        <div>
          <span class="eyebrow">Has the floor</span>
          <strong class="who">{floor?.name ?? '…'}</strong>
        </div>
        <p class="answer">Answer: <strong>{question?.answer ?? '—'}</strong></p>
        <div class="verdict">
          <button class="yes" onclick={() => judge(true)}>
            <span aria-hidden="true">✓</span> Correct <kbd>Y</kbd>
          </button>
          <button class="no" onclick={() => judge(false)}>
            <span aria-hidden="true">✗</span> Wrong <kbd>N</kbd>
          </button>
        </div>
      </div>
    {:else if question && phase !== 'lobby' && phase !== 'final'}
      <div class="panel q">
        <p class="qtext">{question.text}</p>
        <p class="answer">
          Answer: <strong>{question.answer ?? '—'}</strong>
          {#if phase === 'recall'}<span class="muted"> · hidden from the room</span>{/if}
        </p>
        {#if clockRunning}
          <div class="clock-controls">
            <button class="ghost" onclick={extend}>+15s <kbd>E</kbd></button>
            <button class="ghost" class:held={game.paused_at} onclick={togglePause}>
              {game.paused_at ? 'Resume' : 'Pause'} <kbd>H</kbd>
            </button>
            {#if game.extra_seconds > 0}<span class="muted">+{game.extra_seconds}s added</span>{/if}
          </div>
        {/if}
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
              <th class="r">Streak</th><th class="r">Blurts</th><th class="r">Avg</th><th>State</th><th></th>
            </tr>
          </thead>
          <tbody>
            {#each roster as p (p.id)}
              <tr class:quiet={p.quietFor >= 2}>
                <td class="muted">{p.rank}</td>
                <td class="name">
                  {#if renaming === p.id}
                    <form onsubmit={commitRename}>
                      <!-- svelte-ignore a11y_autofocus -->
                      <input
                        id="rename-{p.id}"
                        bind:value={draftName}
                        maxlength="20"
                        autofocus
                        onblur={() => (renaming = null)}
                        aria-label="New name for {p.name}"
                      />
                    </form>
                  {:else}
                    {p.name}
                  {/if}
                </td>
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
                <td class="acts">
                  <button class="link" onclick={() => startRename(p)}>Rename</button>
                  {#if confirming === p.id}
                    <button class="link danger" onclick={() => kick(p.id)}>Sure?</button>
                  {:else}
                    <button class="link" onclick={() => askKick(p.id)}>Remove</button>
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
      Space advances · Y/N judges · E +15s · H pause · S settings · P projector · R new room
    </footer>
  {/if}
</main>

<style>
  /* A column rather than fixed grid rows: which panels are present changes with
     the phase, and a row template silently hands the stretchy row to whatever
     happens to land fifth. */
  .dash {
    display: flex;
    flex-direction: column;
    gap: 14px;
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

  /* The room code in scoreboard bulbs, as it reads on the wall. */
  .code {
    font-family: var(--bulbs);
    font-weight: 800;
    font-size: 30px;
    letter-spacing: 0.12em;
  }

  .secs {
    color: var(--neon-pink);
    font-family: var(--bulbs);
    font-weight: 800;
    font-variant-numeric: tabular-nums;
  }

  .muted {
    color: var(--ink-muted);
    margin: 0;
  }

  .panel {
    padding: 16px 18px;
    border: 1px solid var(--line);
    border-radius: 10px;
    background: var(--stage-raised);
    display: grid;
    gap: 10px;
  }

  .panel.done {
    border-color: var(--correct);
  }

  .panel.warn {
    border-color: var(--neon-pink);
  }

  .panel.claim {
    border-color: var(--neon-pink);
    background: var(--stage-high);
    grid-template-columns: 1fr auto;
    align-items: center;
    gap: 12px 20px;
  }

  .who {
    font-family: var(--display);
    font-size: 40px;
    color: var(--neon-pink);
  }

  .qtext {
    margin: 0;
    font-size: 17px;
    font-weight: 600;
  }

  .answer {
    margin: 0;
    font-size: 14px;
    color: var(--ink-muted);
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
    color: var(--stage);
  }

  .yes {
    background: var(--correct);
  }

  .no {
    background: var(--wrong);
  }

  kbd {
    display: inline-block;
    margin-left: 8px;
    padding: 1px 6px;
    border-radius: 4px;
    background: rgba(11, 7, 22, 0.25);
    font: inherit;
    font-size: 12px;
  }

  .settings {
    gap: 0;
  }

  .setting {
    display: flex;
    flex-wrap: wrap;
    gap: 10px 20px;
    align-items: center;
    justify-content: space-between;
    padding: 12px 0;
    border-bottom: 1px solid var(--line);
  }

  .setting:last-of-type {
    border-bottom: 0;
  }

  .setting div {
    display: grid;
    gap: 1px;
  }

  .setting strong {
    font-size: 14.5px;
  }

  .setting span {
    font-size: 13px;
    color: var(--ink-muted);
  }

  .setting.disabled {
    opacity: 0.45;
  }

  .toggle,
  .setting select {
    min-width: 116px;
    padding: 8px 14px;
    border: 1px solid var(--line-strong);
    border-radius: 999px;
    background: var(--stage-high);
    color: var(--ink-muted);
    font: inherit;
    font-size: 13px;
    text-align: center;
  }

  .toggle.on {
    border-color: var(--neon-pink);
    background: rgba(255, 46, 151, 0.14);
    color: var(--ink);
  }

  .setting select {
    border-radius: 8px;
    text-align: left;
  }

  .note {
    margin: 12px 0 0;
    font-size: 12px;
    color: var(--ink-muted);
  }

  .tiles {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 10px;
  }

  .picker {
    display: grid;
    gap: 16px;
    align-content: start;
  }

  .quizzes {
    display: grid;
    gap: 8px;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .quizzes li {
    display: flex;
    flex-wrap: wrap;
    gap: 10px 20px;
    align-items: center;
    justify-content: space-between;
    padding: 14px 18px;
    border: 1px solid var(--line);
    border-radius: 10px;
    background: var(--stage-raised);
  }

  .quizzes li div {
    display: grid;
    gap: 2px;
  }

  a.ghost {
    text-decoration: none;
  }

  .clock-controls {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    align-items: center;
    font-size: 13px;
  }

  .wrapped {
    color: var(--ink-muted);
  }

  .ghost.held {
    border-color: var(--neon-pink);
    color: var(--neon-pink);
  }

  .acts {
    white-space: nowrap;
    text-align: right;
  }

  .link {
    padding: 2px 6px;
    font-size: 12px;
    color: var(--ink-muted);
    text-decoration: underline;
    text-underline-offset: 3px;
  }

  .link.danger {
    color: var(--wrong);
    font-weight: 600;
  }

  .name input {
    width: 100%;
    max-width: 180px;
    padding: 4px 8px;
    border: 1px solid var(--neon-pink);
    border-radius: 6px;
    background: var(--stage);
    color: var(--ink);
    font: inherit;
  }

  .tile {
    display: grid;
    gap: 2px;
    padding: 12px 14px;
    border-radius: 10px;
    background: var(--stage-raised);
    border: 1px solid var(--line);
  }

  .tile.flag {
    border-color: var(--neon-pink);
  }

  .tile .n {
    font-family: var(--display);
    font-size: 30px;
    line-height: 1;
    font-variant-numeric: tabular-nums;
  }

  .tile small {
    font-size: 16px;
    color: var(--ink-muted);
  }

  .scroll {
    flex: 1;
    overflow: auto;
    min-height: 120px;
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
    background: var(--stage-high);
    text-align: left;
    font-size: 11px;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--ink-muted);
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
    color: var(--ink-muted);
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
    background: rgba(57, 255, 136, 0.16);
    color: var(--correct);
  }

  .pill.wait {
    background: var(--stage-high);
    color: var(--ink-muted);
  }

  .pill.out {
    background: rgba(255, 85, 119, 0.16);
    color: var(--wrong);
  }

  .ghost {
    padding: 9px 14px;
    border: 1px solid var(--line);
    border-radius: 999px;
    color: var(--ink);
    font-size: 13px;
  }

  /* The toggles carry their own on/off styling; without this exclusion the
     generic rule outranks `.toggle` on specificity and both states render the
     same solid accent, which is worse than no styling at all. */
  button:not(.ghost):not(.yes):not(.no):not(.toggle):not(.link) {
    justify-self: start;
    padding: 10px 16px;
    border-radius: 8px;
    background: var(--neon-pink);
    color: var(--on-pink);
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
