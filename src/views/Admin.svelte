<script>
  // The platform admin's view across every teacher: who signed up, who is using
  // it, and the two things only an admin can do to an account. Every number and
  // every action here is checked against the admin list in the database; this
  // page only asks. Students appear as counts, never as names or answers.
  import {
    adminOverview,
    adminSignups,
    adminTeachers,
    amAdmin,
    deleteTeacher,
    suspendTeacher,
  } from '../lib/admin.js'

  let allowed = $state(null) // null while asking
  let loading = $state(true)
  let problem = $state('')
  let overview = $state(null)
  let signups = $state([])
  let teachers = $state([])
  let loadedAt = $state(null)

  let search = $state('')
  let busy = $state(null) // the user id an action is running on
  let armed = $state(null) // a suspend waiting for its second click
  let deleting = $state(null) // the row whose delete form is open
  let confirmText = $state('')
  let notice = $state('')

  async function load() {
    loading = true
    problem = ''
    try {
      ;[overview, signups, teachers] = await Promise.all([
        adminOverview(),
        adminSignups(30),
        adminTeachers(),
      ])
      loadedAt = new Date()
    } catch (error) {
      problem = error.message
    } finally {
      loading = false
    }
  }

  $effect(() => {
    void (async () => {
      allowed = await amAdmin()
      if (allowed) await load()
      else loading = false
    })()
  })

  const day = (iso) =>
    iso ? new Date(iso).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' }) : '—'
  const shortDay = (d) => new Date(`${d}T00:00:00`).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })
  const n = (v) => (v ?? 0).toLocaleString()

  let shown = $derived(
    search.trim()
      ? teachers.filter((t) => t.email?.toLowerCase().includes(search.trim().toLowerCase()))
      : teachers,
  )

  // ---------------------------------------------------------------- chart --
  let peak = $derived(Math.max(1, ...signups.map((s) => s.signups)))
  let total30 = $derived(signups.reduce((a, s) => a + s.signups, 0))
  let hovered = $state(null)
  const W = 600
  const H = 160
  const GAP = 2

  // --------------------------------------------------------------- actions --
  let disarm
  function arm(id) {
    armed = id
    clearTimeout(disarm)
    disarm = setTimeout(() => (armed = null), 3000)
  }

  async function toggleSuspend(t) {
    if (!t.suspended && armed !== t.user_id) return arm(t.user_id)
    armed = null
    busy = t.user_id
    notice = ''
    try {
      await suspendTeacher(t.user_id, !t.suspended)
      notice = t.suspended ? `${t.email} can sign in again.` : `${t.email} is suspended and signed out.`
      teachers = await adminTeachers()
    } catch (error) {
      notice = error.message
    } finally {
      busy = null
    }
  }

  function openDelete(t) {
    deleting = deleting === t.user_id ? null : t.user_id
    confirmText = ''
  }

  async function confirmDelete(t) {
    if (confirmText.trim().toLowerCase() !== t.email?.toLowerCase()) return
    busy = t.user_id
    notice = ''
    try {
      await deleteTeacher(t.user_id)
      notice = `${t.email} and everything they made has been deleted.`
      deleting = null
      await load()
    } catch (error) {
      notice = error.message
    } finally {
      busy = null
    }
  }
</script>

