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
    grid-template-columns: 2.2rem 1fr auto;
    gap: 16px;
    align-items: center;
    padding: 14px 20px;
    border-radius: 8px;
    background: var(--surface);
    font-size: clamp(18px, 2.4vw, 46px);
  }

  li:first-child {
    background: var(--surface-2);
  }

  .rank {
    font-family: var(--display);
    font-size: 1.4em;
    color: var(--muted);
  }

  .name {
    font-weight: 600;
  }

  .score {
    font-variant-numeric: tabular-nums;
    color: var(--muted);
  }
</style>
