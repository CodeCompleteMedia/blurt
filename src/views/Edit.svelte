<script>
  // Where quizzes get written. This is the screen that decides whether blurt gets
  // used twice, so it saves as you type and never makes you think about saving —
  // but it also never pretends: a question that cannot be saved yet says why,
  // right on its card, instead of failing quietly on the way out.
  import QuestionCard from '../components/QuestionCard.svelte'
  import { copySampleQuiz, duplicateQuiz, listQuizzes } from '../lib/api.js'
  import { auth, signOut } from '../lib/auth.svelte.js'
  import { questionsFromText } from '../lib/csv.js'
  import { shrinkImage } from '../lib/image.js'
  import { KINDS, blankQuestion, problemWith } from '../lib/question.js'
  import {
    addQuestions,
    createQuiz,
    deleteQuestion,
    deleteQuiz,
    loadQuiz,
    removeImage,
    reorderQuestions,
    saveQuestion,
    saveQuizMeta,
    uploadImage,
  } from '../lib/quizzes.js'

  let { quizId = null } = $props()

  let loading = $state(true)
  let problem = $state('')

  // ------------------------------------------------------------ the list ---
  let quizzes = $state([])
  let confirmingQuiz = $state(null)

  async function loadList() {
    quizzes = await listQuizzes()
  }

  async function newQuiz() {
    const id = await createQuiz('Untitled quiz')
    window.location.assign(`/edit/${id}`)
  }

  async function removeQuiz(id) {
    if (confirmingQuiz !== id) {
      confirmingQuiz = id
      setTimeout(() => confirmingQuiz === id && (confirmingQuiz = null), 3000)
      return
    }
    confirmingQuiz = null
    await deleteQuiz(id)
    await loadList()
  }

  // ---------------------------------------------------------- one quiz ---
  let quiz = $state(null)
  let questions = $state([])
  let status = $state({})
  let pending = $state(0)
  let importing = $state(false)
  let pasted = $state('')
  let preview = $derived(pasted.trim() ? questionsFromText(pasted) : null)

  const timers = new Map()
  // Every write goes through one queue. Two questions saving at once would both
  // reach for "the next free position" and one would lose to the unique index.
  let queue = Promise.resolve()

  function enqueue(work) {
    pending += 1
    queue = queue
      .then(work)
      .catch((error) => (problem = error.message))
      .finally(() => (pending -= 1))
    return queue
  }

  const savedIds = () => questions.filter((q) => q.id).map((q) => q.id)
  const indexOf = (key) => questions.findIndex((q) => q.key === key)

  function schedule(key) {
    clearTimeout(timers.get(key))
    timers.set(key, setTimeout(() => persist(key), 700))
  }

  function persist(key) {
    const at = indexOf(key)
    if (at < 0 || problemWith(questions[at])) return
    status[key] = 'Saving…'
    enqueue(async () => {
      const i = indexOf(key)
      if (i < 0) return
      const q = questions[i]
      const isNew = !q.id
      // New rows land past the end, then the whole list is put in order — never
      // straight into position, which may already be taken.
      const id = await saveQuestion(q, quiz.id, isNew ? 100000 + i : i)
      if (isNew) {
        questions[indexOf(key)].id = id
        await reorderQuestions(quiz.id, savedIds())
      }
      status[key] = 'Saved'
    })
  }

  function change(i, next) {
    questions[i] = next
    status[next.key] = ''
    schedule(next.key)
  }

  function add(kind) {
    questions.push(blankQuestion(kind))
    requestAnimationFrame(() =>
      document.getElementById(`q-${questions[questions.length - 1].key}`)?.focus(),
    )
  }

  function move(i, by) {
    const j = i + by
    if (j < 0 || j >= questions.length) return
    ;[questions[i], questions[j]] = [questions[j], questions[i]]
    enqueue(() => reorderQuestions(quiz.id, savedIds()))
  }

  function duplicate(i) {
    const copy = { ...$state.snapshot(questions[i]), id: null, key: crypto.randomUUID(), imagePath: null }
    questions.splice(i + 1, 0, copy)
    schedule(copy.key)
  }

  function remove(i) {
    const [gone] = questions.splice(i, 1)
    clearTimeout(timers.get(gone.key))
    if (!gone.id) return
    enqueue(async () => {
      await deleteQuestion(gone.id)
      await removeImage(gone.imagePath)
      if (savedIds().length) await reorderQuestions(quiz.id, savedIds())
    })
  }

  function setImage(i, file) {
    const key = questions[i].key
    status[key] = file ? 'Uploading…' : 'Saving…'
    enqueue(async () => {
      const at = indexOf(key)
      const old = questions[at].imagePath
      const path = file ? await uploadImage(await shrinkImage(file), auth.user.id, quiz.id) : null
      questions[indexOf(key)].imagePath = path
      await removeImage(old)
      persist(key)
    })
  }

  let metaTimer
  function changeMeta(patch) {
    quiz = { ...quiz, ...patch }
    clearTimeout(metaTimer)
    metaTimer = setTimeout(() => enqueue(() => saveQuizMeta(quiz.id, quiz)), 700)
  }

  async function readFile(event) {
    const file = event.currentTarget.files?.[0]
    if (file) pasted = await file.text()
  }

  function runImport() {
    const incoming = preview.questions
    enqueue(async () => {
      const added = await addQuestions(incoming, quiz.id, 200000)
      questions.push(...added)
      await reorderQuestions(quiz.id, savedIds())
    })
    pasted = ''
    importing = false
  }

  function onbeforeunload(event) {
    if (pending > 0) event.preventDefault()
  }

  $effect(() => {
    void (async () => {
      try {
        if (quizId) {
          const loaded = await loadQuiz(quizId)
          if (!loaded) throw new Error('No such quiz, or it belongs to someone else.')
          quiz = { id: loaded.id, title: loaded.title, defaultSeconds: loaded.defaultSeconds }
          questions = loaded.questions
        } else {
          await loadList()
        }
      } catch (error) {
        problem = error.message
      } finally {
        loading = false
      }
    })()
  })

  let drafts = $derived(questions.filter((q) => problemWith(q)).length)