<main class="surface admin">
  {#if allowed === null || (allowed && loading && !overview)}
    <p class="muted">…</p>
  {:else if !allowed}
    <div class="refused">
      <h1>Admin</h1>
      <p class="muted">This page is for platform admins.</p>
    </div>
  {:else}
    <header>
      <h1>Admin</h1>
      <span class="muted">
        {#if loadedAt}As of {loadedAt.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}{/if}
      </span>
      <button class="ghost" onclick={load} disabled={loading}>{loading ? 'Refreshing…' : 'Refresh'}</button>
    </header>

    {#if problem}<p class="problem" role="alert">{problem}</p>{/if}

    {#if overview}
      <section aria-labelledby="usage-title">
        <h2 id="usage-title">Usage</h2>
        <div class="scroll">
          <table class="usage">
            <thead>
              <tr><th></th><th class="r">7 days</th><th class="r">30 days</th><th class="r">All time</th></tr>
            </thead>
            <tbody>
              <tr>
                <th scope="row">New teachers</th>
                <td class="r bulbs">{n(overview.signups_7d)}</td>
                <td class="r bulbs">{n(overview.signups_30d)}</td>
                <td class="r bulbs">{n(overview.teachers)}</td>
              </tr>
              <tr>
                <th scope="row">Teachers who hosted a room</th>
                <td class="r bulbs">{n(overview.active_7d)}</td>
                <td class="r bulbs">{n(overview.active_30d)}</td>
                <td class="r muted">—</td>
              </tr>
              <tr>
                <th scope="row">Rooms run</th>
                <td class="r bulbs">{n(overview.rooms_7d)}</td>
                <td class="r bulbs">{n(overview.rooms_30d)}</td>
                <td class="r bulbs">{n(overview.rooms_total)}</td>
              </tr>
              <tr>
                <th scope="row">Students who joined</th>
                <td class="r bulbs">{n(overview.students_7d)}</td>
                <td class="r bulbs">{n(overview.students_30d)}</td>
                <td class="r bulbs">{n(overview.students_total)}</td>
              </tr>
              <tr>
                <th scope="row">Answers given</th>
                <td class="r muted">—</td>
                <td class="r muted">—</td>
                <td class="r bulbs">{n(overview.answers_total)}</td>
              </tr>
              <tr>
                <th scope="row">Quizzes</th>
                <td class="r muted">—</td>
                <td class="r muted">—</td>
                <td class="r bulbs">{n(overview.quizzes_total)}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="note">
          {n(overview.confirmed)} of {n(overview.teachers)} teachers have confirmed their email. Student
          numbers are counts only; names and answers are not shown here.
        </p>
      </section>

      <section aria-labelledby="signups-title">
        <h2 id="signups-title">New teachers per day</h2>
        <p class="sub">Last 30 days · {n(total30)} in total</p>

        <div class="chart">
          <svg viewBox="0 0 {W} {H + 22}" role="img" aria-label="New teachers per day over the last 30 days, {total30} in total">
            <line class="grid" x1="0" x2={W} y1={0.5} y2={0.5} />
            <line class="grid" x1="0" x2={W} y1={H / 2} y2={H / 2} />
            <line class="base" x1="0" x2={W} y1={H} y2={H} />
            {#each signups as s, i (s.day)}
              {@const slot = W / signups.length}
              {@const h = Math.max(4, (s.signups / peak) * (H - 6))}
              <g
                class="slot"
                class:on={hovered === i}
                onpointerenter={() => (hovered = i)}
                onpointerleave={() => (hovered = null)}
                role="presentation"
              >
                <rect class="hit" x={i * slot} y="0" width={slot} height={H} />
                {#if s.signups > 0}
                  <path
                    class="bar"
                    d="M{i * slot + GAP / 2} {H} v{-(h - 4)} q0 -4 4 -4 h{slot - GAP - 8} q4 0 4 4 v{h - 4} z"
                  />
                {/if}
              </g>
            {/each}
            <text class="tick" x="0" y={H + 16}>{signups.length ? shortDay(signups[0].day) : ''}</text>
            <text class="tick end" x={W} y={H + 16}>Today</text>
            <text class="tick" x="4" y="12">{peak}</text>
          </svg>
          {#if hovered !== null && signups[hovered]}
            <div class="tip" style="left: {((hovered + 0.5) / signups.length) * 100}%" aria-hidden="true">
              <strong>{signups[hovered].signups}</strong>
              {signups[hovered].signups === 1 ? 'teacher' : 'teachers'} · {shortDay(signups[hovered].day)}
            </div>
          {/if}
        </div>

        <details>
          <summary>Show the numbers</summary>
          <table class="days">
            <thead><tr><th>Day</th><th class="r">New teachers</th></tr></thead>
            <tbody>
              {#each [...signups].reverse() as s (s.day)}
                <tr><td>{shortDay(s.day)}</td><td class="r">{s.signups}</td></tr>
              {/each}
            </tbody>
          </table>
        </details>
      </section>

      <section aria-labelledby="billing-title">
        <h2 id="billing-title">Plans and payments</h2>
        <p class="note">
          Each teacher's plan, trial and payment status will appear in the table below once billing is
          built (Phase 2 of the subscription plan). Refunds, invoices and card details stay in the
          payment provider's own dashboard.
        </p>
      </section>

      <section aria-labelledby="teachers-title">
        <div class="table-head">
          <h2 id="teachers-title">Teachers</h2>
          <input
            class="search"
            type="search"
            bind:value={search}
            placeholder="Search by email"
            aria-label="Search teachers by email"
          />
        </div>

        {#if notice}<p class="notice" role="status">{notice}</p>{/if}

        <div class="scroll">
          <table class="teachers">
            <thead>
              <tr>
                <th>Email</th>
                <th>Plan</th>
                <th>Signed up</th>
                <th>Last sign-in</th>
                <th class="r">Quizzes</th>
                <th class="r">Rooms</th>
                <th class="r">Students</th>
                <th>Last room</th>
                <th><span class="sr">Actions</span></th>
              </tr>
            </thead>
            <tbody>
              {#each shown as t (t.user_id)}
                <tr class:suspended={t.suspended}>
                  <td class="email">
                    {t.email}
                    {#if t.is_admin}<span class="pill admin-pill">Admin</span>{/if}
                    {#if t.suspended}<span class="pill out">Suspended</span>{/if}
                    {#if !t.confirmed_at}<span class="pill wait">Unconfirmed</span>{/if}
                  </td>
                  <td class="plan">
                    {#if t.stripe_customer_id}
                      <a
                        href="https://dashboard.stripe.com/customers/{t.stripe_customer_id}"
                        target="_blank"
                        rel="noopener"
                        title="Open this customer in Stripe">{t.plan === 'teacher' ? 'Teacher' : 'Free'} ↗</a
                      >
                    {:else}
                      {t.plan === 'teacher' ? 'Teacher' : 'Free'}
                    {/if}
                    {#if t.plan_comp}<span class="pill wait">Comp</span>{/if}
                    {#if t.plan_status && t.plan_status !== 'active'}<span
                        class="pill"
                        class:out={t.plan_status === 'past_due'}
                        class:wait={t.plan_status !== 'past_due'}>{t.plan_status.replace('_', ' ')}</span
                      >{/if}
                  </td>
                  <td>{day(t.signed_up_at)}</td>
                  <td>{day(t.last_sign_in_at)}</td>
                  <td class="r">{t.quizzes}</td>
                  <td class="r">{t.rooms}</td>
                  <td class="r">{t.students}</td>
                  <td>{day(t.last_room_at)}</td>
                  <td>
                    {#if !t.is_admin}<div class="acts">
                      <button
                        class="link"
                        class:danger={armed === t.user_id}
                        disabled={busy === t.user_id}
                        onclick={() => toggleSuspend(t)}
                      >
                        {t.suspended ? 'Restore' : armed === t.user_id ? 'Suspend now?' : 'Suspend'}
                      </button>
                      <button class="link" disabled={busy === t.user_id} onclick={() => openDelete(t)}>
                        {deleting === t.user_id ? 'Cancel' : 'Delete'}
                      </button>
                    </div>{/if}
                  </td>
                </tr>
                {#if deleting === t.user_id}
                  <tr class="confirm-row">
                    <td colspan="9">
                      <form class="confirm" onsubmit={(e) => { e.preventDefault(); confirmDelete(t) }}>
                        <p>
                          This deletes <strong>{t.email}</strong>, their {t.quizzes}
                          {t.quizzes === 1 ? 'quiz' : 'quizzes'}, {t.rooms}
                          {t.rooms === 1 ? 'room' : 'rooms'} and every answer from {t.students}
                          {t.students === 1 ? 'student' : 'students'}. It cannot be undone. Type their email to
                          confirm.
                        </p>
                        <div class="confirm-row-fields">
                          <input
                            bind:value={confirmText}
                            placeholder={t.email}
                            aria-label="Type {t.email} to confirm"
                            autocomplete="off"
                          />
                          <button
                            type="submit"
                            class="danger-btn"
                            disabled={busy === t.user_id || confirmText.trim().toLowerCase() !== t.email?.toLowerCase()}
                          >
                            {busy === t.user_id ? 'Deleting…' : 'Delete for good'}
                          </button>
                        </div>
                      </form>
                    </td>
                  </tr>
                {/if}
              {:else}
                <tr><td colspan="9" class="muted">No teacher matches “{search}”.</td></tr>
              {/each}
            </tbody>
          </table>
        </div>
        <p class="note">
          Suspending blocks sign-in and ends their sessions; a page they already have open keeps working
          for up to an hour. Question images they uploaded are not removed by Delete.
        </p>
      </section>
    {/if}
  {/if}
</main>

<style>
  .admin {
    display: grid;
    /* One column held to the page width, so a wide table scrolls inside its
       own box instead of stretching the page. */
    grid-template-columns: minmax(0, 1fr);
    align-content: start;
    gap: 36px;
    max-width: 1180px;
    margin: 0 auto;
    width: 100%;
  }

  header {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    gap: 8px 16px;
    padding-bottom: 14px;
    border-bottom: 1px solid var(--line);
  }

  header .muted {
    flex: 1;
  }

  h1 {
    font-size: clamp(26px, 3vw, 34px);
  }

  h2 {
    font-size: 18px;
    margin-bottom: 12px;
  }

  section {
    min-width: 0;
  }

  .muted {
    margin: 0;
    color: var(--ink-muted);
  }

  .sub {
    margin: -6px 0 12px;
    color: var(--ink-muted);
    font-size: 14px;
  }

  .note {
    margin: 10px 0 0;
    max-width: 70ch;
    color: var(--ink-muted);
    font-size: 13.5px;
    line-height: 1.5;
  }

  .refused {
    display: grid;
    gap: 8px;
  }

  .ghost {
    padding: 8px 14px;
    border: 1px solid var(--line);
    border-radius: var(--radius-pill);
    color: var(--ink);
    font-size: 13px;
  }

  .problem,
  .notice {
    margin: 0 0 12px;
    padding: 10px 14px;
    border: 1px solid var(--wrong);
    border-radius: 8px;
    background: var(--stage-raised);
    font-size: 14px;
  }

  .notice {
    border-color: var(--line-strong);
  }

  .scroll {
    /* Positioned, so the visually hidden header label is clipped with the
       table instead of sitting off to the right and widening the page. */
    position: relative;
    overflow-x: auto;
    border: 1px solid var(--line);
    border-radius: var(--radius-md);
    background: var(--stage-raised);
  }

  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 14px;
  }

  th,
  td {
    padding: 10px 14px;
    text-align: left;
    border-bottom: 1px solid var(--line);
    white-space: nowrap;
  }

  thead th {
    color: var(--ink-muted);
    font-size: 11px;
    font-weight: 500;
    letter-spacing: 0.14em;
    text-transform: uppercase;
  }

  tbody tr:last-child > * {
    border-bottom: 0;
  }

  .r {
    text-align: right;
    font-variant-numeric: tabular-nums;
  }

  .usage {
    max-width: 640px;
  }

  .usage tbody th {
    font-weight: 500;
    /* The labels may wrap on a phone; the numbers beside them may not. */
    white-space: normal;
    min-width: 9em;
  }

  .usage .bulbs {
    font-size: 17px;
  }

  /* ----------------------------------------------------------- chart --- */
  .chart {
    position: relative;
    max-width: 760px;
  }

  .chart svg {
    display: block;
    width: 100%;
    height: auto;
    overflow: visible;
  }

  .grid {
    stroke: var(--line);
    stroke-dasharray: 2 4;
  }

  .base {
    stroke: var(--line-strong);
  }

  .hit {
    fill: transparent;
  }

  .bar {
    fill: var(--neon-pink);
  }

  .slot.on .hit {
    fill: var(--stage-high);
  }

  .tick {
    fill: var(--ink-muted);
    font-size: 11px;
  }

  .tick.end {
    text-anchor: end;
  }

  .tip {
    position: absolute;
    top: -6px;
    transform: translate(-50%, -100%);
    padding: 6px 10px;
    border: 1px solid var(--line-strong);
    border-radius: 8px;
    background: var(--stage-raised);
    color: var(--ink);
    font-size: 13px;
    white-space: nowrap;
    pointer-events: none;
  }

  details {
    margin-top: 10px;
    font-size: 14px;
  }

  summary {
    color: var(--ink-muted);
    cursor: pointer;
  }

  .days {
    max-width: 320px;
    margin-top: 8px;
  }

  .days td,
  .days th {
    padding: 4px 10px;
  }

  /* -------------------------------------------------------- teachers --- */
  .table-head {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    justify-content: space-between;
    gap: 8px 16px;
  }

  .search,
  .confirm input {
    padding: 8px 12px;
    border: 1px solid var(--line-strong);
    border-radius: 8px;
    background: var(--stage);
    color: var(--ink);
    font: inherit;
    font-size: 14px;
  }

  .search {
    width: min(100%, 280px);
    margin-bottom: 12px;
  }

  .search:focus,
  .confirm input:focus {
    border-color: var(--neon-cyan);
  }

  .email {
    font-weight: 500;
  }

  .plan {
    white-space: nowrap;
  }

  .plan a {
    color: inherit;
  }

  .pill {
    display: inline-block;
    margin-left: 6px;
    padding: 1px 8px;
    border-radius: 999px;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    vertical-align: 1px;
  }

  .admin-pill {
    background: var(--stage-high);
    color: var(--ink);
  }

  .out {
    background: color-mix(in oklab, var(--wrong) 16%, transparent);
    color: var(--wrong);
  }

  .wait {
    background: var(--stage-high);
    color: var(--ink-muted);
  }

  tr.suspended td {
    color: var(--ink-muted);
  }

  .acts {
    display: flex;
    gap: 4px;
    justify-content: flex-end;
  }

  .link {
    padding: 4px 8px;
    color: var(--ink-muted);
    font-size: 13px;
    text-decoration: underline;
    text-underline-offset: 3px;
  }

  .link:hover:not(:disabled) {
    color: var(--ink);
  }

  .link.danger {
    color: var(--wrong);
    font-weight: 600;
  }

  .confirm-row td {
    white-space: normal;
    background: var(--stage);
  }

  .confirm {
    display: grid;
    gap: 10px;
    max-width: 640px;
  }

  .confirm p {
    margin: 0;
    line-height: 1.5;
  }

  .confirm-row-fields {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }

  .confirm input {
    flex: 1;
    min-width: 200px;
  }

  .danger-btn {
    padding: 8px 14px;
    border-radius: 8px;
    background: var(--wrong);
    color: var(--on-pink);
    font-weight: 600;
  }

  .danger-btn:disabled {
    background: var(--stage-high);
    color: var(--ink-muted);
  }

  .sr {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
  }
</style>
