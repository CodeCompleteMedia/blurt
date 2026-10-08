<script>
  // The frame around everything a teacher does. Three places — the room, the
  // quizzes, what the last class knew — and who is signed in.
  //
  // The wall and the phone deliberately get none of this. A projector with a menu
  // bar is a projector with something to fiddle with, and a student's screen has
  // exactly one job at a time.
  import { amAdmin } from '../lib/admin.js'
  import { auth, setPassword, signOut } from '../lib/auth.svelte.js'
  import {
    billing,
    claimCheckout,
    forgetIntent,
    onShowPlan,
    peekIntent,
    refreshPlan,
    refreshPlanFromStripeIfStale,
    releaseCheckout,
    startCheckout,
    syncPlan,
  } from '../lib/billing.svelte.js'
  import { readHost } from '../lib/session.js'
  import { setTheme, theme } from '../lib/theme.svelte.js'
  import PlanSheet from './PlanSheet.svelte'

  let { current, children } = $props()

  // A room keeps running while its teacher is off editing a quiz — but it stops
  // advancing itself, because the host screen is what closes questions on time.
  // So a live room is never out of sight: it rides along in the bar.
  const room = current === 'host' ? null : readHost()

  // Only admins see the link. Hiding it is courtesy, not security: the page's
  // every read is refused by the database to anyone else.
  let admin = $state(false)
  // The id, not the user object: a token refresh hands back a new object, and
  // this should ask once per person, not once per refresh.
  let userId = $derived(auth.user?.id ?? null)
  $effect(() => {
    if (!userId) return
    amAdmin().then((yes) => (admin = yes))
  })

  // Plan & billing, and the two ways a teacher arrives with billing on their
  // mind: from the pricing page wanting the Teacher plan (an intent, carried
  // through sign-up), or back from one of Stripe's pages (?billing=...).
  let planSheet = $state()
  const back = new URLSearchParams(window.location.search).get('billing')
  const wanted = back ? null : peekIntent()
  const intent = wanted && claimCheckout() ? wanted : null
  // Decided before the first paint, so a teacher on their way to Checkout sees
  // that, and not a flash of the room they have not paid for yet.
  let paying = $state(Boolean(intent))
  // Not state on purpose: if this effect ever runs twice, the second run must
  // not start a second Checkout or reopen the sheet.
  let arrived = false

  $effect(() => {
    if (!userId || arrived) return
    arrived = true
    onShowPlan((note) => planSheet?.show(note))

    // Spent once: a refresh must not send anyone to Checkout a second time.
    forgetIntent()
    if (back) releaseCheckout()
    if (back || wanted) history.replaceState(null, '', window.location.pathname + window.location.hash)

    if (intent) {
      startCheckout(intent)
        .then((already) => {
          if (!already) return
          paying = false
          planSheet?.show('You are already on the Teacher plan.')
        })
        .catch((error) => {
          paying = false
          planSheet?.show(error.message, { failed: true })
        })
    } else if (back === 'cancelled') {
      planSheet?.show('No payment was taken. You are on the Free plan, and can upgrade from here whenever you like.')
    } else if (back) {
      // Do not wait on the webhook: ask the server to read Stripe now, so the
      // first screen after paying already has the plan.
      syncPlan()
        .catch(() => refreshPlan())
        .then((plan) => {
          if (back === 'done') {
            planSheet?.show(
              plan?.plan === 'teacher'
                ? 'Thank you. You are on the Teacher plan.'
                : 'Your payment is still being confirmed. This usually takes a few seconds: close this and open Plan & billing again.',
            )
          }
        })
        .catch(() => {})
    } else {
      refreshPlanFromStripeIfStale().catch(() => {})
    }
  })

  async function leave() {
    await signOut()
    window.location.assign('/')
  }

  // The account menu. A plain disclosure rather than an ARIA menu: a handful of
  // links and buttons that Tab already walks, with Escape and a click elsewhere
  // to put it away.
  let open = $state(false)
  let menu = $state()
  let trigger = $state()

  function dismiss(event) {
    if (open && !menu?.contains(event.target)) open = false
  }

  function onkeydown(event) {
    if (open && event.key === 'Escape') {
      open = false
      trigger?.focus()
    }
  }

  // Changing the password while signed in — the same call the recovery link
  // ends in, without the email round trip.
  let changing = $state()
  let password = $state('')
  let again = $state('')
  let busy = $state(false)
  let problem = $state('')
  let changed = $state(false)

  function changePassword() {
    open = false
    password = ''
    again = ''
    problem = ''
    changed = false
    changing.showModal()
  }

  async function savePassword(event) {
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
      changed = true
    } catch (error) {
      problem = error.message
    } finally {
      busy = false
    }
  }
</script>

