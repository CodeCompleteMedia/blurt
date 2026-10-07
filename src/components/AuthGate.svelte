<script>
  // Everything a teacher does sits behind this. Students never meet it: joining
  // and playing need no account, only a room code.
  import {
    auth,
    linkProblem,
    requestReset,
    resendConfirmation,
    setPassword,
    signIn,
    signUp,
    signOut,
  } from '../lib/auth.svelte.js'
  import { intentInAddress, rememberIntent } from '../lib/billing.svelte.js'

  let { children } = $props()

  // Arriving from the Teacher plan on the pricing page: /host?plan=month|year.
  // Whoever gets through this gate is sent on to Checkout by the shell.
  const arrivedWanting = intentInAddress()
  let wanted = $state(arrivedWanting)

  // The last chance to choose yearly before Stripe. The address is rewritten
  // too, because the address is what the shell reads on the way to Checkout.
  function bill(interval) {
    wanted = interval
    history.replaceState(null, '', `${window.location.pathname}?plan=${interval}${window.location.hash}`)
  }

  // in | up | reset — the third asks only for an address and sends a link.
  // Someone who came to buy is most likely new, so they start on sign-up.
  let mode = $state(arrivedWanting ? 'up' : 'in')
  let email = $state('')
  let password = $state('')
  let again = $state('')
  let busy = $state(false)
  let problem = $state('')
  let notice = $state('')
  let unconfirmed = $state(false)
  let shown = $state(false)

  // Arriving from a confirmation link that did not work. The usual cause is not
  // the teacher: mail scanners and link previews open these links first, which
  // spends the one-time token — and quite often confirms the account in passing.
  const failed = linkProblem()
  if (failed) {
    notice =
      failed.code === 'otp_expired'
        ? 'That link had already been used or had expired. If it was a confirmation link your account may be confirmed anyway — try signing in. Otherwise ask for a fresh one below.'
        : `That link did not work (${failed.detail ?? failed.code}). Try signing in, or ask for a fresh link.`
  }

  async function resend() {
    problem = ''
    try {
      await resendConfirmation(email.trim(), wanted)
      notice = 'A fresh confirmation link is on its way.'
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
      } else if (mode === 'reset') {
        await requestReset(email.trim())
        // Deliberately the same answer whether or not that address has an
        // account: this form must not say which teachers exist.
        notice = 'If that address has an account, a reset link is on its way. Open it on this device.'
        mode = 'in'
      } else {
        // The link carries the plan; this is the fallback for a project
        // whose allow-list sends the link to the bare /host instead.
        if (wanted) rememberIntent(wanted)
        if (await signUp(email.trim(), password, wanted)) {
          notice = ''
          waiting = true
        }
      }
    } catch (error) {
      problem = error.message
      unconfirmed = /not confirmed/i.test(error.message)
    } finally {
      busy = false
    }
  }

  // Between "Create account" and the confirmation link being clicked. There
  // is nothing more to do on this page: the link in the email carries the plan
  // and goes on to Checkout by itself, in whatever browser opens it.
  let waiting = $state(false)

  function startOver() {
    waiting = false
    password = ''
    mode = 'up'
  }

  // The recovery link signed them in; this is the only thing they can do with
  // that session until the password is set.
  async function choose(event) {
    event.preventDefault()
    if (busy) return
    if (password !== again) {
      problem = 'Those two do not match.'
      return
    }
    busy = true
    problem = ''
    try {
      await setPassword(password)
      password = ''
      again = ''
    } catch (error) {
      problem = error.message
    } finally {
      busy = false
    }
  }

  async function abandon() {
    auth.recovering = false
    password = ''
    again = ''
    await signOut()
  }
</script>

