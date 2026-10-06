<script>
  // Plan & billing: what the teacher is on, how much of it is used, and the
  // way to Stripe. Paying, changing card and cancelling all happen on Stripe's
  // pages; this sheet only knows which one to send them to.
  import { billing, openPortal, refreshPlan, startCheckout } from '../lib/billing.svelte.js'

  let dialog = $state()
  let note = $state('')
  let problem = $state('')
  let busy = $state(false)
  let yearly = $state(false)

  let plan = $derived(billing.plan)
  let paid = $derived(plan?.plan === 'teacher')

  /** Open the sheet, with an optional line saying why it opened. */
  export function show(why = '', { failed = false } = {}) {
    note = failed ? '' : why
    problem = failed ? why : ''
    if (!dialog.open) dialog.showModal()
    refreshPlan().catch((error) => (problem ||= error.message))
  }

  async function go(trip) {
    if (busy) return
    busy = true
    problem = ''
    try {
      // Stays busy on success: the page is on its way to Stripe.
      if (await trip()) {
        await refreshPlan()
        note = 'You are already on the Teacher plan.'
        busy = false
      }
    } catch (error) {
      problem = error.message
      busy = false
    }
  }

  const upgrade = () => go(() => startCheckout(yearly ? 'year' : 'month'))
  const manage = () => go(() => openPortal().then(() => false))

  const day = (iso) =>
    new Date(iso).toLocaleDateString(undefined, { day: 'numeric', month: 'long', year: 'numeric' })
  const of = (used, limit) => (limit == null ? `${used}` : `${used} of ${limit}`)
</script>

<!-- A click on the backdrop lands on the dialog itself, never on its contents. -->
<dialog bind:this={dialog} aria-labelledby="plan-title" onclick={(e) => e.target === dialog && dialog.close()}>
  <div class="sheet">
    <h2 id="plan-title">Plan &amp; billing</h2>

    {#if note}<p class="notice" role="status">{note}</p>{/if}
    {#if problem}<p class="problem" role="alert">{problem}</p>{/if}

    {#if !plan}
      <p class="muted">…</p>
    {:else}
      <div class="current">
        <span class="eyebrow">Your plan</span>
        <strong class="name">{paid ? 'Teacher' : 'Free'}</strong>
        <span class="muted">
          {#if !paid}
            {plan.room_limit} full games with your class, to see blurt in action.
          {:else if plan.comp && !plan.status}
            On the house. Nothing to pay.
          {:else if plan.status === 'past_due'}
            Your last payment did not go through.
          {:else if plan.cancel_at_period_end && plan.current_period_end}
            Ends on {day(plan.current_period_end)}.
          {:else if plan.current_period_end}
            {plan.billing_interval === 'year' ? '$72 a year' : '$8 a month'} · renews {day(plan.current_period_end)}
          {/if}
        </span>
      </div>

      {#if paid && plan.status === 'past_due'}
        <p class="problem">
          Update your card under Manage billing to keep the Teacher plan. A room that is already open is not affected.
        </p>
      {:else if paid && plan.cancel_at_period_end}
        <p class="muted small">
          After that you are on Free. Nothing is deleted: your quizzes and reports stay, and come back in full if you
          return.
        </p>
      {/if}

      <dl>
        {#if plan.room_limit != null}
          <div><dt>Games played</dt><dd>{of(Math.min(plan.rooms_used, plan.room_limit), plan.room_limit)}</dd></div>
        {/if}
        <div><dt>Quizzes</dt><dd>{of(plan.quizzes, plan.quiz_limit)}</dd></div>
        <div><dt>Students in a room</dt><dd>up to {plan.player_limit}</dd></div>
        <div><dt>Reports</dt><dd>{plan.report_days == null ? 'kept for good' : `last ${plan.report_days} days`}</dd></div>
        <div><dt>Paired displays</dt><dd>up to {plan.display_limit}</dd></div>
        <div><dt>Spreadsheet export</dt><dd>{paid ? 'yes' : 'no'}</dd></div>
      </dl>

      {#if !paid}
        <div class="upgrade">
          <span class="eyebrow">Teacher plan</span>
          <p class="muted small">
            Unlimited games and quizzes, up to 60 students in a room, up to 10 displays, and spreadsheet export.
            Everything you have made so far comes with you.
          </p>
          <div class="seg" role="group" aria-label="Billing period">
            <button aria-pressed={!yearly} onclick={() => (yearly = false)}>$8 a month</button>
            <button aria-pressed={yearly} onclick={() => (yearly = true)}>$72 a year</button>
          </div>
        </div>
      {/if}

      <div class="actions">
        <button type="button" class="quiet" onclick={() => dialog.close()}>Close</button>
        {#if !paid}
          <button type="button" class="primary" disabled={busy} onclick={upgrade}>
            {busy ? 'On to payment…' : 'Upgrade to Teacher'}
          </button>
        {:else if plan.has_customer && plan.status}
          <button type="button" class="primary" disabled={busy} onclick={manage}>
            {busy ? 'Opening…' : 'Manage billing'}
          </button>
        {/if}
      </div>
      {#if !paid}<p class="muted small fine">Payment is taken by Stripe. Cancel any time.</p>{/if}
    {/if}
  </div>
</dialog>

<style>
  dialog {
    width: min(440px, calc(100vw - 32px));
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
    gap: 14px;
    padding: 22px;
  }

  h2 {
    font-size: 20px;
  }

  .current {
    display: grid;
    gap: 2px;
  }

  .name {
    font-family: var(--display);
    font-size: 28px;
    font-weight: 400;
    letter-spacing: 0.02em;
    text-transform: uppercase;
  }

  .muted {
    margin: 0;
    color: var(--ink-muted);
  }

  .small {
    font-size: 13px;
    line-height: 1.5;
  }

  .fine {
    text-align: right;
  }

  dl {
    display: grid;
    margin: 0;
    border: 1px solid var(--line);
    border-radius: var(--radius-md);
  }

  dl div {
    display: flex;
    justify-content: space-between;
    gap: 16px;
    padding: 9px 12px;
    font-size: 14px;
  }

  dl div + div {
    border-top: 1px solid var(--line);
  }

  dt {
    color: var(--ink-muted);
  }

  dd {
    margin: 0;
    font-weight: 500;
    font-variant-numeric: tabular-nums;
  }

  .upgrade {
    display: grid;
    gap: 8px;
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

  .actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }

  .primary {
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
    line-height: 1.5;
  }

  .notice {
    border-color: var(--correct);
  }
</style>