<div class="shell">
  <nav aria-label="Teacher">
    <a class="wordmark brand" href="/host">Blurt!</a>

    <div class="places">
      <a href="/host" aria-current={current === 'host' ? 'page' : undefined}>
        Room
        {#if room?.code}<span class="live" title="A room is still open">{room.code}</span>{/if}
      </a>
      <a href="/edit" aria-current={current === 'edit' ? 'page' : undefined}>Quizzes</a>
      <a href="/games" aria-current={current === 'games' ? 'page' : undefined}>Reports</a>
      {#if admin}<a href="/admin" aria-current={current === 'admin' ? 'page' : undefined}>Admin</a>{/if}
    </div>

    <div class="who" bind:this={menu}>
      <button
        class="account"
        bind:this={trigger}
        aria-expanded={open}
        aria-controls="account-menu"
        aria-label="Account"
        onclick={() => (open = !open)}
      >
        <span class="initial" aria-hidden="true">{(auth.user?.email ?? '?')[0].toUpperCase()}</span>
        <span class="chevron" aria-hidden="true">▾</span>
      </button>

      {#if open}
        <div class="menu" id="account-menu">
          <div class="signed-in">
            <span class="eyebrow">Signed in as</span>
            <span class="address">{auth.user?.email}</span>
          </div>

          <div class="group">
            <button
              class="item plan-item"
              onclick={() => {
                open = false
                planSheet.show()
              }}
            >
              Plan &amp; billing
              {#if billing.plan}<span class="plan-pill">{billing.plan.plan === 'teacher' ? 'Teacher' : 'Free'}</span>{/if}
            </button>
            <button class="item" onclick={changePassword}>Change password</button>
            <a class="item" href="/join" target="_blank" rel="noopener">Student join page ↗</a>
          </div>

          <div class="group theme" role="group" aria-labelledby="theme-label">
            <span class="eyebrow" id="theme-label">Appearance</span>
            <div class="seg">
              <button aria-pressed={theme.mode === 'dark'} onclick={() => setTheme('dark')}>Dark</button>
              <button aria-pressed={theme.mode === 'light'} onclick={() => setTheme('light')}>Light</button>
            </div>
          </div>

          <div class="group">
            <button class="item" onclick={leave}>Sign out</button>
          </div>
        </div>
      {/if}
    </div>
  </nav>

  <div class="content">
    {#if paying}
      <p class="paying" role="status">On to payment…</p>
    {:else}
      {@render children()}
    {/if}
  </div>
</div>

<PlanSheet bind:this={planSheet} />

<svelte:window onclick={dismiss} {onkeydown} />

<!-- A click on the backdrop lands on the dialog itself, never on its contents. -->
<dialog
  bind:this={changing}
  aria-labelledby="change-title"
  onclick={(e) => e.target === changing && changing.close()}
>
  <form class="sheet" onsubmit={savePassword}>
    <h2 id="change-title">Change password</h2>

    {#if changed}
      <p class="notice" role="status">Done. Use the new one next time you sign in.</p>
      <button type="button" class="primary" onclick={() => changing.close()}>Close</button>
    {:else}
      <label for="change-password">New password</label>
      <input
        id="change-password"
        type="password"
        bind:value={password}
        autocomplete="new-password"
        minlength="8"
        required
      />

      <label for="change-password-again">New password again</label>
      <input
        id="change-password-again"
        type="password"
        bind:value={again}
        autocomplete="new-password"
        minlength="8"
        required
      />

      {#if problem}<p class="problem" role="alert">{problem}</p>{/if}

      <div class="actions">
        <button type="button" class="quiet" onclick={() => changing.close()}>Cancel</button>
        <button type="submit" class="primary" disabled={busy}>{busy ? '…' : 'Save password'}</button>
      </div>
    {/if}
  </form>
</dialog>

<style>
  .shell {
    display: grid;
    grid-template-rows: auto minmax(0, 1fr);
    height: 100%;
  }

  nav {
    display: flex;
    align-items: center;
    gap: 8px 20px;
    /* Lines up with the gutter every surface uses, notch included. */
    padding: 10px calc(var(--gutter) + env(safe-area-inset-right, 0px)) 10px
      calc(var(--gutter) + env(safe-area-inset-left, 0px));
    padding-top: calc(10px + env(safe-area-inset-top, 0px));
    border-bottom: 1px solid var(--line);
    background: var(--stage-raised);
  }

  /* Face, colour and glow come from .wordmark — this only sizes it. The hand
     rolled copy that used to live here glowed at 1/8/— against the token's
     2/14/40, so the nav sign was dimmer than every other one in the product. */
  .brand {
    font-size: 24px;
    line-height: 1;
    text-transform: uppercase;
    text-decoration: none;
  }

  .places {
    display: flex;
    gap: 4px;
  }

  .places a {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 7px 14px;
    border-radius: 999px;
    color: var(--ink-muted);
    font-size: 14px;
    font-weight: 500;
    text-decoration: none;
  }

  .places a:hover {
    color: var(--ink);
  }

  .places a[aria-current='page'] {
    background: var(--stage-high);
    color: var(--ink);
  }

  .live {
    padding: 1px 8px;
    border-radius: 999px;
    background: rgba(255, 46, 151, 0.16);
    color: var(--neon-pink);
    font-size: 11px;
    letter-spacing: 0.1em;
  }

  .who {
    margin-left: auto;
    display: flex;
    align-items: center;
    gap: 12px;
    min-width: 0;
  }

  .who {
    position: relative;
  }

  .account {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 3px 10px 3px 3px;
    border: 1px solid var(--line);
    border-radius: var(--radius-pill);
    color: var(--ink-muted);
  }

  .account:hover,
  .account[aria-expanded='true'] {
    border-color: var(--line-strong);
    color: var(--ink);
  }

  .initial {
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    border-radius: 50%;
    background: var(--neon-pink);
    color: var(--on-pink);
    font-family: var(--display);
    font-size: 13px;
  }

  .chevron {
    font-size: 11px;
  }

  .menu {
    position: absolute;
    top: calc(100% + 8px);
    right: 0;
    z-index: 20;
    display: grid;
    width: 260px;
    max-width: calc(100vw - 2 * var(--gutter));
    border: 1px solid var(--line-strong);
    border-radius: var(--radius-lg);
    background: var(--stage-raised);
    box-shadow: 0 16px 40px rgba(0, 0, 0, 0.35);
    overflow: hidden;
  }

  .signed-in {
    display: grid;
    gap: 2px;
    padding: 14px 16px 12px;
  }

  .address {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 14px;
    font-weight: 500;
  }

  .group {
    display: grid;
    padding: 6px;
    border-top: 1px solid var(--line);
  }

  .item {
    display: block;
    padding: 9px 10px;
    border-radius: var(--radius-sm);
    color: var(--ink);
    font-size: 14px;
    text-align: left;
    text-decoration: none;
  }

  .item:hover {
    background: var(--stage-high);
  }

  .plan-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .plan-pill {
    padding: 1px 8px;
    border: 1px solid var(--line-strong);
    border-radius: var(--radius-pill);
    color: var(--ink-muted);
    font-size: 11px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
  }

  .paying {
    display: grid;
    place-items: center;
    height: 100%;
    margin: 0;
    color: var(--ink-muted);
  }

  .theme {
    gap: 8px;
    padding: 10px 16px 12px;
  }

  .seg {
    display: grid;
    grid-template-columns: 1fr 1fr;
    padding: 3px;
    border: 1px solid var(--line);
    border-radius: var(--radius-pill);
  }

  .seg button {
    padding: 6px 0;
    border-radius: var(--radius-pill);
    color: var(--ink-muted);
    font-size: 13px;
  }

  .seg button[aria-pressed='true'] {
    background: var(--stage-high);
    color: var(--ink);
    font-weight: 600;
  }

  dialog {
    width: min(400px, calc(100vw - 32px));
    padding: 0;
    border: 1px solid var(--line-strong);
    border-radius: var(--radius-lg);
    background: var(--stage-raised);
    color: var(--ink);
  }

  dialog::backdrop {
    background: rgba(11, 7, 22, 0.72);
  }

  .sheet {
    display: grid;
    gap: 10px;
    padding: 22px;
  }

  .sheet h2 {
    margin-bottom: 6px;
    font-size: 20px;
  }

  .sheet label {
    font-size: 12px;
    letter-spacing: 0.18em;
    text-transform: uppercase;
    color: var(--ink-muted);
  }

  .sheet input {
    width: 100%;
    min-width: 0;
    padding: 12px;
    border: 2px solid var(--line-strong);
    border-radius: var(--radius-md);
    background: var(--stage);
    color: var(--ink);
    font: inherit;
  }

  .sheet input:focus {
    border-color: var(--neon-cyan);
  }

  .actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    margin-top: 6px;
  }

  .primary {
    justify-self: end;
    padding: 10px 16px;
    border-radius: 8px;
    background: var(--neon-pink);
    color: var(--on-pink);
    font-weight: 600;
  }

  .primary:disabled {
    background: var(--stage-high);
    color: var(--ink-muted);
  }

  .quiet {
    padding: 10px 14px;
    border: 1px solid var(--line);
    border-radius: 8px;
    color: var(--ink);
  }

  .problem,
  .notice {
    margin: 0;
    padding: 10px 12px;
    border: 1px solid var(--wrong);
    border-radius: 8px;
    font-size: 14px;
  }

  .notice {
    border-color: var(--correct);
  }

  /* The editor is longer than a screen; the room is sized to fit one. Either way
     the bar stays put and only this scrolls. */
  .content {
    overflow: auto;
  }

  @media (max-width: 560px) {
    nav {
      gap: 8px 10px;
    }
  }
</style>
