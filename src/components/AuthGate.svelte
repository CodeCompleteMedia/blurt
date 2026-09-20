<script>
  // Everything a teacher does sits behind this. Students never meet it: joining
  // and playing need no account, only a room code.
  import { auth, linkProblem, resendConfirmation, signIn, signUp } from '../lib/auth.svelte.js'

  let { children } = $props()

  let mode = $state('in')
  let email = $state('')
  let password = $state('')
  let busy = $state(false)
  let problem = $state('')
  let notice = $state('')
  let unconfirmed = $state(false)

  // Arriving from a confirmation link that did not work. The usual cause is not
  // the teacher: mail scanners and link previews open these links first, which
  // spends the one-time token — and quite often confirms the account in passing.
  const failed = linkProblem()
  if (failed) {
    notice =
      failed.code === 'otp_expired'
        ? 'That confirmation link had already been used or had expired. Your account may be confirmed anyway — try signing in. If it is not, you can ask for a fresh link below.'
        : `That link did not work (${failed.detail ?? failed.code}). Try signing in, or ask for a fresh link.`
  }

  async function resend() {
    problem = ''
    try {
      await resendConfirmation(email.trim())
      notice = 'A fresh confirmation link is on its way. Open it on this device.'
      unconfirmed = false
    } catch (error) {
      problem = error.message
    }
  }

  async function submit(event) {
    event.preventDefault()
    if (busy) return
    busy = true
    problem = ''
    notice = ''
    try {
      if (mode === 'in') {
        await signIn(email.trim(), password)
      } else if (await signUp(email.trim(), password)) {
        notice = 'Check your inbox to confirm the address, then sign in.'
        mode = 'in'
      }
    } catch (error) {
      problem = error.message
      unconfirmed = /not confirmed/i.test(error.message)
    } finally {
      busy = false
    }
  }
</script>

{#if !auth.ready}
  <main class="surface gate"><p class="muted">…</p></main>
{:else if auth.user}
  {@render children()}
{:else}
  <main class="surface gate">
    <form class="card" onsubmit={submit}>
      <h1 class="wordmark">blurt!</h1>
      <p class="muted">
        {mode === 'in' ? 'Sign in to host a room or edit your quizzes.' : 'Create a teacher account.'}
      </p>

      <label for="auth-email">Email</label>
      <input id="auth-email" type="email" bind:value={email} autocomplete="email" required />

      <label for="auth-password">Password</label>
      <input
        id="auth-password"
        type="password"
        bind:value={password}
        autocomplete={mode === 'in' ? 'current-password' : 'new-password'}
        minlength="8"
        required
      />

      <button type="submit" disabled={busy}>
        {busy ? '…' : mode === 'in' ? 'Sign in' : 'Create account'}
      </button>

      {#if problem}<p class="problem" role="alert">{problem}</p>{/if}
      {#if unconfirmed && email.trim()}
        <button type="button" class="switch" onclick={resend}>Send me a fresh confirmation link</button>
      {/if}
      {#if notice}<p class="notice" role="status">{notice}</p>{/if}

      <button
        type="button"
        class="switch"
        onclick={() => {
          mode = mode === 'in' ? 'up' : 'in'
          problem = ''
        }}
      >
        {mode === 'in' ? 'First time? Create an account' : 'Have an account? Sign in'}
      </button>

      <p class="muted small">Students don't need any of this — they join at <a href="/">the front door</a>.</p>
    </form>
  </main>
{/if}

<style>
  .gate {
    display: grid;
    place-items: center;
    height: 100%;
  }

  .card {
    display: grid;
    gap: 10px;
    width: 100%;
    max-width: 380px;
    min-width: 0;
  }

  h1 {
    font-size: 56px;
    text-align: center;
  }

  .muted {
    margin: 0 0 8px;
    color: var(--ink-muted);
    text-align: center;
  }

  .small {
    margin-top: 10px;
    font-size: 13px;
  }

  .small a {
    color: inherit;
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
    padding: 14px;
    border: 2px solid var(--line-strong);
    border-radius: var(--radius-md);
    background: var(--stage-raised);
    color: var(--ink);
    font: inherit;
    font-size: 17px;
  }

  input:focus {
    border-color: var(--neon-cyan);
  }

  button[type='submit'] {
    margin-top: 6px;
    padding: 15px;
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
  }

  .switch {
    justify-self: center;
    margin-top: 4px;
    color: var(--ink-muted);
    font-size: 14px;
    text-decoration: underline;
  }

  .problem,
  .notice {
    margin: 0;
    padding: 12px 14px;
    border-radius: 8px;
    background: var(--stage-raised);
    border: 1px solid var(--wrong);
    font-size: 15px;
  }

  .notice {
    border-color: var(--correct);
  }
</style>
