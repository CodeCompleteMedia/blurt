<script>
  // One answer. On the projector it carries the text; on a phone it deliberately
  // does not, so a glance at a neighbour's screen gives nothing away.
  //
  // At results the same tile does double duty: it stays exactly where it was
  // during the question and grows a fill showing how much of the room chose it.
  // Reading the answer off the tile you were just looking at beats reading it off
  // a separate chart.
  let {
    choice,
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
  <button class="tile {state}" class:solo={!showText} style="--tile: {choice.color}; --rim: {choice.rim}" {disabled} {onclick} aria-label={choice.label}>
    <span class="letter" class:big={!showText}>{choice.key}</span>
    {#if showText}<span class="text">{choiceText}</span>{/if}
  </button>
{:else}
  <div class="tile {state}" class:solo={!showText && count === null} style="--tile: {choice.color}; --rim: {choice.rim}">
    {#if count !== null}
      <div class="fill" style="width: {Math.max(share * 100, 2)}%"></div>
    {/if}
    <span class="letter" class:big={!showText}>{choice.key}</span>
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
    border-radius: var(--radius-md);
    background: var(--tile);
    color: var(--on-tile);
    /* Lit plexiglass: the fill, a neon rim, and the glow it throws. */
    box-shadow:
      inset 0 0 0 2px var(--rim),
      0 0 18px -4px var(--rim);
    text-align: left;
    min-height: 88px;
    overflow: hidden;
    transition:
      opacity 0.2s ease,
      transform 0.15s ease,
      box-shadow 0.2s ease;
  }

  .letter,
  .text,
  .count,
  .tick {
    position: relative;
    z-index: 1;
  }

  /* The letter is the answer's name — on a phone it is the only thing on the
     tile, so it is sized to be readable at arm's length and unmistakable from
     the back of the room when the wall shows it. A fixed min-width keeps the
     answer text starting at the same x on all four. */
  .letter {
    flex: none;
    /* A fixed footprint, so the answer text starts at the same x on all four
       and the tile does not grow a line just because the letter is wide. The
       shape this replaced was a flat 34px even on a projector; the letter is
       the answer's name now, so it scales with the wall instead. */
    width: clamp(28px, 2.6vw, 48px);
    font-family: var(--display);
    font-size: clamp(20px, 2vw, 38px);
    line-height: 1;
    text-align: center;
  }

  .letter.big {
    width: auto;
    font-size: clamp(44px, 9vw, 64px);
  }

  /* Nothing on the tile but the letter — centre it rather than leaving it
     hanging off the left where the answer text would have started. */
  .tile.solo {
    justify-content: center;
  }

  .text {
    font-size: clamp(18px, 2.8vw, 54px);
    font-weight: 600;
    line-height: 1.2;
  }

  .tile.dimmed {
    opacity: 0.28;
    box-shadow: none;
  }

  /* At results the tile becomes its own bar chart: the ground goes dark and the
     fill shows this answer's share of the room. */
  .tile.correct,
  .tile.wrong {
    background: var(--stage-raised);
    color: var(--ink);
  }

  .tile.correct {
    box-shadow: var(--glow-correct);
  }

  .tile.wrong {
    opacity: 0.6;
    box-shadow: inset 0 0 0 1px var(--line);
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

  /* The bars grow out from nothing as the answer goes up. Pure CSS, so the
     reduced-motion rule in app.css switches it off without anyone asking. */
  .fill {
    animation: grow 0.7s cubic-bezier(0.2, 0.8, 0.2, 1) both;
  }

  @keyframes grow {
    from {
      width: 0;
    }
  }

  .count {
    margin-left: auto;
    font-family: var(--bulbs);
    font-weight: 900;
    font-size: clamp(28px, 3.6vw, 72px);
    font-variant-numeric: tabular-nums;
    line-height: 1;
  }

  .tick {
    color: var(--correct);
    font-weight: 700;
    font-size: clamp(22px, 2.4vw, 32px);
    line-height: 1;
  }

  button.tile:hover:not(:disabled) {
    transform: translateY(-2px);
    box-shadow:
      inset 0 0 0 2px var(--rim),
      0 0 28px 0 var(--rim);
  }

  button.tile:disabled {
    cursor: default;
  }
</style>
