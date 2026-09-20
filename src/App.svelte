<script>
  import { configured } from './lib/supabase.js'
  import { routeFor } from './lib/router.js'
  import AuthGate from './components/AuthGate.svelte'
  import TeacherShell from './components/TeacherShell.svelte'
  import Edit from './views/Edit.svelte'
  import Games from './views/Games.svelte'
  import Host from './views/Host.svelte'
  import Join from './views/Join.svelte'
  import Play from './views/Play.svelte'
  import Present from './views/Present.svelte'
  import Wall from './views/Wall.svelte'

  const route = routeFor()
</script>

{#if !configured}
  <main class="setup">
    <div>
      <h1 class="wordmark">blurt!</h1>
      <p>
        No database configured. This build is missing
        <code>VITE_SUPABASE_URL</code> and <code>VITE_SUPABASE_ANON_KEY</code>.
      </p>
      <p class="fix">Run <code>vercel env pull .env.local</code>, then restart the dev server.</p>
    </div>
  </main>
{:else if route.view === 'host'}
  <AuthGate>
    <TeacherShell current="host">
      <Host />
    </TeacherShell>
  </AuthGate>
{:else if route.view === 'games'}
  <AuthGate>
    <TeacherShell current="games">
      <Games gameId={route.gameId} />
    </TeacherShell>
  </AuthGate>
{:else if route.view === 'edit'}
  <AuthGate>
    <TeacherShell current="edit">
      <Edit quizId={route.quizId} />
    </TeacherShell>
  </AuthGate>
{:else if route.view === 'present'}
  <Present code={route.code} />
{:else if route.view === 'wall'}
  <Wall wallId={route.wallId} />
{:else if route.view === 'play'}
  <Play />
{:else}
  <Join />
{/if}

<style>
  /* A blank screen in front of a class is the worst possible failure, so an
     unconfigured build says exactly what is missing and how to fix it. */
  .setup {
    display: grid;
    place-items: center;
    height: 100%;
    padding: 24px;
    text-align: center;
  }

  .setup div {
    display: grid;
    gap: 12px;
    max-width: 440px;
  }

  h1 {
    font-size: 56px;
  }

  p {
    margin: 0;
    color: var(--ink-muted);
    line-height: 1.6;
  }

  .fix {
    color: var(--ink);
  }

  code {
    font-family: ui-monospace, Menlo, monospace;
    font-size: 0.9em;
    background: var(--stage-raised);
    padding: 2px 6px;
    border-radius: 4px;
  }
</style>
