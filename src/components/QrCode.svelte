<script>
  // A room code you can point a phone at.
  //
  // Drawn as one SVG path so it stays crisp at whatever size a projector throws
  // it, rather than a canvas bitmap scaled up.
  //
  // It is dark-on-white, on a white card, on an otherwise very dark wall. That
  // is deliberate and not negotiable: the spec has quiet-zone and contrast
  // expectations, and while some readers cope with inverted codes, plenty do
  // not. A neon-on-black QR would look like it belongs and fail on a third of
  // the room's phones.
  import qrcode from 'qrcode-generator'

  let { text = '', size = 320, quiet = 4 } = $props()

  // 0 asks the encoder to pick the smallest version that fits. 'M' recovers ~15%
  // — the level nearly everything is tuned for, and a short URL keeps the module
  // count low, which is what actually makes it scannable from a few rows back.
  let qr = $derived.by(() => {
    if (!text) return null
    try {
      const made = qrcode(0, 'M')
      made.addData(text)
      made.make()
      return made
    } catch {
      // Too much data for any version, or an encoder quirk. A missing QR is
      // survivable — the code is on the wall in letters a foot tall.
      return null
    }
  })

  let modules = $derived(qr?.getModuleCount() ?? 0)
  let span = $derived(modules + quiet * 2)

  // One path for the whole symbol: each dark module is its own little square
  // subpath. Far fewer nodes than a rect per module, and it scales identically.
  let path = $derived.by(() => {
    if (!qr) return ''
    const parts = []
    for (let row = 0; row < modules; row += 1) {
      for (let col = 0; col < modules; col += 1) {
        if (qr.isDark(row, col)) parts.push(`M${col + quiet} ${row + quiet}h1v1h-1z`)
      }
    }
    return parts.join('')
  })
</script>

{#if path}
  <svg
    class="qr"
    width={size}
    height={size}
    viewBox="0 0 {span} {span}"
    shape-rendering="crispEdges"
    role="img"
    aria-label="Scan to join this room"
  >
    <!-- The quiet zone is part of the symbol, not padding around it. -->
    <rect width={span} height={span} fill="#fff" />
    <path d={path} fill="#000" />
  </svg>
{/if}

<style>
  .qr {
    display: block;
    width: 100%;
    height: auto;
    border-radius: 6px;
    /* The card is white, so it needs its own edge against a near-black wall. */
    box-shadow: 0 0 0 3px #fff, 0 0 30px -6px var(--neon-cyan);
  }
</style>
