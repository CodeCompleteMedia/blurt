<script>
  import Shape from './Shape.svelte'

  // One answer. On the projector it carries the text; on a phone it deliberately
  // does not, so a glance at a neighbour's screen gives nothing away.
  //
  // At results the same tile does double duty: it stays exactly where it was
  // during the question and grows a fill showing how much of the room chose it.
  // Reading the answer off the tile you were just looking at beats reading it off
  // a separate chart.
  let {
    shape,
    text: choiceText = '',
    showText = true,
    state = 'idle', // idle | correct | wrong | dimmed
    count = null,
    share = 0,
    onclick = null,
    disabled = false,
  } = $props()
</script>

{#if onclick}
  <button class="tile {state}" style="--tile: {shape.color}" {disabled} {onclick} aria-label={shape.label}>
    <Shape shape={shape.key} size={showText ? 34 : 56} color="#fff" />
    {#if showText}<span class="text">{choiceText}</span>{/if}
  </button>
{:else}
  <div class="tile {state}" style="--tile: {shape.color}">
    {#if count !== null}
      <div class="fill" style="width: {Math.max(share * 100, 2)}%"></div>
    {/if}
    <Shape shape={shape.key} size={showText ? 34 : 56} color="#fff" />
    {#if showText}<span class="text">{choiceText}</span>{/if}
    {#if count !== null}
      <span class="count">{count}</span>
      {#if state === 'correct'}<span class="tick" aria-label="correct answer">✓</span>{/if}
    {/if}
  </div>
{/if}

<style>
  .tile {
    position: relative;
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 20px 22px;
    border-radius: 10px;
    background: var(--tile);
    color: #fff;
    text-align: left;
    min-height: 88px;
    overflow: hidden;
    transition: opacity 0.2s ease, transform 0.15s ease;
  }

  .tile > :global(svg),
  .text,
  .count,
  .tick {
    position: relative;
    z-index: 1;
  }

  .text {
    font-size: clamp(18px, 2.1vw, 28px);
    font-weight: 600;
    line-height: 1.2;
  }

  .tile.dimmed {
    opacity: 0.28;
  }

  /* At results the tile becomes its own bar chart: the ground goes dark and the
     fill shows this answer's share of the room. */
  .tile.correct,
  .tile.wrong {
    background: var(--surface);
    color: var(--ink);
  }

  .tile.correct {
    box-shadow: 0 0 0 3px var(--tile) inset;
  }

  .tile.wrong {
    opacity: 0.6;
  }

  .fill {
    position: absolute;
    inset: 0 auto 0 0;
    background: var(--tile);
    opacity: 0.85;
    transition: width 0.5s cubic-bezier(0.2, 0.8, 0.2, 1);
  }

  .tile.wrong .fill {
    opacity: 0.4;
  }

  .count {
    margin-left: auto;
    font-family: var(--display);
    font-size: clamp(28px, 3vw, 44px);
    font-variant-numeric: tabular-nums;
    line-height: 1;
  }

  .tick {
    font-size: clamp(22px, 2.4vw, 32px);
    line-height: 1;
  }

  button.tile:hover:not(:disabled) {
    transform: translateY(-2px);
  }

  button.tile:disabled {
    cursor: default;
  }
</style>