</script>

<svelte:window {onbeforeunload} />

<main class="surface edit">
  {#if loading}
    <p class="muted">…</p>
  {:else if !quizId}
    <header>
      <div class="grow">
        <span class="eyebrow">Signed in as {auth.user?.email}</span>
        <h1>Your quizzes</h1>
      </div>
      <a class="ghost" href="/host">Host a room</a>
      <button class="ghost" onclick={signOut}>Sign out</button>
    </header>

    {#if problem}<p class="problem" role="alert">{problem}</p>{/if}

    <ul class="list">
      {#each quizzes as q (q.id)}
        <li>
          <a class="title" href="/edit/{q.id}">
            <strong>{q.title}</strong>
            <span class="muted">{q.questionCount} question{q.questionCount === 1 ? '' : 's'}</span>
          </a>
          <button class="link" onclick={async () => { await duplicateQuiz(q.id); await loadList() }}>Duplicate</button>
          <button class="link" class:danger={confirmingQuiz === q.id} onclick={() => removeQuiz(q.id)}>
            {confirmingQuiz === q.id ? 'Delete for good?' : 'Delete'}
          </button>
        </li>
      {/each}
    </ul>

    <div class="row">
      <button class="primary" onclick={newQuiz}>New quiz</button>
      {#if !quizzes.length}
        <button class="ghost" onclick={async () => { await copySampleQuiz(); await loadList() }}>
          Start from the sample quiz
        </button>
      {/if}
    </div>
  {:else if quiz}
    <header>
      <a class="ghost" href="/edit">← Quizzes</a>
      <div class="grow">
        <label class="sr" for="quiz-title">Quiz title</label>
        <input
          id="quiz-title"
          class="titlebox"
          value={quiz.title}
          oninput={(e) => changeMeta({ title: e.currentTarget.value })}
        />
      </div>
      <span class="save" class:busy={pending > 0}>
        {pending > 0 ? 'Saving…' : drafts ? `${drafts} not saved yet` : 'All saved'}
      </span>
      <a class="ghost" href="/host">Host</a>
    </header>

    {#if problem}<p class="problem" role="alert">{problem}</p>{/if}

    <label class="default">
      Default answer time
      <select value={quiz.defaultSeconds} onchange={(e) => changeMeta({ defaultSeconds: Number(e.currentTarget.value) })}>
        {#each [10, 15, 20, 30, 45, 60] as n}<option value={n}>{n}s</option>{/each}
      </select>
    </label>

    <div class="cards">
      {#each questions as question, i (question.key)}
        <QuestionCard
          {question}
          index={i}
          total={questions.length}
          status={status[question.key] ?? (question.id ? 'Saved' : '')}
          defaultSeconds={quiz.defaultSeconds}
          onchange={(next) => change(i, next)}
          onmove={(by) => move(i, by)}
          onduplicate={() => duplicate(i)}
          onremove={() => remove(i)}
          onimage={(file) => setImage(i, file)}
        />
      {:else}
        <p class="muted">No questions yet. Add one below, or paste a whole set from a spreadsheet.</p>
      {/each}
    </div>

    <div class="row">
      {#each Object.entries(KINDS) as [kind, label]}
        <button class="primary" onclick={() => add(kind)}>+ {label}</button>
      {/each}
      <button class="ghost" onclick={() => (importing = !importing)}>Import from a spreadsheet</button>
    </div>

    {#if importing}
      <section class="import">
        <p class="muted">
          Copy rows out of Google Sheets or Excel and paste them here, or choose a .csv file. Columns:
          <strong>question, a, b, c, d, correct, seconds</strong>. Leave the choices empty and put
          <em>true</em> or <em>false</em> in <strong>correct</strong> for a true/false question, or the
          answer itself for a typed one (<em>answer|another way</em>).
        </p>
        <textarea
          id="import-paste"
          rows="6"
          placeholder="Capital of France?&#9;Paris&#9;Lyon&#9;Nice&#9;&#9;A&#9;15"
          bind:value={pasted}
        ></textarea>
        <input id="import-file" type="file" accept=".csv,.tsv,.txt,text/csv" onchange={readFile} />

        {#if preview}
          <p>
            <strong>{preview.questions.length}</strong> question{preview.questions.length === 1 ? '' : 's'} ready
            {#if preview.problems.length}· <span class="warn">{preview.problems.length} with problems, left out</span>{/if}
          </p>
          {#if preview.problems.length}
            <ul class="problems">
              {#each preview.problems as p}
                <li><span class="muted">row {p.line}</span> {p.why}{p.text ? ` — “${p.text.slice(0, 50)}”` : ''}</li>
              {/each}
            </ul>
          {/if}
          <button class="primary" onclick={runImport} disabled={!preview.questions.length}>
            Add {preview.questions.length} question{preview.questions.length === 1 ? '' : 's'}
          </button>
        {/if}
      </section>
    {/if}
  {:else}
    <p class="problem" role="alert">{problem}</p>
    <a class="ghost" href="/edit">← Quizzes</a>
  {/if}
</main>

<style>
  .edit {
    display: grid;
    gap: 16px;
    align-content: start;
    max-width: 900px;
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
    font-size: 34px;
  }

  .titlebox {
    width: 100%;
    padding: 6px 10px;
    border: 1px solid transparent;
    border-radius: 8px;
    background: transparent;
    color: var(--ink);
    font-family: var(--display);
    font-size: 30px;
  }

  .titlebox:hover,
  .titlebox:focus {
    border-color: var(--line);
    background: var(--surface);
  }

  .save {
    font-size: 12px;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--muted);
  }

  .save.busy {
    color: var(--accent);
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
  }

  .primary {
    padding: 11px 16px;
    border-radius: 10px;
    background: var(--accent);
    color: #1a0d07;
    font-weight: 600;
  }

  .primary:disabled {
    background: var(--surface-2);
    color: var(--muted);
  }

  .row {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }

  .list,
  .problems {
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

  .link.danger,
  .warn {
    color: #f09070;
    font-weight: 600;
  }

  .default {
    display: flex;
    gap: 10px;
    align-items: center;
    font-size: 13px;
    color: var(--muted);
  }

  select,
  .import textarea {
    padding: 8px 10px;
    border: 1px solid var(--line);
    border-radius: 8px;
    background: var(--surface);
    color: var(--ink);
    font: inherit;
  }

  .cards {
    display: grid;
    gap: 12px;
  }

  .import {
    display: grid;
    gap: 12px;
    padding: 16px 18px;
    border: 1px dashed var(--line);
    border-radius: 12px;
  }

  .import textarea {
    width: 100%;
    font-family: ui-monospace, Menlo, monospace;
    font-size: 13px;
  }

  .import p {
    margin: 0;
    font-size: 14px;
  }

  .problems li {
    font-size: 13px;
  }

  .problem {
    margin: 0;
    padding: 12px 14px;
    border-left: 3px solid var(--accent);
    border-radius: 8px;
    background: var(--surface);
  }

  .sr {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
  }
</style>
