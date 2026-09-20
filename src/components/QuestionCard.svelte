<script>
  // One question in the editor. It owns nothing: every edit is reported upward
  // through `onchange`, and the parent decides when that becomes a save.
  import { CHOICES } from '../lib/answers.js'
  import { KINDS, problemWith } from '../lib/question.js'
  import { imageUrl } from '../lib/quizzes.js'

  let {
    question,
    index,
    total,
    status = '',
    defaultSeconds = 20,
    onchange,
    onmove,
    onduplicate,
    onremove,
    onimage,
  } = $props()

  let confirming = $state(false)
  let problem = $derived(problemWith(question))

  const set = (patch) => onchange({ ...question, ...patch })

  function setChoice(i, value) {
    const choices = [...question.choices]
    choices[i] = value
    set({ choices })
  }

  function setAccepted(i, value) {
    const accepted = [...question.accepted]
    accepted[i] = value
    set({ accepted })
  }

  function askRemove() {
    if (confirming) return onremove()
    confirming = true
    setTimeout(() => (confirming = false), 3000)
  }
</script>

<article class="card" class:invalid={problem}>
  <header>
    <span class="n">{index + 1}</span>
    <span class="kind">{KINDS[question.kind]}</span>
    <span class="status" class:warn={problem}>{problem ?? status}</span>
    <div class="acts">
      <button class="link" onclick={() => onmove(-1)} disabled={index === 0} aria-label="Move up">↑</button>
      <button class="link" onclick={() => onmove(1)} disabled={index === total - 1} aria-label="Move down">↓</button>
      <button class="link" onclick={onduplicate}>Duplicate</button>
      <button class="link" class:danger={confirming} onclick={askRemove}>{confirming ? 'Sure?' : 'Delete'}</button>
    </div>
  </header>

  <label class="sr" for="q-{question.key}">Question {index + 1}</label>
  <textarea
    id="q-{question.key}"
    rows="2"
    placeholder="The question, as it will appear on the wall"
    value={question.text}
    oninput={(e) => set({ text: e.currentTarget.value })}
  ></textarea>

  {#if question.kind === 'choice'}
    <div class="choices">
      {#each question.choices as choice, i}
        <div class="choice" style="--tile: {CHOICES[i].color}; --rim: {CHOICES[i].rim}">
          <input
            type="radio"
            name="correct-{question.key}"
            id="c-{question.key}-{i}"
            checked={question.correctIndex === i}
            onchange={() => set({ correctIndex: i })}
            aria-label="Choice {i + 1} is correct"
          />
          <span class="mark">{CHOICES[i].key}</span>
          <input
            type="text"
            id="t-{question.key}-{i}"
            placeholder={i < 2 ? `Choice ${i + 1}` : `Choice ${i + 1} (optional)`}
            value={choice}
            maxlength="120"
            oninput={(e) => setChoice(i, e.currentTarget.value)}
          />
        </div>
      {/each}
    </div>
  {:else if question.kind === 'truefalse'}
    <div class="tf">
      {#each ['True', 'False'] as label, i}
        <button class="pick" class:on={question.correctIndex === i} onclick={() => set({ correctIndex: i })}>
          {label}
        </button>
      {/each}
    </div>
  {:else}
    <div class="accepted">
      <p class="hint">
        Accepted answers. Case, spacing, punctuation, accents and a leading "the" are forgiven. Spelling is not.
      </p>
      {#each question.accepted as answer, i}
        <input
          type="text"
          id="a-{question.key}-{i}"
          placeholder={i === 0 ? 'The answer' : 'Another way to say it'}
          value={answer}
          maxlength="80"
          oninput={(e) => setAccepted(i, e.currentTarget.value)}
        />
      {/each}
      <button class="link" onclick={() => set({ accepted: [...question.accepted, ''] })}>+ another accepted answer</button>
    </div>
  {/if}

  <footer>
    <label>
      Answer time
      <select
        value={question.seconds ?? 0}
        onchange={(e) => set({ seconds: Number(e.currentTarget.value) || null })}
      >
        <option value={0}>Quiz default ({defaultSeconds}s)</option>
        {#each [10, 15, 20, 30, 45, 60, 90] as n}<option value={n}>{n}s</option>{/each}
      </select>
    </label>
    <label>
      Blurt
      <button
        class="toggle" class:on={question.blurtEnabled}
        aria-pressed={question.blurtEnabled}
        onclick={() => set({ blurtEnabled: !question.blurtEnabled })}
      >{question.blurtEnabled ? 'Yes' : 'No'}</button>
    </label>

    {#if question.blurtEnabled}
      <label>
        Recall window
        <select value={question.recallSeconds} onchange={(e) => set({ recallSeconds: Number(e.currentTarget.value) })}>
          {#each [5, 8, 12, 15, 20, 30] as n}<option value={n}>{n}s</option>{/each}
        </select>
      </label>
    {/if}

    <div class="image">
      {#if question.imagePath}
        <img src={imageUrl(question.imagePath)} alt="" />
        <button class="link" onclick={() => onimage(null)}>Remove picture</button>
      {:else}
        <label class="link upload">
          + Picture
          <input type="file" accept="image/*" onchange={(e) => onimage(e.currentTarget.files?.[0] ?? null)} />
        </label>
      {/if}
    </div>
  </footer>
</article>

<style>
  .card {
    display: grid;
    gap: 12px;
    padding: 16px 18px;
    border: 1px solid var(--line);
    border-radius: 12px;
    background: var(--stage-raised);
  }

  .card.invalid {
    border-color: rgba(255, 46, 151, 0.45);
  }

  header {
    display: flex;
    flex-wrap: wrap;
    gap: 6px 12px;
    align-items: baseline;
  }

  .n {
    font-family: var(--display);
    font-size: 24px;
    line-height: 1;
  }

  .kind,
  .status {
    font-size: 12px;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--ink-muted);
  }

  .status.warn {
    color: var(--neon-pink);
    letter-spacing: 0;
    text-transform: none;
    font-size: 13px;
  }

  .acts {
    margin-left: auto;
    display: flex;
    gap: 2px;
  }

  .link {
    padding: 4px 8px;
    font-size: 13px;
    color: var(--ink-muted);
    text-decoration: underline;
    text-underline-offset: 3px;
    cursor: pointer;
  }

  .link:disabled {
    opacity: 0.3;
    cursor: default;
  }

  .link.danger {
    color: var(--wrong);
    font-weight: 600;
  }

  .sr {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
  }

  textarea,
  input[type='text'],
  select {
    width: 100%;
    min-width: 0;
    padding: 10px 12px;
    border: 1px solid var(--line);
    border-radius: 8px;
    background: var(--stage);
    color: var(--ink);
    font: inherit;
  }

  textarea {
    font-size: 17px;
    font-weight: 500;
    resize: vertical;
  }

  .choices {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
    gap: 8px;
  }

  .choice {
    display: grid;
    grid-template-columns: auto auto 1fr;
    gap: 8px;
    align-items: center;
  }

  .choice input[type='radio'] {
    width: 18px;
    height: 18px;
    accent-color: var(--rim);
  }

  /* The letter on its tile colour, so the editor row looks like the answer the
     room will see. White on every fill clears 5:1 — see src/lib/answers.js. */
  .mark {
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    border-radius: var(--radius-sm);
    background: var(--tile);
    box-shadow: inset 0 0 0 1px var(--rim);
    color: var(--on-tile);
    font-family: var(--display);
    font-size: 14px;
    line-height: 1;
  }

  .tf {
    display: flex;
    gap: 8px;
  }

  .pick {
    flex: 1;
    padding: 12px;
    border: 1px solid var(--line);
    border-radius: 8px;
    color: var(--ink-muted);
    font-weight: 600;
  }

  .pick.on {
    border-color: var(--correct);
    background: rgba(57, 255, 136, 0.14);
    color: var(--ink);
  }

  .accepted {
    display: grid;
    gap: 8px;
    justify-items: start;
  }

  .hint {
    margin: 0;
    font-size: 13px;
    color: var(--ink-muted);
  }

  footer {
    display: flex;
    flex-wrap: wrap;
    gap: 12px 18px;
    align-items: end;
  }

  footer label:not(.upload) {
    display: grid;
    gap: 4px;
    font-size: 12px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: var(--ink-muted);
  }

  .toggle {
    padding: 9px 16px;
    border: 1px solid var(--line);
    border-radius: 999px;
    background: var(--stage);
    color: var(--ink-muted);
    font: inherit;
    font-size: 14px;
    letter-spacing: 0;
    text-transform: none;
  }

  .toggle.on {
    border-color: var(--neon-pink);
    background: rgba(255, 46, 151, 0.14);
    color: var(--ink);
  }

  footer select {
    width: auto;
    font-size: 14px;
    letter-spacing: 0;
    text-transform: none;
  }

  .image {
    margin-left: auto;
    display: flex;
    gap: 10px;
    align-items: center;
  }

  .image img {
    height: 44px;
    border-radius: 6px;
  }

  .upload input {
    position: absolute;
    width: 1px;
    height: 1px;
    opacity: 0;
  }
</style>
