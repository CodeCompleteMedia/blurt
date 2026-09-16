<script>
  // Between questions, not during. Five rows is what a class reads in the few
  // seconds it is up; the rest of the room finds itself on its own phone.
  let { standings = [], limit = 5 } = $props()

  let rows = $derived(standings.slice(0, limit))
</script>

<ol class="board">
  {#each rows as player (player.id)}
    <li>
      <span class="rank">{player.rank}</span>
      <span class="name">{player.name}</span>
      <span class="score">{player.score.toLocaleString()}</span>
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
    font-size: clamp(18px, 2vw, 26px);
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
