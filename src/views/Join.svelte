<script>
  // Room code, then name. The database owns both checks — a wrong code and a
  // taken name come back as messages written to be read by a fifteen-year-old.
  import { joinGame } from '../lib/api.js'
  import { writeSeat } from '../lib/session.js'

  // A scanned QR arrives with the room already decided, so the code step is
  // skipped entirely: the student sees the name field and nothing else.
  let { code: scanned = null } = $props()

  let code = $state(scanned ?? '')
  let name = $state('')
  let step = $state(scanned ? 'name' : 'code')
  let busy = $state(false)
  // Sent here by /play when the seat stopped existing. Said once, plainly — a
  // student bounced to a blank join form would assume the app broke.
  const removed = new URLSearchParams(window.location.search).has('removed')
  let problem = $state(removed ? 'You were removed from the room.' : '')

  let field = $state(null)

  // A student holding a phone should be typing the moment the step changes,
  // not hunting for the box.
  $effect(() => {
    void step
    field?.focus()
  })

  let codeReady = $derived(code.trim().length >= 4)
  let nameReady = $derived(name.trim().length >= 2)

  function submitCode(event) {
    event.preventDefault()
    problem = ''
    if (codeReady) step = 'name'
  }

  async function submitName(event) {
    event.preventDefault()
    if (!nameReady || busy) return
    busy = true
    problem = ''
    try {
      const seat = await joinGame(code, name)
      writeSeat({ ...seat, code: code.trim().toUpperCase(), name: name.trim() })
      window.location.assign('/play')
    } catch (error) {
      problem = error.message
      // A bad room code only shows up here, so send them back to fix it.
      if (/no such room/i.test(problem)) step = 'code'
    } finally {
      busy = false
    }
  }
</script>

<main class="surface">
  <div class="card">
    <h1 class="wordmark">blurt!</h1>

    {#if step === 'code'}
      <form onsubmit={submitCode}>
        <label for="code">Room code</label>
        <input
          id="code"
          class="code"
          bind:this={field}
          bind:value={code}
          placeholder="ABC12"
          autocomplete="off"
          autocapitalize="characters"
          autocorrect="off"
          spellcheck="false"
          maxlength="8"
        />
        <button type="submit" disabled={!codeReady}>Enter</button>
      </form>
    {:else}
      <form onsubmit={submitName}>
        <label for="name">Your name</label>
        <input id="name" bind:this={field} bind:value={name} placeholder="First name" maxlength="20" />
        <button type="submit" disabled={!nameReady || busy}>
          {busy ? 'Joining…' : 'Join'}
        </button>
      </form>
      <button class="back" onclick={() => (step = 'code')}>Wrong code?</button>
    {/if}

    {#if problem}
      <p class="problem" role="alert">{problem}</p>
    {/if}
  </div>

  <!-- The only way onto the teacher's side from here, kept out of a student's way. -->
  <a class="teacher" href="/host">Teacher? Open a room</a>
</main>

<style>
  main {
    display: grid;
    grid-template-rows: 1fr auto;
    place-items: center;
    height: 100%;
  }

  .teacher {
    color: var(--ink-muted);
    font-size: 13px;
    text-underline-offset: 3px;
  }

  .card {
    display: grid;
    gap: 22px;
    width: 100%;
    max-width: 380px;
    /* A text input has an intrinsic width of about twenty characters, and a grid
       item will not shrink below its content unless told it may. At 24px type
       that pushed the form 3px past a 320px screen. */
    min-width: 0;
  }

  h1 {
    font-size: 64px;
    text-align: center;
  }

  form {
    display: grid;
    gap: 10px;
  }

  label {
    font-size: 12px;
    letter-spacing: 0.18em;
    text-transform: uppercase;
    color: var(--ink-muted);
  }

  input {
    width: 100%;
    min-width: 0;
    padding: 18px;
    border: 2px solid var(--line-strong);
    border-radius: var(--radius-md);
    background: var(--stage-raised);
    color: var(--ink);
    font: inherit;
    font-size: 24px;
    text-align: center;
    letter-spacing: 0.08em;
  }

  input:focus {
    border-color: var(--neon-cyan);
    box-shadow: 0 0 16px -2px #19e3ff99;
  }

  /* 0.8, not 0.7: the blend against --stage-raised is 5.85:1 rather than
     4.76:1, so a nudge in either direction does not quietly fail AA. */
  input::placeholder {
    color: var(--ink-muted);
    opacity: 0.8;
  }

  /* The same face the wall shows it in, so what a student copies and what they
     type look like the same thing. */
  input.code {
    font-family: var(--display);
    font-size: 34px;
    letter-spacing: 0.2em;
    text-transform: uppercase;
  }

  button[type='submit'] {
    padding: 18px;
    border-radius: 10px;
    background: var(--neon-pink);
    color: var(--on-pink);
    font-family: var(--display);
    font-size: 18px;
    font-weight: 400;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    box-shadow: 0 4px 0 var(--neon-pink-deep);
  }

  button[type='submit']:disabled {
    background: var(--stage-high);
    color: var(--ink-muted);
    box-shadow: none;
    cursor: default;
  }

  .back {
    justify-self: center;
    color: var(--ink-muted);
    font-size: 14px;
    text-decoration: underline;
  }

  .problem {
    margin: 0;
    padding: 12px 14px;
    border-radius: 8px;
    background: var(--stage-raised);
    border: 1px solid var(--wrong);
    color: var(--ink);
    font-size: 15px;
  }
</style>
