<script>
  // Third, then second, then first. The order is the whole point: the room spends
  // three seconds finding out, instead of reading a finished list in one glance.
  //
  // A wall that is refreshed after the game has ended shows the result at once —
  // the ceremony is for the room that was there, not for whoever reloads the page.
  import { ms, rise, slam } from '../lib/motion.js'
  import RollingNumber from './RollingNumber.svelte'

  let { standings = [], ceremony = false, onreveal = () => {} } = $props()

  let top = $derived(standings.slice(0, 3))
  let rest = $derived(standings.slice(3, 6))

  // How far the reveal has got: 0 nothing, then one step per place from the bottom.
  let shown = $state(0)

  $effect(() => {
    const places = top.length
    if (!ceremony) {
      shown = places + 1
      return
    }
    const timers = []
    for (let step = 1; step <= places; step += 1) {
      timers.push(
        setTimeout(() => {
          shown = step
          onreveal(places - step + 1)
        }, ms(700 + (step - 1) * 1500)),
      )
    }
    timers.push(setTimeout(() => (shown = places + 1), ms(700 + places * 1500)))
    return () => timers.forEach(clearTimeout)
  })

  const visible = (place) => shown >= top.length - place + 1
</script>

<div class="podium" style="--places: {top.length}">
  <!-- Laid out second, first, third, the way a podium stands. -->
  {#each [2, 1, 3] as place}
    {@const player = top[place - 1]}
    {#if player}
      <div class="spot p{place}">
        {#if visible(place)}
          <div class="who" in:slam={{ from: place === 1 ? 1.7 : 1.3 }}>
            <span class="name">{player.name}</span>
            <span class="score"><RollingNumber value={player.score} duration={0} /></span>
          </div>
        {/if}
        <div class="block" class:lit={visible(place)}><span>{place}</span></div>
      </div>
    {/if}
  {/each}
</div>

{#if rest.length && shown > top.length}
  <ol class="rest" in:rise>
    {#each rest as player (player.id)}
      <li><span class="rank">{player.rank}</span>{player.name}<span class="score">{player.score.toLocaleString()}</span></li>
    {/each}
  </ol>
{/if}

<style>
  .podium {
    display: grid;
    grid-template-columns: repeat(var(--places), minmax(0, 1fr));
    gap: clamp(10px, 2vw, 28px);
    align-items: end;
    width: 100%;
    max-width: 1100px;
    margin: 0 auto;
  }

  .spot {
    display: grid;
    gap: 14px;
    justify-items: center;
    align-content: end;
    text-align: center;
    min-width: 0;
  }

  .who {
    display: grid;
    gap: 2px;
    min-width: 0;
    max-width: 100%;
  }

  .name {
    font-family: var(--display);
    font-size: clamp(24px, 4.2vw, 76px);
    line-height: 1;
    overflow-wrap: anywhere;
  }

  .p1 .name {
    font-size: clamp(30px, 5.6vw, 104px);
    color: var(--accent);
  }

  .score {
    color: var(--muted);
    font-size: clamp(14px, 1.8vw, 30px);
    font-variant-numeric: tabular-nums;
  }

  .block {
    display: grid;
    place-items: center;
    width: 100%;
    border-radius: 12px 12px 0 0;
    background: var(--surface);
    font-family: var(--display);
    font-size: clamp(28px, 4vw, 64px);
    color: var(--muted);
    transition: background 0.5s ease, color 0.5s ease;
  }

  .block.lit {
    background: var(--surface-2);
    color: var(--ink);
  }

  .p1 .block {
    height: clamp(120px, 24vh, 260px);
  }

  .p1 .block.lit {
    background: var(--accent);
    color: #1a0d07;
  }

  .p2 .block {
    height: clamp(84px, 17vh, 180px);
  }

  .p3 .block {
    height: clamp(60px, 12vh, 130px);
  }

  .rest {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 8px 28px;
    margin: 22px 0 0;
    padding: 0;
    list-style: none;
    font-size: clamp(15px, 1.7vw, 28px);
  }

  .rest li {
    display: flex;
    gap: 10px;
    align-items: baseline;
  }

  .rank {
    font-family: var(--display);
    color: var(--muted);
  }
</style>
