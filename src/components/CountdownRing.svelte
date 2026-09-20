<script>
  import { remainingFraction, remainingSeconds, ticker } from '../lib/clock.js'

  // Reads the clock, never a server tick: the ring is a pure function of
  // `startedAt` and the limit, so it stays right through a missed poll.
  // `frozenAt` holds the ring still while the teacher has the game paused.
  let { startedAt, limit, size = 120, frozenAt = null } = $props()

  let now = $state(Date.now())

  $effect(() => ticker((t) => (now = t)))

  const r = 46
  const circumference = 2 * Math.PI * r
  let at = $derived(frozenAt ?? now)
  let fraction = $derived(remainingFraction(startedAt, limit, at))
  let seconds = $derived(remainingSeconds(startedAt, limit, at))
</script>

<div class="ring" style="width: {size}px; height: {size}px">
  <svg viewBox="0 0 108 108">
    <circle cx="54" cy="54" {r} fill="none" stroke="var(--stage-high)" stroke-width="8" />
    <circle
      class="arc"
      class:late={fraction < 0.25}
      class:held={frozenAt !== null}
      cx="54"
      cy="54"
      {r}
      fill="none"
      stroke-width="8"
      stroke-linecap="round"
      stroke-dasharray={circumference}
      stroke-dashoffset={circumference * (1 - fraction)}
      transform="rotate(-90 54 54)"
    />
  </svg>
  <span class="count" class:late={fraction < 0.25}>{seconds}</span>
</div>

<style>
  .ring {
    position: relative;
    display: grid;
    place-items: center;
  }

  svg {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    overflow: visible;
  }

  /* Cyan while there is time, pink for the last quarter, grey and still while
     the teacher holds the game. */
  .arc {
    stroke: var(--neon-cyan);
    filter: drop-shadow(0 0 6px #19e3ffcc);
    transition: stroke 0.3s ease;
  }

  .arc.late {
    stroke: var(--neon-pink);
    filter: drop-shadow(0 0 6px #ff2e97cc);
  }

  .arc.held {
    stroke: var(--ink-muted);
    filter: none;
  }

  .count {
    font-family: var(--bulbs);
    font-size: 44px;
    font-weight: 900;
    line-height: 1;
    font-variant-numeric: tabular-nums;
  }

  .count.late {
    color: var(--neon-pink);
  }
</style>
