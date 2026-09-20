<script>
  // The wall. It holds no credential and can change nothing — it reads the room
  // by code and renders it big. Everything a student is allowed to see is here,
  // and nothing else is: the database withholds the choices during recall and
  // the correct answer until results, so this view has no secret to leak.
  import AnswerTile from '../components/AnswerTile.svelte'
  import CountdownRing from '../components/CountdownRing.svelte'
  import confetti from 'canvas-confetti'

  import Leaderboard from '../components/Leaderboard.svelte'
  import Podium from '../components/Podium.svelte'
  import {
    blurter,
    currentQuestion,
    distribution,
    textDistribution,
    fetchGame,
    fetchPlayers,
    watchGame,
  } from '../lib/api.js'
  import { choiceFor } from '../lib/answers.js'
  import { arrivals } from '../lib/arrivals.js'
  import { duckMusic, isMusicOn, setMusicOn, syncMusic } from '../lib/music.js'
  import { clockBase, remainingSeconds, ticker } from '../lib/clock.js'
  import { calm, rise, slam } from '../lib/motion.js'
  import { isMuted, isUnlocked, setMuted, sounds, unlock } from '../lib/sound.js'

  let { code = null } = $props()

  let game = $state(null)
  let players = $state([])
  let question = $state(null)
  let counts = $state([])
  // What the room typed, for a question with no tiles to tally.
  let typed = $state([])
  let floor = $state(null)
  let problem = $state('')
  let booting = $state(true)
  let now = $state(Date.now())
  let questionBase = $state(null)
  let loadedKey = ''

  // ------------------------------------------------------------------ sound ---
  // Browsers keep a page silent until someone touches it, and the wall is usually
  // opened by the host screen rather than clicked. So it says when it is silent,
  // and the first click or keypress anywhere wakes it.
  let audio = $state({ unlocked: isUnlocked(), muted: isMuted(), music: isMusicOn() })

  // The bed plays whenever the wall is allowed to make noise at all. Muting is
  // the master switch over both, so one click still silences the room.
  let allowed = $derived(audio.unlocked && !audio.muted)

  // The projector needs a click before it may make noise, so that same click is
  // the one gesture a browser will also accept for fullscreen. One click on the
  // wall and it is running: sound on, browser chrome gone. Only the first one —
  // a teacher who presses Escape should not be dragged back in by a stray click.
  let filled = $state(false)
  let triedFull = false

  async function goFullscreen() {
    try {
      await document.documentElement.requestFullscreen()
    } catch {
      // Refused, or unsupported. The wall is perfectly usable in a window.
    }
  }

  async function wake(event) {
    if (!audio.unlocked) audio.unlocked = await unlock()
    syncMusic(audio.unlocked && !audio.muted)
    if (!triedFull && event?.isTrusted) {
      triedFull = true
      await goFullscreen()
    }
  }

  async function toggleFullscreen(event) {
    event.stopPropagation()
    triedFull = true
    if (document.fullscreenElement) await document.exitFullscreen().catch(() => {})
    else await goFullscreen()
  }

  $effect(() => {
    const sync = () => (filled = Boolean(document.fullscreenElement))
    sync()
    document.addEventListener('fullscreenchange', sync)
    return () => document.removeEventListener('fullscreenchange', sync)
  })

  async function toggleSound(event) {
    event.stopPropagation()
    if (!audio.unlocked) {
      audio.unlocked = await unlock()
      audio.muted = false
    } else {
      audio.muted = !audio.muted
    }
    setMuted(audio.muted)
    syncMusic(audio.unlocked && !audio.muted)
  }

  async function toggleMusic(event) {
    event.stopPropagation()
    if (!audio.unlocked) {
      audio.unlocked = await unlock()
      audio.muted = false
      setMuted(false)
    }
    audio.music = !audio.music
    setMusicOn(audio.music, audio.unlocked && !audio.muted)
  }

  // Autoplay is refused until the page has been touched, so the bed starts on
  // the same gesture everything else waits for — and starts again by itself if
  // the wall is unmuted later.
  $effect(() => {
    syncMusic(allowed)
  })

  // Someone has the floor and is about to say the answer out loud. That is the
  // one moment in the game the room has to hear a person, not a soundtrack.
  $effect(() => {
    duckMusic(phase === 'blurt_claimed')
  })

  // Cues fire on a *change* the wall watched happen. A wall that is refreshed
  // mid-question must not replay the sting for a claim made a minute ago.
  let lastPhase = null
  let lastIndex = null
  let ceremony = $state(false)

  $effect(() => {
    const p = game?.phase ?? null
    const index = game?.question_index
    if (p == null) return
    if (lastPhase !== null && (p !== lastPhase || index !== lastIndex)) {
      if (p === 'recall' || p === 'question_open') sounds.open()
      else if (p === 'blurt_claimed') sounds.sting()
      else if (p === 'locked') sounds.time()
      else if (p === 'results') sounds.reveal()
      else if (p === 'final') ceremony = true
    }
    lastPhase = p
    lastIndex = index
  })

  // A phone arriving.
  //
  // Same rule as the phase cues: only for an arrival this wall watched happen.
  // `known` starts null, so the first roster the wall receives sets the baseline
  // silently — otherwise refreshing the projector in a full lobby would fire
  // thirty chirps at a room that has been sitting there for five minutes.
  //
  // Identity, not count: a student removed and another joining between two polls
  // leaves the length unchanged but is still an arrival.
  let known = null
  let joins = 0

  $effect(() => {
    const seen = arrivals(known, players)
    known = seen.known
    joins += seen.arrived
    if (seen.baseline || !seen.arrived) return

    // Never over a live question. A latecomer is worth knowing about, but not at
    // the cost of chirping through the eight seconds someone is recalling in.
    if (phase === 'recall' || phase === 'question_open') return

    // Staggered, so a clump reads as a little run rather than one thick noise.
    // `joins - seen.arrived` is where the ladder stood before they walked in.
    const from = joins - seen.arrived
    for (let i = 0; i < seen.chirps; i += 1) sounds.join(from + i, i * 0.08)
  })

  // The last five seconds tick. Not the whole clock: a quiz should not sound like
  // a bomb from the first second.
  let lastTick = null
  $effect(() => {
    if (!counting || frozenAt || !questionBase) return
    const left = remainingSeconds(questionBase, limit, now)
    if (left === lastTick) return
    lastTick = left
    if (left >= 1 && left <= 5) sounds.tick(left)
  })

  function celebrate(place) {
    if (place > 1) return sounds.step(place)
    sounds.fanfare()
    const burst = {
      disableForReducedMotion: true,
      particleCount: 90,
      spread: 70,
      startVelocity: 55,
      // The tubes, and the four answer rims.
      colors: ['#ff2e97', '#19e3ff', '#ffe53d', '#ff4d8d', '#5c8bff', '#ffb020', '#2dff9a'],
    }
    confetti({ ...burst, origin: { x: 0.15, y: 0.75 }, angle: 60 })
    confetti({ ...burst, origin: { x: 0.85, y: 0.75 }, angle: 120 })
    setTimeout(() => confetti({ ...burst, particleCount: 140, spread: 110, origin: { y: 0.55 } }), calm ? 0 : 350)
  }

  let limit = $derived((question?.seconds ?? 20) * 1000)
  let phase = $derived(game?.phase ?? null)
  let closed = $derived(Boolean(game?.closed_at))
  let frozenAt = $derived(game?.paused_at ? Date.parse(game.paused_at) : null)
  let counting = $derived(phase === 'recall' || phase === 'question_open')
  let totalVotes = $derived(counts.reduce((sum, n) => sum + n, 0))
  // Only reachable if the "All in" beat is restored — an all-in question now goes
  // straight to the reveal, so `locked` is currently only ever reached by the
  // clock running out. Kept because the beat is one line away in
  // 0011_all_in_reveals.sql, and "Time" over a question everyone answered would
  // read as a cut-off.
  let allIn = $derived(players.length > 0 && (game?.answered_count ?? 0) >= players.length)

  async function boot() {
    if (!code) {
      problem = 'No room code. Open this view from the host screen.'
      booting = false
      return
    }
    try {
      game = await fetchGame(code)
      if (!game) problem = `No room called ${code}.`
      else players = await fetchPlayers(code)
    } catch (error) {
      problem = error.message
    } finally {
      booting = false
    }
  }

  $effect(() => {
    boot()
  })

  $effect(() => ticker((t) => (now = t)))

  $effect(() => {
    if (!code) return
    const watch = watchGame({
      code,
      onGame: (row) => (game = row),
      onPlayers: (rows) => (players = rows),
    })
    return watch.stop
  })

  $effect(() => {
    const p = game?.phase
    const index = game?.question_index
    const started = game?.question_started_at
    if (!code || index == null || index < 0) {
      question = null
      counts = []
      floor = null
      loadedKey = ''
      return
    }

    // The extension is part of the key: more time means a new limit to fetch.
    const key = `${p}:${index}:${started}:${game?.extra_seconds}`
    if (key === loadedKey) return
    loadedKey = key
    questionBase = clockBase(started, limit, Date.now())

    void (async () => {
      try {
        question = await currentQuestion(code)
        counts = p === 'results' ? await distribution(code) : []
        typed = p === 'results' && question?.kind === 'text' ? await textDistribution(code) : []
        floor = p === 'blurt_claimed' || p === 'results' ? await blurter(code) : null
      } catch (error) {
        problem = error.message
      }
    })()
  })
