<script>
  // The frame around everything a teacher does. Two places — the room and the
  // quizzes — and who is signed in.
  //
  // The wall and the phone deliberately get none of this. A projector with a menu
  // bar is a projector with something to fiddle with, and a student's screen has
  // exactly one job at a time.
  import { auth, signOut } from '../lib/auth.svelte.js'
  import { readHost } from '../lib/session.js'

  let { current, children } = $props()

  // A room keeps running while its teacher is off editing a quiz — but it stops
  // advancing itself, because the host screen is what closes questions on time.
  // So a live room is never out of sight: it rides along in the bar.
  const room = current === 'host' ? null : readHost()

  async function leave() {
    await signOut()
    window.location.assign('/')
  }
</script>

<div class="shell">
  <nav aria-label="Teacher">
    <a class="brand" href="/host">blurt</a>

    <div class="places">
      <a href="/host" aria-current={current === 'host' ? 'page' : undefined}>
        Room
        {#if room?.code}<span class="live" title="A room is still open">{room.code}</span>{/if}
      </a>
      <a href="/edit" aria-current={current === 'edit' ? 'page' : undefined}>Quizzes</a>
    </div>

    <div class="who">
      <span class="email">{auth.user?.email}</span>
      <button onclick={leave}>Sign out</button>
    </div>
  </nav>

  <div class="content">
    {@render children()}
  </div>
</div>

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
    background: var(--surface);
  }

  .brand {
    font-family: var(--display);
    font-size: 24px;
    line-height: 1;
    color: var(--accent);
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
    color: var(--muted);
    font-size: 14px;
    font-weight: 500;
    text-decoration: none;
  }

  .places a:hover {
    color: var(--ink);
  }

  .places a[aria-current='page'] {
    background: var(--surface-2);
    color: var(--ink);
  }

  .live {
    padding: 1px 8px;
    border-radius: 999px;
    background: rgba(255, 110, 69, 0.16);
    color: var(--accent);
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

  .email {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 13px;
    color: var(--muted);
  }

  .who button {
    padding: 6px 12px;
    border: 1px solid var(--line);
    border-radius: 999px;
    color: var(--ink);
    font-size: 13px;
    white-space: nowrap;
  }

  /* The editor is longer than a screen; the room is sized to fit one. Either way
     the bar stays put and only this scrolls. */
  .content {
    overflow: auto;
  }

  @media (max-width: 560px) {
    .email {
      display: none;
    }

    nav {
      gap: 8px 10px;
    }
  }
</style>
