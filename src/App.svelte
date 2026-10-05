<script>
  import { configured } from './lib/config.js'
  import { routeFor } from './lib/router.js'
  import { applyTheme, showTheme } from './lib/theme.svelte.js'

  const route = routeFor()

  // Before anything mounts, so the sign-in card is drawn in the chosen light
  // rather than switching under the teacher. The wall and the phones start in
  // the default and follow the room's copy of the teacher's choice once they
  // know which room they are in.
  if (['home', 'host', 'games', 'edit'].includes(route.view)) applyTheme()
  else showTheme('light')

  // Each surface is its own download. A student's phone on school Wi-Fi fetches
  // the join form and the buzzer, not the quiz editor, the reports or the
  // landing page; a first-time visitor to / fetches the landing page and not
  // the database client.
  const views = {
    home: () => import('./views/Landing.svelte'),
    host: () => import('./views/Teacher.svelte'),
    games: () => import('./views/Teacher.svelte'),
    edit: () => import('./views/Teacher.svelte'),
    present: () => import('./views/Present.svelte'),
    wall: () => import('./views/Wall.svelte'),
    play: () => import('./views/Play.svelte'),
    join: () => import('./views/Join.svelte'),
  }

  const props = {
    home: {},
    host: { route },
    games: { route },
    edit: { route },
    present: { code: route.code },
    wall: { wallId: route.wallId },
    play: {},
    join: { code: route.code ?? null },
  }

  const view = route.view in views ? route.view : 'join'
  const loading = views[view]()
</script>

{#if !configured && view !== 'home'}
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
{:else}
  {#await loading then module}
    {@const View = module.default}
    <View {...props[view]} />
  {:catch}
    <!-- The one failure a split app adds: its page arriving in pieces over a
         bad connection. Say so, and offer the obvious fix. -->
    <main class="setup">
      <div>
        <h1 class="wordmark">blurt!</h1>
        <p>This page didn't finish loading. The connection may have dropped.</p>
        <p class="fix"><button onclick={() => window.location.reload()}>Try again</button></p>
      </div>
    </main>
  {/await}
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

  .fix button {
    padding: 10px 18px;
    border-radius: 8px;
    background: var(--neon-pink);
    color: var(--on-pink);
    font-weight: 600;
  }

  code {
    font-family: ui-monospace, Menlo, monospace;
    font-size: 0.9em;
    background: var(--stage-raised);
    padding: 2px 6px;
    border-radius: 4px;
  }
</style>