</script>

<svelte:window onclick={wake} onkeydown={wake} />

<main class="stage surface">
  <header>
    <span class="wordmark brand">blurt!</span>
    {#if game && game.question_index >= 0 && phase !== 'final'}
      <span class="eyebrow">Question {game.question_index + 1}</span>
    {/if}
    {#if code}<span class="eyebrow code">{code}</span>{/if}
    <button
      class="sound"
      class:off={!audio.unlocked || audio.muted}
      onclick={toggleSound}
      aria-label={!audio.unlocked ? 'Turn sound on' : audio.muted ? 'Unmute' : 'Mute'}
    >
      {!audio.unlocked ? 'Click the wall to start' : audio.muted ? 'Muted' : 'Sound on'}
    </button>
    <button
      class="sound"
      class:off={!audio.music}
      onclick={toggleMusic}
      aria-label={audio.music ? 'Turn the music off' : 'Turn the music on'}
    >
      {audio.music ? 'Music on' : 'Music off'}
    </button>
    <button
      class="sound"
      class:off={!filled}
      onclick={toggleFullscreen}
      aria-label={filled ? 'Leave fullscreen' : 'Fill the screen'}
    >
      {filled ? 'Fullscreen' : 'Fill the screen'}
    </button>
    {#if phase === 'final' || closed}
      <!-- The way off the wall, and it appears only once there is nothing left
           to interrupt. During a game the projector deliberately has nothing on
           it to fiddle with. -->
      <a class="leave" href="/">Leave</a>
    {/if}
  </header>

  {#if booting}
    <section class="centred"><p class="muted">Finding the room…</p></section>
  {:else if problem}
    <section class="centred"><p class="muted">{problem}</p></section>
  {:else if closed && phase === 'final' && players.length}
    <!-- Wrapped up. The result stays up for the room to look at; the ceremony is
         over. No reveal, no fanfare, no confetti — a scoreboard, not a party. -->
    <section class="final">
      <p class="eyebrow">Final</p>
      <Podium standings={players} ceremony={false} />
    </section>
  {:else if closed}
    <!-- The host started a new room. This one has no way to discover the new
         code, so it says so plainly rather than showing a game nobody is in. -->
    <section class="centred">
      <h1 class="hush">Room closed</h1>
      <p class="muted">The teacher has opened a new room.</p>
    </section>
  {:else if phase === 'lobby'}
    <section class="lobby">
      <p class="eyebrow">Room code</p>
      <h1 class="code-big">{code}</h1>
      {#if players.length}
        <ul class="roster">
          {#each players as player (player.id)}<li>{player.name}</li>{/each}
        </ul>
      {:else}
        <p class="muted waiting">Waiting for the first phone…</p>
      {/if}
    </section>
  {:else if phase === 'recall' && question}
    <!-- No choices on screen and none in the payload. Knowing it beats
         recognising it, and that is the whole point of the window. -->
    <section class="recall" class:with-image={question.image}>
      {#if question.image}<img class="picture" src={question.image} alt="" />{/if}
      <h2 class="big-q" in:rise={{ y: 26 }}>{question.text}</h2>
      <div class="recall-foot">
        <p class="prompt">
          {#if frozenAt}<strong>Paused</strong>{:else}Know it? <strong>Blurt.</strong>{/if}
        </p>
        <CountdownRing startedAt={questionBase} {limit} size={96} {frozenAt} />
      </div>
    </section>
  {:else if phase === 'blurt_claimed'}
    <section class="claimed">
      <p class="eyebrow">Has the floor</p>
      <!-- Keyed on the name so it lands when the name arrives, not when the empty
           section does: the claim is known a beat before who made it. -->
      {#key floor?.name}
        <h1 class="who" in:slam>{floor?.name ?? '…'}</h1>
      {/key}
      <p class="sub">Say it out loud</p>
    </section>
  {:else if question && (phase === 'question_open' || phase === 'locked')}
    <section class="question">
      <div class="q-head">
        <h2>{question.text}</h2>
        {#if counting}
          <CountdownRing startedAt={questionBase} {limit} {frozenAt} />
        {:else}
          <div class="times-up" class:all-in={allIn}><span>{allIn ? 'All in' : 'Time'}</span></div>
        {/if}
      </div>
      {#if question.kind === 'text'}
        <!-- No tiles to show: the answer is whatever they can produce. -->
        <div class="typed-prompt" class:with-image={question.image}>
          {#if question.image}<img class="picture" src={question.image} alt="" />{/if}
          <p>Type your answer</p>
        </div>
      {:else}
        <div class="q-body" class:with-image={question.image}>
          {#if question.image}<img class="picture" src={question.image} alt="" />{/if}
          <div class="tiles" class:pair={question.choices?.length === 2}>
            {#each question.choices ?? [] as choice, i}
              <!-- One after another, so four tiles read as four choices rather
                   than as a block that appeared. -->
              <div class="tile-wrap" in:rise={{ delay: i * 80 }}>
                <AnswerTile
                  choice={choiceFor(i)}
                  text={choice}
                  state={phase === 'locked' ? 'dimmed' : 'idle'}
                />
              </div>
            {/each}
          </div>
        </div>
      {/if}
      <p class="answered">
        {#if frozenAt}<strong class="paused-note">Paused</strong> &middot; {/if}
        {game.answered_count} of {players.length} answered
      </p>
    </section>
  {:else if phase === 'results' && question}
    <section class="results">
      <div class="left">
        <h2 class="reveal">
          <span class="eyebrow">
            {floor?.wasCorrect ? `${floor.name} blurted it` : 'The answer was'}
          </span>
          {question.answer ?? '—'}
        </h2>
        {#if question.kind === 'text'}
          <ol class="typed">
            {#each typed as row}
              <li class:right={row.correct}>
                <span class="what">{row.text}</span>
                <span class="n">{row.count}</span>
              </li>
            {:else}
              <li class="none">Nobody typed an answer.</li>
            {/each}
          </ol>
        {:else}
        <div class="tiles result-tiles">
          {#each question.choices ?? [] as choice, i}
            <AnswerTile
              choice={choiceFor(i)}
              text={choice}
              state={i === question.correctIndex ? 'correct' : 'wrong'}
              count={counts[i] ?? 0}
              share={totalVotes ? (counts[i] ?? 0) / totalVotes : 0}
            />
          {/each}
        </div>
        {/if}
      </div>
      <div class="right">
        <p class="eyebrow">Standings</p>
        <Leaderboard standings={players} />
      </div>
    </section>
  {:else if phase === 'final'}
    <section class="final">
      <p class="eyebrow">Final</p>
      {#if players.length}
        <Podium standings={players} {ceremony} onreveal={celebrate} />
      {:else}
        <h1>Nobody played</h1>
      {/if}
    </section>
  {:else}
    <section class="centred"><p class="muted">…</p></section>
  {/if}
</main>

<style>
  .stage {
    display: grid;
    grid-template-rows: auto 1fr;
    gap: 24px;
    height: 100%;
  }

  header {
    display: flex;
    flex-wrap: wrap;
    gap: 10px 28px;
    align-items: baseline;
  }

  .sound {
    padding: 4px 12px;
    border: 1px solid var(--line);
    border-radius: 999px;
    color: var(--ink-muted);
    font-size: 11px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
  }

  .sound.off {
    border-color: var(--neon-pink);
    color: var(--neon-pink);
  }

  .leave {
    padding: 4px 12px;
    border: 1px solid var(--line);
    border-radius: 999px;
    color: var(--ink-muted);
    font-size: 11px;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    text-decoration: none;
  }

  /* The wrapper exists only to carry the entrance; it must not change how a tile
     sits in the grid. */
  .tile-wrap {
    display: grid;
    min-width: 0;
  }

  .brand {
    font-size: 22px;
    line-height: 1;
    text-transform: uppercase;
  }

  header .code {
    margin-left: auto;
    padding: 2px 14px;
    border: 2px solid var(--neon-cyan);
    border-radius: var(--radius-pill);
    color: var(--ink);
    font-family: var(--display);
    font-size: 18px;
    letter-spacing: 0.2em;
  }

  section {
    min-height: 0;
  }

  .centred,
  .lobby,
  .claimed {
    display: grid;
    align-content: center;
    justify-items: center;
    gap: 10px;
    text-align: center;
  }

  .muted {
    margin: 0;
    color: var(--ink-muted);
    font-size: clamp(16px, 1.8vw, 22px);
  }

  .hush {
    color: var(--ink-muted);
    font-size: clamp(48px, 9vw, 110px);
  }

  /* The room code on a lit plate. In Bungee, not the scoreboard face: this is
     the one string the room has to read and retype, and in dot-matrix B/8 and
     S/5 are a couple of dots apart. Same reason Q left the alphabet. */
  .code-big {
    padding: 0.12em 0.3em 0.12em 0.42em;
    border: 3px solid var(--neon-cyan);
    border-radius: var(--radius-lg);
    background: var(--stage-raised);
    box-shadow: var(--glow-cyan);
    font-family: var(--display);
    font-size: clamp(72px, 15vw, 200px);
    letter-spacing: 0.12em;
  }

  .waiting {
    margin-top: 20px;
  }

  .roster {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 10px;
    margin: 24px 0 0;
    padding: 0;
    list-style: none;
  }

  .roster li {
    padding: 8px 18px;
    border-radius: var(--radius-pill);
    background: var(--stage-raised);
    box-shadow: inset 0 0 0 1px var(--line-strong);
    font-size: clamp(16px, 2vw, 38px);
  }

  /* Recall — the question alone, as large as it will go */
  .recall {
    display: grid;
    grid-template-rows: 1fr auto;
    gap: 28px;
    align-items: center;
  }

  .big-q {
    font-family: var(--body);
    font-size: clamp(36px, 6.5vw, 96px);
    font-weight: 600;
    line-height: 1.05;
    text-transform: none;
    text-wrap: balance;
    align-self: center;
  }

  .recall-foot {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 24px;
  }

  .prompt {
    margin: 0;
    font-size: clamp(18px, 2.4vw, 32px);
    color: var(--ink-muted);
  }

  .prompt strong {
    color: var(--neon-pink);
  }

  .who {
    font-size: clamp(56px, 11vw, 140px);
    color: var(--neon-pink);
    text-shadow: var(--text-glow-pink);
  }

  .claimed .sub {
    margin: 0;
    font-size: clamp(20px, 2.6vw, 34px);
    color: var(--ink-muted);
  }

  /* Multiple choice */
  .question {
    display: grid;
    grid-template-rows: auto 1fr auto;
    gap: 22px;
  }

  .q-head {
    display: flex;
    gap: 32px;
    align-items: center;
    justify-content: space-between;
  }

  .q-head h2 {
    font-family: var(--body);
    font-size: clamp(28px, 4.4vw, 84px);
    font-weight: 600;
    line-height: 1.1;
    text-transform: none;
    text-wrap: balance;
  }

  .times-up {
    display: grid;
    place-items: center;
    width: 120px;
    height: 120px;
    padding: 10px;
    border: 4px solid var(--neon-pink);
    border-radius: 50%;
    box-shadow: var(--glow-pink);
    font-family: var(--display);
    font-size: 34px;
    line-height: 0.95;
    text-align: center;
    color: var(--neon-pink);
    text-transform: uppercase;
  }

  .times-up.all-in {
    border-color: var(--correct);
    box-shadow: var(--glow-correct);
    color: var(--correct);
    font-size: 26px;
  }

  .tiles {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 16px;
    align-content: center;
  }

  /* A picture shares the screen with the question rather than replacing it, and
     never grows past the space it is given — a tall phone photo must not push
     the choices off the wall. */
  .picture {
    display: block;
    max-width: 100%;
    max-height: 100%;
    min-height: 0;
    object-fit: contain;
    border-radius: 10px;
    justify-self: center;
  }

  .recall.with-image {
    grid-template-rows: minmax(0, 1fr) auto auto;
  }

  .q-body {
    display: grid;
    min-height: 0;
    align-content: center;
  }

  .q-body.with-image,
  .typed-prompt.with-image {
    grid-template-columns: minmax(0, 1fr) minmax(0, 1.2fr);
    gap: 24px;
    align-items: center;
  }

  .tiles.pair {
    grid-template-columns: 1fr 1fr;
  }

  .typed-prompt {
    display: grid;
    min-height: 0;
    place-items: center;
    font-size: clamp(24px, 3.4vw, 60px);
    color: var(--ink-muted);
  }

  .typed-prompt p {
    margin: 0;
  }

  .typed {
    display: grid;
    gap: 10px;
    align-content: start;
    margin: 0;
    padding: 0;
    list-style: none;
    font-size: clamp(18px, 2.6vw, 48px);
  }

  .typed li {
    display: flex;
    justify-content: space-between;
    gap: 20px;
    padding: 12px 20px;
    border-radius: 10px;
    background: var(--stage-raised);
    color: var(--ink-muted);
  }

  .typed li.right {
    color: var(--ink);
    box-shadow: 0 0 0 3px var(--correct) inset;
  }

  .typed .n {
    font-family: var(--display);
    font-variant-numeric: tabular-nums;
  }

  .typed .none {
    justify-content: center;
  }

  .answered {
    margin: 0;
    color: var(--ink-muted);
    font-size: clamp(14px, 1.5vw, 24px);
    font-variant-numeric: tabular-nums;
  }

  .paused-note {
    color: var(--neon-pink);
  }

  /* At results the tiles are the chart, so they take the room rather than
     floating in the middle of it. */
  .result-tiles {
    align-content: stretch;
    grid-auto-rows: 1fr;
    height: 100%;
  }

  .results {
    display: grid;
    grid-template-columns: 1.4fr 1fr;
    gap: 40px;
  }

  .reveal {
    display: grid;
    gap: 6px;
    /* The eyebrow becomes the credit when someone won it outright, so it earns a
       little more presence than a label. */
    font-family: var(--body);
    font-size: clamp(30px, 4.2vw, 60px);
    font-weight: 600;
    line-height: 1.05;
    text-transform: none;
    text-wrap: balance;
  }

  .left,
  .right {
    display: grid;
    grid-template-rows: auto 1fr;
    gap: 20px;
    min-height: 0;
    align-content: start;
  }

  .final {
    display: grid;
    grid-template-rows: auto 1fr;
    align-content: end;
    gap: 18px;
    width: 100%;
    text-align: center;
  }

  .final :global(.podium) {
    align-self: end;
  }

  .final h1 {
    font-size: clamp(46px, 7.5vw, 100px);
  }

  @media (max-width: 900px) {
    .results,
    .tiles {
      grid-template-columns: 1fr;
    }
  }
</style>
