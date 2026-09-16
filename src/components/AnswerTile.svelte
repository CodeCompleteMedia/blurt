<script>
  import Shape from './Shape.svelte'

  // One answer. On the projector it carries the text; on a phone it deliberately
  // does not, so a glance at a neighbour's screen gives nothing away.
  let {
    shape,
    text: choiceText = '',
    showText = true,
    state = 'idle', // idle | correct | wrong | dimmed
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
    <Shape shape={shape.key} size={showText ? 34 : 56} color="#fff" />
    {#if showText}<span class="text">{choiceText}</span>{/if}
  </div>
{/if}

<style>
  .tile {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 20px 22px;
    border-radius: 10px;
    background: var(--tile);
    color: #fff;
    text-align: left;
    min-height: 88px;
    transition: opacity 0.2s ease, transform 0.15s ease;
  }

  .text {
    font-size: clamp(18px, 2.1vw, 28px);
    font-weight: 600;
    line-height: 1.2;
  }

  .tile.dimmed {
    opacity: 0.28;
  }

  .tile.correct {
    box-shadow: 0 0 0 4px #fff inset;
  }

  .tile.wrong {
    opacity: 0.35;
  }

  button.tile:hover:not(:disabled) {
    transform: translateY(-2px);
  }

  button.tile:disabled {
    cursor: default;
  }
</style>
