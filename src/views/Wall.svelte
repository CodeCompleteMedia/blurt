<script>
  // A display, waiting to be told which room it is showing.
  //
  // It is the same wall as /present/CODE once it knows the code — literally the
  // same component. The only thing this adds is how the code arrives: pushed by
  // the teacher instead of typed into the address bar at the front of a class.
  import { watchWall } from '../lib/api.js'
  import Present from './Present.svelte'

  let { wallId = null } = $props()

  let room = $state(null)
  let booting = $state(true)

  $effect(() => {
    if (!wallId) {
      booting = false
      return
    }
    const watch = watchWall({
      wallId,
      onRoom: (found) => {
        room = found
        booting = false
      },
    })
    return watch.stop
  })
</script>

{#if room?.code}
  <!-- Keyed, so pointing this display at a different room gives the wall a clean
       start rather than a half-remembered one: the cue guards, the ceremony flag
       and the arrival baseline all belong to one room. -->
  {#key room.code}
    <Present code={room.code} />
  {/key}
{:else}
  <main class="idle">
    {#if booting}
      <p class="muted">…</p>
    {:else if !wallId || !room}
      <h1 class="hush">Not a display</h1>
      <p class="muted">This link does not match any display. Check it in blurt under Room → Displays.</p>
    {:else}
      <span class="wordmark mark">blurt!</span>
      <h1>{room.label}</h1>
      <p class="muted">Ready. Send a room to this display from the teacher's screen.</p>
    {/if}
  </main>
{/if}

<style>
  .idle {
    display: grid;
    place-content: center;
    justify-items: center;
    gap: 18px;
    height: 100%;
    padding: var(--gutter);
    text-align: center;
  }

  .mark {
    font-size: clamp(28px, 4vw, 54px);
    text-transform: uppercase;
  }

  h1 {
    font-size: clamp(40px, 8vw, 120px);
  }

  .hush {
    color: var(--ink-muted);
  }

  .muted {
    margin: 0;
    color: var(--ink-muted);
    font-size: clamp(16px, 2vw, 28px);
  }
</style>
