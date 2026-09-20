<script>
  // Between questions, not during. Five rows is what a class reads in the few
  // seconds it is up; the rest of the room finds itself on its own phone.
  import { flip } from 'svelte/animate'

  import { ms } from '../lib/motion.js'
  import RollingNumber from './RollingNumber.svelte'

  let { standings = [], limit = 5 } = $props()

  let rows = $derived(standings.slice(0, limit))
</script>

<ol class="board">
  {#each rows as player (player.id)}
    <!-- Rows slide to their new places: an overtake is something you watch
         happen, not something you work out by re-reading the list. -->
    <li animate:flip={{ duration: ms(520) }}>
      <span class="rank">{player.rank}</span>
      <span class="name">{player.name}</span>
      <span class="score"><RollingNumber value={player.score} /></span>
    </li>
  {/each}
</ol>

<style>
  .board {
    display: grid;
    gap: 8px;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  li {
    display: grid;
    grid-template-columns: 2.4rem 1fr auto;
    gap: 16px;
    align-items: center;
    padding: 14px 20px;
    border-radius: var(--radius-md);
    background: var(--stage-raised);
    box-shadow: inset 0 0 0 1px var(--line);
    font-size: clamp(18px, 2.4vw, 46px);
  }

  /* The leader is lit: yellow means winning, and nothing else is yellow. */
  li:first-child {
    background: var(--stage-high);
    box-shadow:
      inset 0 0 0 2px var(--neon-yellow),
      0 0 18px -2px #ffe53d80;
  }

  li:first-child .rank {
    color: var(--neon-yellow);
  }

  li:first-child .score {
    color: var(--ink);
  }

  .rank {
    font-family: var(--display);
    font-size: 1.2em;
    line-height: 1;
    color: var(--ink-muted);
  }

  .name {
    font-weight: 600;
  }

  .score {
    font-family: var(--bulbs);
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    color: var(--ink-muted);
  }
</style>
