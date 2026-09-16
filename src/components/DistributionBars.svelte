<script>
  import Shape from './Shape.svelte'
  import { shapeFor } from '../lib/answers.js'

  // What the class actually picked. The bar for the right answer is the one
  // worth reading, so it is the only one that keeps full colour.
  let { counts = [], correctIndex = 0 } = $props()

  let total = $derived(Math.max(1, counts.reduce((sum, n) => sum + n, 0)))
</script>

<div class="bars">
  {#each counts as count, i}
    {@const shape = shapeFor(i)}
    <div class="col" class:correct={i === correctIndex}>
      <div class="track">
        <div
          class="fill"
          style="height: {(count / total) * 100}%; background: {shape.color}"
        ></div>
      </div>
      <div class="n">{count}</div>
      <Shape shape={shape.key} size={26} color={shape.color} />
    </div>
  {/each}
</div>

<style>
  .bars {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 18px;
    align-items: end;
    height: 100%;
    min-height: 180px;
  }

  .col {
    display: grid;
    grid-template-rows: 1fr auto auto;
    gap: 8px;
    justify-items: center;
    height: 100%;
    opacity: 0.45;
  }

  .col.correct {
    opacity: 1;
  }

  .track {
    display: flex;
    align-items: flex-end;
    width: 100%;
    height: 100%;
    border-radius: 6px;
    background: var(--surface);
  }

  .fill {
    width: 100%;
    min-height: 4px;
    border-radius: 6px;
    transition: height 0.45s cubic-bezier(0.2, 0.8, 0.2, 1);
  }

  .n {
    font-family: var(--display);
    font-size: 30px;
    font-variant-numeric: tabular-nums;
  }
</style>
