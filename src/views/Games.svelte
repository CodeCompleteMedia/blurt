<script>
  // What a class actually knew.
  //
  // The whole phase is one sentence: you should be able to see the two questions
  // the room bombed without opening a spreadsheet. So questions come back
  // hardest-first from the database and the worst of them are stated in a line of
  // prose at the top — the table is for afterwards, when you want the detail.
  import { rise } from '../lib/motion.js'
  import { downloadCsv, reportCsv } from '../lib/csv-export.js'
  import { deleteGame, listGames, loadReport } from '../lib/reports.js'

  let { gameId = null } = $props()

  let loading = $state(true)
  let problem = $state('')
  let games = $state([])
  let report = $state(null)
  let confirming = $state(null)
  let tab = $state('questions')

  const when = (iso) =>
    new Date(iso).toLocaleString(undefined, {
      weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit',
    })

  const seconds = (ms) => `${(ms / 1000).toFixed(1)}s`

  // Under half the room is the line worth drawing: fewer than half got it, so it
  // is worth saying again rather than worth moving on from.
  let bombed = $derived((report?.questions ?? []).filter((q) => q.answered > 0 && q.percent < 50))
  // "Most of them chose X" and "they scattered" are both claims about a
  // distribution. Under three answers there is no distribution to describe —
  // a single student picking one wrong answer is unanimous and scattered at
  // once — so those rooms just get told what was put instead.
  function missNote(q) {
    if (!q.commonWrong) return ''
    if (q.answered < 3) return `Answered “${q.commonWrong}”.`
    if (q.commonWrongCount >= Math.max(2, Math.ceil(q.answered * 0.6)))
      return `Most of them chose “${q.commonWrong}” — worth checking the question, not just the topic.`
    return `They scattered; “${q.commonWrong}” was the most common miss.`
  }

  async function remove(id) {
    if (confirming !== id) {
      confirming = id
      setTimeout(() => confirming === id && (confirming = null), 3000)
      return
    }
    confirming = null
    try {
      await deleteGame(id)
      games = await listGames()
    } catch (error) {
      problem = error.message
    }
  }

  function exportCsv() {
    const stamp = new Date(report.summary.playedAt).toISOString().slice(0, 10)
    const slug = report.summary.quizTitle.replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, '').toLowerCase()
    downloadCsv(`blurt-${slug || 'quiz'}-${stamp}.csv`, reportCsv(report))
  }

  $effect(() => {
    void (async () => {
      loading = true
      problem = ''
      try {
        if (gameId) report = await loadReport(gameId)
        else games = await listGames()
      } catch (error) {
        problem = error.message
      } finally {
        loading = false
      }
    })()
  })
</script>

