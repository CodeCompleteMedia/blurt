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
  const of = (used, limit) => `${used} of ${limit}`

  // What the Teacher plan allows, for the comparison a Free teacher sees. The
  // database (plan_limits) is what enforces these; this is only the brochure,
  // like the prices beside it.
  const TEACHER = { students: 60, displays: 10 }
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
            {plan.room_limit} full games with your class, to see Blurt in action.
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

      {#if paid}
        <dl>
          <div><dt>Games</dt><dd>Unlimited</dd></div>
          <div><dt>Quizzes</dt><dd>Unlimited</dd></div>
          <div><dt>Students in a room</dt><dd>Up to {plan.player_limit}</dd></div>
          <div><dt>Reports</dt><dd>Kept for good</dd></div>
          <div><dt>Paired displays</dt><dd>Up to {plan.display_limit}</dd></div>
          <div><dt>Spreadsheet export</dt><dd>Yes</dd></div>
        </dl>
      {:else}
        <!-- Side by side, so the upgrade is read as what changes, with the
             teacher's own numbers on the left where they can see what is used up. -->
        <table>
          <thead>
            <tr>
              <td></td>
              <th scope="col">Free <span class="you">you</span></th>
              <th scope="col" class="teacher">Teacher</th>
            </tr>
          </thead>
          <tbody>
            <tr class:spent={plan.rooms_used >= plan.room_limit}>
              <th scope="row">Games</th>
              <td>{of(Math.min(plan.rooms_used, plan.room_limit), plan.room_limit)}</td>
              <td class="teacher">Unlimited</td>
            </tr>
            <tr class:spent={plan.quizzes >= plan.quiz_limit}>
              <th scope="row">Quizzes</th>
              <td>{of(plan.quizzes, plan.quiz_limit)}</td>
              <td class="teacher">Unlimited</td>
            </tr>
            <tr>
              <th scope="row">Students in a room</th>
              <td>Up to {plan.player_limit}</td>
              <td class="teacher">Up to {TEACHER.students}</td>
            </tr>
            <tr>
              <th scope="row">Paired displays</th>
              <td>{plan.display_limit}</td>
              <td class="teacher">Up to {TEACHER.displays}</td>
            </tr>
            <tr>
              <th scope="row">Spreadsheet export</th>
              <td>No</td>
              <td class="teacher">Yes</td>
            </tr>
          </tbody>
        </table>
        <p class="muted small">Everything you have made so far comes with you.</p>

        <div class="seg" role="group" aria-label="Billing period">
          <button aria-pressed={!yearly} onclick={() => (yearly = false)}>$8 a month</button>
          <button aria-pressed={yearly} onclick={() => (yearly = true)}>$72 a year <span class="save">save 25%</span></button>
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

  table {
    width: 100%;
    border-collapse: separate;
    border-spacing: 0;
    border: 1px solid var(--line);
    border-radius: var(--radius-md);
    font-size: 14px;
    font-variant-numeric: tabular-nums;
  }

  table th,
  table td {
    padding: 9px 12px;
    text-align: left;
  }

  tbody th,
  tbody td {
    border-top: 1px solid var(--line);
  }

  tbody th {
    color: var(--ink-muted);
    font-weight: 400;
  }

  thead th {
    font-size: 12px;
    letter-spacing: 0.14em;
    text-transform: uppercase;
  }

  /* The column being offered carries the brand colour, top to bottom. */
  .teacher {
    background: color-mix(in oklab, var(--neon-pink) 10%, transparent);
    font-weight: 600;
  }

  thead .teacher {
    border-top-right-radius: var(--radius-md);
    color: var(--neon-pink);
  }

  tbody tr:last-child .teacher {
    border-bottom-right-radius: var(--radius-md);
  }

  /* A limit that has been reached is the reason they are here. */
  .spent td:not(.teacher) {
    color: var(--wrong);
    font-weight: 600;
  }

  .you {
    margin-left: 4px;
    padding: 1px 6px;
    border: 1px solid var(--line-strong);
    border-radius: var(--radius-pill);
    color: var(--ink-muted);
    font-size: 10px;
    letter-spacing: 0.1em;
  }

  .save {
    margin-left: 4px;
    font-size: 11px;
    font-weight: 400;
    opacity: 0.8;
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
