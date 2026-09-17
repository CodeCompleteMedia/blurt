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
    <circle cx="54" cy="54" {r} fill="none" stroke="var(--line)" stroke-width="8" />
    <circle
      cx="54"
      cy="54"
      {r}
      fill="none"
      stroke={fraction < 0.25 ? 'var(--accent)' : '#fff'}
      stroke-width="8"
      stroke-linecap="round"
      stroke-dasharray={circumference}
      stroke-dashoffset={circumference * (1 - fraction)}
      transform="rotate(-90 54 54)"
    />
  </svg>
  <span class="count">{seconds}</span>
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
  }

  .count {
    font-family: var(--display);
    font-size: 44px;
    font-weight: 400;
    font-variant-numeric: tabular-nums;
  }
</style>
