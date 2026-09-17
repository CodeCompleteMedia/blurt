<script>
  // A number that counts to its new value instead of jumping to it. On a
  // scoreboard the movement is the news: you see who just gained, and how much,
  // before you have read a single figure.
  import { cubicOut } from 'svelte/easing'
  import { Tween } from 'svelte/motion'

  import { ms } from '../lib/motion.js'

  let { value = 0, duration = 900 } = $props()

  // Starts at the value rather than at zero, so a board that is simply loading
  // does not pretend everyone just scored.
  const shown = new Tween(value, { duration: ms(duration), easing: cubicOut })

  $effect(() => {
    shown.target = value
  })
</script>

{Math.round(shown.current).toLocaleString()}
