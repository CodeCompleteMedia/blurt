<script>
  // Room code, then name. The database owns both checks — a wrong code and a
  // taken name come back as messages written to be read by a fifteen-year-old.
  import { joinGame } from '../lib/api.js'
  import { writeSeat } from '../lib/session.js'

  let code = $state('')
  let name = $state('')
  let step = $state('code')
  let busy = $state(false)
  let problem = $state('')

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

<main>
  <div class="card">
    <h1>blurt</h1>

    {#if step === 'code'}
      <form onsubmit={submitCode}>
        <label for="code">Room code</label>
        <input
          id="code"
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
</main>

<style>
  main {
    display: grid;
    place-items: center;
    height: 100%;
    padding: 24px;
  }

  .card {
    display: grid;
    gap: 22px;
    width: 100%;
    max-width: 380px;
  }

  h1 {
    font-size: 64px;
    text-align: center;
    color: var(--accent);
  }

  form {
    display: grid;
    gap: 10px;
  }

  label {
    font-size: 12px;
    letter-spacing: 0.18em;
    text-transform: uppercase;
    color: var(--muted);
  }

  input {
    padding: 18px;
    border: 1px solid var(--line);
    border-radius: 10px;
    background: var(--surface);
    color: var(--ink);
    font: inherit;
    font-size: 24px;
    text-align: center;
    letter-spacing: 0.08em;
  }

  button[type='submit'] {
    padding: 18px;
    border-radius: 10px;
    background: var(--accent);
    color: #1a0d07;
    font-size: 18px;
    font-weight: 700;
  }

  button[type='submit']:disabled {
    background: var(--surface-2);
    color: var(--muted);
    cursor: default;
  }

  .back {
    justify-self: center;
    color: var(--muted);
    font-size: 14px;
    text-decoration: underline;
  }

  .problem {
    margin: 0;
    padding: 12px 14px;
    border-radius: 8px;
    background: var(--surface);
    border-left: 3px solid var(--accent);
    color: var(--ink);
    font-size: 15px;
  }
</style>