<main class="surface games">
  {#if loading}
    <p class="muted">…</p>
  {:else if problem}
    <p class="problem" role="alert">{problem}</p>
    <a class="ghost" href="/games">← Games</a>
  {:else if !gameId}
    <header>
      <h1>Games played</h1>
    </header>

    {#if games.length}
      <ul class="list">
        {#each games as g (g.id)}
          <li>
            <a class="title" href="/games/{g.id}">
              <strong>{g.quizTitle}</strong>
              <span class="muted">
                {when(g.playedAt)} · {g.players} student{g.players === 1 ? '' : 's'} ·
                {#if g.finished}all {g.total} questions
                {:else if g.asked >= g.total}all {g.total} questions, left open
                {:else}stopped after {g.asked} of {g.total}{/if}
                {#if g.topName} · {g.topName} won{/if}
              </span>
            </a>
            <button class="link" class:danger={confirming === g.id} onclick={() => remove(g.id)}>
              {confirming === g.id ? 'Delete for good?' : 'Delete'}
            </button>
          </li>
        {/each}
      </ul>
    {:else}
      <div class="empty">
        <p class="muted">Nothing here yet. Rooms show up once they have asked a question.</p>
        <a class="ghost" href="/host">Open a room</a>
      </div>
    {/if}
  {:else}
    <header>
      <a class="ghost" href="/games">← Games</a>
      <div class="grow">
        <h1>{report.summary.quizTitle}</h1>
        <span class="muted">
          {when(report.summary.playedAt)} · room {report.summary.code} ·
          {report.summary.players} student{report.summary.players === 1 ? '' : 's'} ·
          {#if report.summary.finished}
            all {report.summary.total} questions
          {:else if report.summary.asked >= report.summary.total}
            all {report.summary.total} questions, left open
          {:else}
            stopped after {report.summary.asked} of {report.summary.total}
          {/if}
        </span>
      </div>
      <button class="ghost" onclick={exportCsv}>Export CSV</button>
    </header>

    <!-- The answer to the question the phase exists for, in words, before any
         table. -->
    <section class="verdict" in:rise>
      {#if !report.questions.length}
        <p>This room never got to a question.</p>
      {:else if !bombed.length}
        <p><strong>Nothing bombed.</strong> Every question this room reached was over half right.</p>
      {:else}
        <p>
          <strong>{bombed.length === 1 ? 'One question' : `${bombed.length} questions`}</strong>
          went badly — under half the room:
        </p>
        <ol class="bombed">
          {#each bombed.slice(0, 3) as q}
            <li>
              <span class="pc">{q.percent}%</span>
              <span class="what">
                {q.text}
                {#if q.commonWrong}<em>{missNote(q)}</em>{/if}
              </span>
            </li>
          {/each}
        </ol>
      {/if}
    </section>

    <div class="tabs">
      <button class:on={tab === 'questions'} onclick={() => (tab = 'questions')}>Questions</button>
      <button class:on={tab === 'students'} onclick={() => (tab = 'students')}>Students</button>
    </div>

    <div class="scroll">
      {#if tab === 'questions'}
        <table>
          <thead>
            <tr>
              <th>#</th><th>Question</th><th>Answer</th>
              <th class="r">Right</th><th class="r">%</th><th class="r">Median</th>
              <th>Most common miss</th><th>Blurt</th>
            </tr>
          </thead>
          <tbody>
            {#each report.questions as q (q.position)}
              <tr class:bad={q.answered > 0 && q.percent < 50}>
                <td class="muted">{q.position + 1}</td>
                <td class="text">{q.text}</td>
                <td class="muted">{q.answer ?? '—'}</td>
                <td class="r">{q.correct}/{q.answered}</td>
                <td class="r pc">{q.answered ? `${q.percent}%` : '—'}</td>
                <td class="r">{q.medianMs ? seconds(q.medianMs) : '—'}</td>
                <td class="muted">
                  {#if q.commonWrong}{q.commonWrong} <span class="times">×{q.commonWrongCount}</span>{:else}—{/if}
                </td>
                <td>
                  {#if q.blurter}
                    <span class="pill" class:won={q.blurtCorrect}>{q.blurter}</span>
                  {:else}—{/if}
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      {:else}
        <table>
          <thead>
            <tr>
              <th class="r">#</th><th>Name</th><th class="r">Score</th>
              <th class="r">Right</th><th class="r">Streak</th>
              <th class="r">Blurts</th><th class="r">Average</th><th>Missed</th>
            </tr>
          </thead>
          <tbody>
            {#each report.players as p (p.id)}
              <tr>
                <td class="r muted">{p.place}</td>
                <td class="text">{p.name}</td>
                <td class="r">{p.score.toLocaleString()}</td>
                <td class="r">{p.correct}/{p.answered}</td>
                <td class="r">{p.bestStreak || '—'}</td>
                <td class="r">
                  {#if p.blurtWins || p.blurtMisses}
                    {p.blurtWins}<span class="muted">/{p.blurtWins + p.blurtMisses}</span>
                  {:else}—{/if}
                </td>
                <td class="r">{p.avgMs ? seconds(p.avgMs) : '—'}</td>
                <td class="muted">{p.missed.length ? p.missed.map((i) => i + 1).join(', ') : '—'}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      {/if}
    </div>
  {/if}
</main>

<style>
  .games {
    display: flex;
    flex-direction: column;
    gap: 16px;
    max-width: 1100px;
    margin: 0 auto;
    width: 100%;
    min-height: 100%;
  }

  header {
    display: flex;
    flex-wrap: wrap;
    gap: 10px 14px;
    align-items: center;
    padding-bottom: 14px;
    border-bottom: 1px solid var(--line);
  }

  .grow {
    flex: 1;
    min-width: 200px;
    display: grid;
    gap: 2px;
  }

  h1 {
    font-size: clamp(26px, 3vw, 34px);
  }

  .muted {
    margin: 0;
    color: var(--muted);
  }

  .ghost {
    padding: 9px 14px;
    border: 1px solid var(--line);
    border-radius: 999px;
    color: var(--ink);
    font-size: 13px;
    text-decoration: none;
    white-space: nowrap;
  }

  .list,
  .bombed {
    display: grid;
    gap: 8px;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .list li {
    display: flex;
    flex-wrap: wrap;
    gap: 6px 10px;
    align-items: center;
    padding: 14px 18px;
    border: 1px solid var(--line);
    border-radius: 10px;
    background: var(--surface);
  }

  .title {
    flex: 1;
    display: grid;
    gap: 2px;
    color: inherit;
    text-decoration: none;
  }

  .link {
    padding: 4px 8px;
    font-size: 13px;
    color: var(--muted);
    text-decoration: underline;
    text-underline-offset: 3px;
  }

  .link.danger {
    color: #f09070;
    font-weight: 600;
  }

  .empty {
    display: grid;
    gap: 12px;
    justify-items: start;
    padding: 18px;
    border: 1px dashed var(--line);
    border-radius: 12px;
  }

  .verdict {
    display: grid;
    gap: 12px;
    padding: 18px 20px;
    border: 1px solid var(--line);
    border-left: 3px solid var(--accent);
    border-radius: 12px;
    background: var(--surface);
  }

  .verdict p {
    margin: 0;
    font-size: 16px;
  }

  .bombed li {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 4px 14px;
    align-items: baseline;
  }

  .pc {
    font-family: var(--display);
    font-size: 22px;
    color: var(--accent);
    font-variant-numeric: tabular-nums;
  }

  .what {
    display: grid;
    gap: 2px;
    font-size: 15.5px;
  }

  .what em {
    font-size: 14px;
    color: var(--muted);
  }

  .tabs {
    display: flex;
    gap: 4px;
  }

  .tabs button {
    padding: 7px 14px;
    border-radius: 999px;
    color: var(--muted);
    font-size: 14px;
    font-weight: 500;
  }

  .tabs button.on {
    background: var(--surface-2);
    color: var(--ink);
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
    background: var(--surface-2);
    text-align: left;
    font-size: 11px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--muted);
    font-weight: 500;
    padding: 9px 12px;
    white-space: nowrap;
  }

  td {
    padding: 9px 12px;
    border-top: 1px solid var(--line);
    font-variant-numeric: tabular-nums;
    vertical-align: top;
  }

  .r {
    text-align: right;
  }

  .text {
    font-weight: 500;
    min-width: 16ch;
  }

  tr.bad .pc {
    color: var(--accent);
    font-family: inherit;
    font-size: inherit;
    font-weight: 700;
  }

  .times {
    color: var(--muted);
    font-size: 12px;
  }

  .pill {
    display: inline-block;
    padding: 2px 9px;
    border-radius: 999px;
    background: rgba(224, 102, 74, 0.16);
    color: #f09070;
    font-size: 12px;
    white-space: nowrap;
  }

  .pill.won {
    background: rgba(63, 191, 135, 0.16);
    color: #6fd7ac;
  }

  .problem {
    margin: 0;
    padding: 12px 14px;
    border-left: 3px solid var(--accent);
    border-radius: 8px;
    background: var(--surface);
  }
</style>