{#if !auth.ready}
  <main class="surface gate"><p class="muted">…</p></main>
{:else if auth.recovering}
  <main class="surface gate">
    <form class="card" onsubmit={choose}>
      <h1 class="wordmark">Blurt!</h1>
      <p class="muted">Choose a new password. You are signed in on this device while you do.</p>

      <label for="new-password">New password</label>
      <input
        id="new-password"
        type="password"
        bind:value={password}
        autocomplete="new-password"
        minlength="8"
        required
      />

      <label for="new-password-again">New password again</label>
      <input
        id="new-password-again"
        type="password"
        bind:value={again}
        autocomplete="new-password"
        minlength="8"
        required
      />

      <button type="submit" disabled={busy}>{busy ? '…' : 'Set password'}</button>

      {#if problem}<p class="problem" role="alert">{problem}</p>{/if}

      <button type="button" class="switch" onclick={abandon}>Not now — sign out</button>
    </form>
  </main>
{:else if auth.user}
  {@render children()}
{:else if waiting}
  <main class="surface gate">
    <div class="card">
      <h1 class="wordmark">Blurt!</h1>
      <h2>Check your inbox</h2>
      <p class="muted">
        We sent a link to <strong>{email.trim()}</strong>. Click it to confirm the address.
      </p>
      <p class="wanted solo">
        {#if wanted}
          The link takes you on to payment (Teacher plan, {wanted === 'year' ? '$72 a year' : '$8 a month'}) and then
          into Blurt. You can close this page.
        {:else}
          The link takes you straight into Blurt. You can close this page.
        {/if}
      </p>

      {#if problem}<p class="problem" role="alert">{problem}</p>{/if}
      {#if notice}<p class="notice" role="status">{notice}</p>{/if}

      <button type="button" class="switch" onclick={resend}>Send the link again</button>
      <button type="button" class="switch" onclick={startOver}>Use a different address</button>
    </div>
  </main>
{:else}
  <main class="surface gate">
    <form class="card" onsubmit={submit}>
      <h1 class="wordmark">Blurt!</h1>
      <p class="muted">
        {mode === 'in'
          ? 'Sign in to host a room or edit your quizzes.'
          : mode === 'reset'
            ? 'We will email you a link to set a new password.'
            : 'Create a teacher account.'}
      </p>
      {#if wanted && mode !== 'reset'}
        <div class="wanted">
          <p>
            <strong>Teacher plan.</strong>
            {mode === 'up' ? 'Create your account, then pay on the next screen.' : 'Sign in, then pay on the next screen.'}
          </p>
          <div class="seg" role="group" aria-label="Billing period">
            <button type="button" aria-pressed={wanted === 'month'} onclick={() => bill('month')}>$8 a month</button>
            <button type="button" aria-pressed={wanted === 'year'} onclick={() => bill('year')}>$72 a year</button>
          </div>
          <p class="saving" class:saved={wanted === 'year'}>
            {#if wanted === 'year'}
              You save $24 a year: it works out to $6 a month.
            {:else}
              Twelve months this way is $96. Yearly is $72, which saves you $24.
              <button type="button" class="inline" onclick={() => bill('year')}>Switch to yearly</button>
            {/if}
          </p>
        </div>
      {/if}

      <label for="auth-email">Email</label>
      <input id="auth-email" type="email" bind:value={email} autocomplete="email" required />

      {#if mode !== 'reset'}
        <label for="auth-password">Password</label>
        <div class="reveal">
          <input
            id="auth-password"
            type={shown ? 'text' : 'password'}
            bind:value={password}
            autocomplete={mode === 'in' ? 'current-password' : 'new-password'}
            minlength="8"
            required
          />
          <button
            type="button"
            class="peek"
            aria-controls="auth-password"
            aria-pressed={shown}
            onclick={() => (shown = !shown)}
          >
            {shown ? 'Hide' : 'Show'}
          </button>
        </div>
      {/if}

      <button type="submit" disabled={busy}>
        {busy ? '…' : mode === 'in' ? 'Sign in' : mode === 'reset' ? 'Email me a link' : 'Create account'}
      </button>

      {#if mode === 'in'}
        <button
          type="button"
          class="switch"
          onclick={() => {
            mode = 'reset'
            problem = ''
            notice = ''
          }}
        >
          Forgot your password?
        </button>
      {/if}

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

      <p class="muted small">Students don't need any of this — they join at <a href="/join">the front door</a>.</p>
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

  h2 {
    font-size: 22px;
    text-align: center;
  }

  .muted {
    margin: 0 0 8px;
    color: var(--ink-muted);
    text-align: center;
  }

  .wanted {
    display: grid;
    gap: 8px;
    margin: 0 0 8px;
    padding: 12px;
    border: 1px solid var(--line-strong);
    border-radius: 8px;
    font-size: 14px;
    line-height: 1.5;
    text-align: center;
  }

  .wanted p {
    margin: 0;
  }

  .wanted.solo {
    display: block;
  }

  .seg {
    display: grid;
    grid-template-columns: 1fr 1fr;
    padding: 3px;
    border: 1px solid var(--line);
    border-radius: var(--radius-pill);
  }

  .seg button {
    padding: 8px 0;
    border-radius: var(--radius-pill);
    color: var(--ink-muted);
    font-size: 14px;
  }

  .seg button[aria-pressed='true'] {
    background: var(--stage-high);
    color: var(--ink);
    font-weight: 600;
  }

  .saving {
    color: var(--ink-muted);
    font-size: 13px;
  }

  /* Ink, not the green used for borders: at this size the green is too faint
     to read on the light theme. */
  .saving.saved {
    color: var(--ink);
    font-weight: 600;
  }

  .inline {
    color: var(--ink);
    font-size: inherit;
    font-weight: 600;
    text-decoration: underline;
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

  .reveal {
    position: relative;
  }

  .reveal input {
    padding-right: 72px;
  }

  .peek {
    position: absolute;
    inset: 2px 2px 2px auto;
    padding: 0 14px;
    border-radius: var(--radius-md);
    color: var(--ink-muted);
    font-size: 12px;
    letter-spacing: 0.18em;
    text-transform: uppercase;
  }

  .peek:hover {
    color: var(--ink);
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
