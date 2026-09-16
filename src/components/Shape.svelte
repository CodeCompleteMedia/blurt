<script>
  // The four answer marks. Drawn rather than glyphs so they stay crisp from the
  // back row of the room and legible at 44px on a phone.
  let { shape, size = 32, color = 'currentColor' } = $props()

  const paths = {
    triangle: 'M16 4 30 28H2z',
    diamond: 'M16 2 30 16 16 30 2 16z',
    circle: '',
    square: 'M4 4h24v24H4z',
  }
</script>

<svg width={size} height={size} viewBox="0 0 32 32" aria-hidden="true">
  {#if shape === 'circle'}
    <circle cx="16" cy="16" r="13" fill={color} />
  {:else}
    <path d={paths[shape]} fill={color} />
  {/if}
</svg>
