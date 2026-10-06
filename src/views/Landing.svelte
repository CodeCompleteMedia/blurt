<script>
  // The front door. Two people arrive here and only one of them is shopping: a
  // teacher deciding whether to try blurt tomorrow, and a student who typed the
  // domain off the wall and wants their room. So the room-code box comes first,
  // above everything, and the rest of the page is for the teacher.
  //
  // The walkthrough is built from the app's own pieces (the countdown ring, the
  // answer tiles, the buzzer and the verdict buttons) so the page shows the room
  // the class will actually see, not a drawing of it.
  import AnswerTile from '../components/AnswerTile.svelte'
  import CountdownRing from '../components/CountdownRing.svelte'
  import { choiceFor } from '../lib/answers.js'
  import { calm } from '../lib/motion.js'
  import { setTheme, theme } from '../lib/theme.svelte.js'
  import doodles from '../assets/images/doodles.webp'

  // ------------------------------------------------------------ room code ---
  let code = $state('')
  let codeProblem = $state('')

  function joinRoom(event) {
    event.preventDefault()
    const clean = code.replace(/\s+/g, '').toUpperCase()
    if (!/^[A-Z0-9]{4,8}$/.test(clean)) {
      codeProblem = 'A room code is 4 to 8 letters and numbers, as shown on the board.'
      return
    }
    // The same address a scanned QR opens: straight to the name field, in the
    // room's own light.
    window.location.assign(`/j/${clean}`)
  }

  // ---------------------------------------------------------- one round ---
  const QUESTION = 'Which planet has the most known moons?'
  const ANSWERS = ['Jupiter', 'Saturn', 'Uranus', 'Neptune']
  const RIGHT = 1

  const BEATS = [
    { title: 'The choices stay hidden', body: 'The question goes up alone. For a few seconds, anyone who knows it can hit one button.' },
    { title: 'Someone claims the floor', body: 'The first press to reach the room wins. There is no tie to settle and no way to fake being first.' },
    { title: 'They say it out loud', body: 'You hear the answer and judge it with one key: Y for right, N for wrong.' },
    { title: 'Right scores big', body: 'A right blurt is worth 1,500 points. Wrong, and the choices go up for everyone else.' },
  ]

  let beat = $state(0)
  let playing = $state(!calm)
  let ringStart = $state(Date.now())

  function show(n) {
    beat = n
    if (n === 0) ringStart = Date.now()
  }

  // Advances itself while playing. Depends only on two primitives, so nothing
  // else on the page can restart it mid-beat.
  $effect(() => {
    if (!playing) return
    const id = setInterval(() => show((beat + 1) % BEATS.length), 3800)
    return () => clearInterval(id)
  })

  function pick(n) {
    playing = false
    show(n)
  }

  // -------------------------------------------------------------- pricing ---
  // Yearly is $72, which is $6 a month: a quarter off the monthly $8.
  let yearly = $state(false)
</script>

<svelte:head>
  <title>blurt · Know it? BLURT it!</title>
  <meta
    name="description"
    content="A live classroom quiz where the choices stay hidden until someone says the answer out loud. Students join from any phone with a room code."
  />
</svelte:head>

<div class="landing">
  <!-- Students first: the one thing a student came for, before anything else. -->
  <form class="door" onsubmit={joinRoom} aria-label="Join a room">
    <label for="door-code">Got a room code?</label>
    <div class="door-row">
      <input
        id="door-code"
        bind:value={code}
        oninput={() => (codeProblem = '')}
        placeholder="ABC12"
        autocomplete="off"
        autocapitalize="characters"
        autocorrect="off"
        spellcheck="false"
        maxlength="10"
        aria-describedby={codeProblem ? 'door-problem' : undefined}
      />
      <button type="submit">Join</button>
    </div>
    {#if codeProblem}<p id="door-problem" class="door-problem" role="alert">{codeProblem}</p>{/if}
  </form>

  <header class="top">
    <span class="wordmark brand">blurt!</span>
    <div class="top-end">
      <!-- The same choice as the account menu's Appearance: one preference per
           browser, so a teacher who likes it light sees the front door light. -->
      <button
        class="lights"
        onclick={() => setTheme(theme.mode === 'light' ? 'dark' : 'light')}
        aria-label={theme.mode === 'light' ? 'Switch to dark mode' : 'Switch to light mode'}
        title={theme.mode === 'light' ? 'Dark mode' : 'Light mode'}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true">
          {#if theme.mode === 'light'}
            <path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5Z" />
          {:else}
            <circle cx="12" cy="12" r="4" />
            <path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4" />
          {/if}
        </svg>
      </button>
      <a class="signin" href="#pricing">Pricing</a>
      <a class="signin" href="/host">Teacher sign in</a>
    </div>
  </header>

  <main>
    <section class="hero" style:--doodles="url({doodles})">
      <div class="hero-words">
        <h1>
          <span class="ask">Know it?</span>
          <span class="shout"><span class="wordmark">BLURT</span> it!</span>
        </h1>
        <p class="lede">
          A live quiz for your classroom where the choices stay hidden until someone says the
          answer out loud.
        </p>
        <div class="actions">
          <a class="cta" href="/host">Host a room free</a>
          <a class="quiet" href="#round">Watch a round</a>
        </div>
        <p class="fine">Students join from any phone. No accounts, no app to install.</p>
      </div>

      <div class="hero-buzzer" aria-hidden="true">
        <span class="buzzer">BLURT</span>
      </div>
    </section>

    <section id="round" class="round" aria-labelledby="round-title">
      <div class="round-head">
        <h2 id="round-title">One round, four beats</h2>
        <button class="play" onclick={() => (playing = !playing)} aria-pressed={!playing}>
          {playing ? 'Pause' : 'Play'}
        </button>
      </div>

      <div class="round-body">
        <ol class="beats">
          {#each BEATS as b, i}
            <li>
              <button class="beat" class:on={beat === i} aria-current={beat === i ? 'step' : undefined} onclick={() => pick(i)}>
                <span class="n bulbs">{i + 1}</span>
                <span class="beat-words">
                  <strong>{b.title}</strong>
                  <span>{b.body}</span>
                </span>
              </button>
            </li>
          {/each}
        </ol>

        <!-- A picture of the room at this beat: the wall, a phone, your screen. -->
        <div class="stage" aria-hidden="true">
          <div class="wall">
            <span class="wall-tag">The wall</span>
            {#if beat === 0}
              <p class="wall-q">{QUESTION}</p>
              <div class="wall-foot">
                <p class="wall-prompt">Know it? <strong>BLURT</strong> it!</p>
                {#key ringStart}<CountdownRing startedAt={ringStart} limit={8000} size={64} />{/key}
              </div>
            {:else if beat === 1 || beat === 2}
              <div class="floor">
                <span class="floor-label">Has the floor</span>
                <span class="floor-who">Rosa</span>
              </div>
            {:else}
              <div class="tiles">
                {#each ANSWERS as text, i}
                  <AnswerTile choice={choiceFor(i)} {text} state={i === RIGHT ? 'correct' : 'dimmed'} />
                {/each}
              </div>
              <p class="points"><span class="bulbs">+1,500</span> Rosa</p>
            {/if}
          </div>

          <div class="phone">
            <span class="phone-tag">Rosa's phone</span>
            {#if beat === 0}
              <span class="phone-note">Know it?</span>
              <span class="mini-buzzer">BLURT</span>
            {:else if beat < 3}
              <span class="phone-note">You have the floor</span>
              <span class="say">Say it</span>
              <span class="phone-note">Out loud, to the room.</span>
            {:else}
              <span class="phone-note">Right!</span>
              <span class="say bulbs gold">+1,500</span>
            {/if}
          </div>

          <div class="desk" class:lit={beat === 2}>
            <span class="desk-tag">Your screen</span>
            <p class="desk-answer">Answer: <strong>Saturn</strong></p>
            <div class="desk-verdict">
              <span class="yes">✓ Correct <kbd>Y</kbd></span>
              <span class="no">✗ Wrong <kbd>N</kbd></span>
            </div>
          </div>
        </div>
      </div>
      <p class="round-live" aria-live="polite">Step {beat + 1} of 4: {BEATS[beat].title}.</p>
    </section>

    <section class="screens" aria-labelledby="screens-title">
      <h2 id="screens-title">Three screens, one room</h2>
      <dl>
        <div>
          <dt>Your laptop</dt>
          <dd>You run it. Space moves the game on, Y and N judge a blurt, and the answer is always in front of you.</dd>
        </div>
        <div>
          <dt>The wall</dt>
          <dd>Any projector or classroom screen. The question, the clock, who has the floor and the leaderboard. No controls on it to fiddle with.</dd>
        </div>
        <div>
          <dt>Their phones</dt>
          <dd>A room code and a first name, nothing else. The phone shows the button and the letters, never the question, so a neighbour's screen gives nothing away.</dd>
        </div>
      </dl>
    </section>

    <section class="toolkit" aria-labelledby="toolkit-title">
      <h2 id="toolkit-title">Built for the person at the front</h2>

      <div class="keys" aria-label="Keyboard shortcuts while hosting">
        <span><kbd>Space</kbd> next</span>
        <span><kbd>Y</kbd> <kbd>N</kbd> judge</span>
        <span><kbd>E</kbd> +15s</span>
        <span><kbd>H</kbd> pause</span>
        <span><kbd>P</kbd> projector</span>
      </div>

      <ul class="tools">
        <li>
          <strong>See what they didn't know.</strong>
          After the game, the report leads with the questions fewer than half the room got right,
          and the wrong answer most of them chose.
        </li>
        <li>
          <strong>Bring the quiz you already have.</strong>
          Paste rows straight out of a spreadsheet, and choose per question whether it opens
          with a blurt round.
        </li>
        <li>
          <strong>Pair a screen once.</strong>
          Set up the classroom display one time, then send each new room to it from your laptop.
        </li>
        <li>
          <strong>Lights up or down.</strong>
          Dark or light, and the wall and every phone follow your choice.
        </li>
      </ul>
    </section>

    <section class="privacy" aria-labelledby="privacy-title">
      <h2 id="privacy-title">What students share</h2>
      <p>
        A first name and their answers. Students never create an account, give an email or install
        anything, and they can't read each other's answers. You can delete a game, and every answer in
        it, whenever you like.
      </p>
    </section>

    <section id="pricing" class="pricing" aria-labelledby="pricing-title">
      <div class="pricing-head">
        <h2 id="pricing-title">Free to start. One plan when you want more.</h2>
        <div class="period" role="group" aria-label="Billing period">
          <button aria-pressed={!yearly} onclick={() => (yearly = false)}>Monthly</button>
          <button aria-pressed={yearly} onclick={() => (yearly = true)}>Yearly <span class="save">save 25%</span></button>
        </div>
      </div>

      <div class="plans">
        <article class="plan" aria-labelledby="plan-free">
          <h3 id="plan-free">Free</h3>
          <p class="price"><span class="amount">$0</span></p>
          <p class="for">For trying blurt with a class or two.</p>
          <ul>
            <li>3 quizzes</li>
            <li>5 rooms a month</li>
            <li>Up to 15 students in a room</li>
            <li>Reports for the last 30 days</li>
            <li>1 paired display</li>
          </ul>
          <a class="plan-cta quiet-cta" href="/host">Start free</a>
        </article>

        <article class="plan paid" aria-labelledby="plan-teacher">
          <h3 id="plan-teacher">Teacher</h3>
          <p class="price">
            <span class="amount">{yearly ? '$72' : '$8'}</span>
            <span class="per">{yearly ? 'a year' : 'a month'}</span>
          </p>
          <p class="for">
            {yearly ? 'Works out to $6 a month, billed once a year.' : 'Billed monthly. Cancel any time.'}
          </p>
          <ul>
            <li>Unlimited quizzes</li>
            <li>Unlimited rooms</li>
            <li>Up to 60 students in a room</li>
            <li>Every report, kept for good</li>
            <li>Up to 10 paired displays</li>
            <li>Export reports as a spreadsheet</li>
          </ul>
          <a class="plan-cta" href="/host?plan={yearly ? 'year' : 'month'}">Get the Teacher plan</a>
        </article>
      </div>

      <p class="pricing-note">
        Students never pay and never need an account. Prices in US dollars; tax may apply.
      </p>
    </section>

    <section class="last">
      <h2>Your class, <span class="wordmark">tomorrow</span>.</h2>
      <p>Sign up, open the sample quiz, and put the room code on the board. It takes about a minute.</p>
      <a class="cta" href="/host">Host a room free</a>
    </section>
  </main>

  <footer>
    <span class="wordmark small">blurt!</span>
    <a href="/join">Join a room</a>
    <a href="/host">Teacher sign in</a>
  </footer>
</div>

<style>
  .landing {
    min-height: 100%;
    background: var(--stage);
    color: var(--ink);
    /* The window is the one scroller. This used to scroll itself at full
       height, which gave the page a second scrollbar. `clip`, not `hidden`, for
       the full-bleed doodles: hidden makes a scroll container that an anchor
       link can push sideways, which slid the whole page off its left edge. */
    overflow-x: clip;
  }

  main,
  .top,
  footer {
    width: 100%;
    max-width: 1180px;
    margin: 0 auto;
    padding-inline: calc(var(--gutter) + env(safe-area-inset-left, 0px))
      calc(var(--gutter) + env(safe-area-inset-right, 0px));
  }

  h2 {
    font-size: clamp(28px, 4.2vw, 52px);
    line-height: 1;
  }

  .wordmark {
    font-family: var(--marquee);
  }

  /* ------------------------------------------------------------- door --- */
  .door {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: center;
    gap: 8px 16px;
    padding: calc(12px + env(safe-area-inset-top, 0px)) var(--gutter) 12px;
    background: var(--stage-raised);
    border-bottom: 1px solid var(--line);
  }

  .door label {
    font-size: 14px;
    font-weight: 600;
  }

  .door-row {
    display: flex;
    gap: 8px;
  }

  .door input {
    width: 9.5em;
    padding: 8px 12px;
    border: 2px solid var(--line-strong);
    border-radius: var(--radius-md);
    background: var(--stage);
    color: var(--ink);
    font-family: var(--display);
    font-size: 18px;
    letter-spacing: 0.14em;
    text-transform: uppercase;
  }

  .door input::placeholder {
    color: var(--ink-muted);
    opacity: 0.6;
  }

  .door input:focus {
    border-color: var(--neon-cyan);
  }

  .door button {
    padding: 8px 18px;
    border-radius: var(--radius-md);
    background: var(--neon-cyan);
    color: var(--stage);
    font-weight: 700;
  }

  .door-problem {
    flex-basis: 100%;
    margin: 0;
    text-align: center;
    font-size: 14px;
    color: var(--wrong);
  }

  /* -------------------------------------------------------------- top --- */
  .top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding-block: 22px;
  }

  .brand {
    font-size: 28px;
    color: var(--neon-pink);
    text-shadow: var(--text-glow-pink);
    text-transform: uppercase;
  }

  .signin {
    color: var(--ink-muted);
    font-size: 15px;
    text-underline-offset: 4px;
  }

  .signin:hover {
    color: var(--ink);
  }

  .top-end {
    display: flex;
    align-items: center;
    gap: 18px;
  }

  .lights {
    display: grid;
    place-items: center;
    width: 38px;
    height: 38px;
    border: 1px solid var(--line);
    border-radius: 50%;
    color: var(--ink-muted);
  }

  .lights:hover {
    border-color: var(--line-strong);
    color: var(--ink);
  }

  .lights svg {
    width: 18px;
    height: 18px;
    fill: none;
    stroke: currentColor;
    stroke-width: 1.8;
    stroke-linecap: round;
    stroke-linejoin: round;
  }

  /* ------------------------------------------------------------- hero --- */
  .hero {
    position: relative;
    isolation: isolate;
    display: grid;
    grid-template-columns: minmax(0, 1.35fr) minmax(0, 1fr);
    align-items: center;
    gap: 24px 48px;
    padding-block: clamp(24px, 6vw, 88px) clamp(56px, 9vw, 128px);
  }

  .hero::before {
    content: '';
    position: absolute;
    /* Full-bleed: the texture runs edge to edge, past the content column. */
    inset: 0 calc(50% - 50vw);
    z-index: -1;
    background: var(--doodles) center / 900px auto repeat;
    filter: invert(1);
    mix-blend-mode: screen;
    opacity: 0.1;
    /* Fades out toward the next section, so the texture belongs to the hero. */
    mask-image: linear-gradient(to bottom, black 55%, transparent);
    pointer-events: none;
  }

  :global([data-theme='light']) .hero::before {
    filter: none;
    mix-blend-mode: multiply;
  }

  h1 {
    display: grid;
    gap: 0.06em;
    font-size: clamp(44px, 7.2vw, 112px);
    line-height: 0.9;
  }

  .shout {
    white-space: nowrap;
  }

  .ask {
    font-size: 0.55em;
    color: var(--ink-muted);
  }

  .shout .wordmark {
    color: var(--neon-pink);
    text-shadow: var(--text-glow-pink);
  }

  .lede {
    max-width: 34ch;
    margin: 28px 0 0;
    font-size: clamp(19px, 2vw, 24px);
    line-height: 1.5;
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 14px 24px;
    margin-top: 32px;
  }

  .cta {
    display: inline-block;
    padding: 16px 28px 14px;
    border-radius: var(--radius-md);
    background: var(--neon-pink);
    color: var(--on-pink);
    box-shadow: 0 6px 0 var(--neon-pink-deep);
    font-family: var(--display);
    font-size: clamp(17px, 1.6vw, 20px);
    letter-spacing: 0.03em;
    text-decoration: none;
    text-transform: uppercase;
    transition:
      transform 0.12s cubic-bezier(0.22, 1, 0.36, 1),
      box-shadow 0.12s cubic-bezier(0.22, 1, 0.36, 1);
  }

  .cta:hover {
    transform: translateY(2px);
    box-shadow: 0 4px 0 var(--neon-pink-deep);
  }

  .cta:active {
    transform: translateY(6px);
    box-shadow: 0 0 0 var(--neon-pink-deep);
  }

  .quiet {
    color: var(--ink);
    font-weight: 600;
    text-underline-offset: 5px;
  }

  .fine {
    margin: 22px 0 0;
    color: var(--ink-muted);
    font-size: 15px;
  }

  .hero-buzzer {
    display: grid;
    place-items: center;
  }

  /* The phone's button, at billboard size. */
  .buzzer {
    display: grid;
    place-items: center;
    width: min(100%, 320px);
    aspect-ratio: 1;
    border-radius: 50%;
    background: var(--neon-pink);
    color: var(--on-pink);
    box-shadow:
      0 14px 0 var(--neon-pink-deep),
      0 0 70px 10px #ff2e9766;
    font-family: var(--display);
    font-size: clamp(40px, 5.4vw, 72px);
    animation: press 3.8s cubic-bezier(0.22, 1, 0.36, 1) infinite;
  }

  /* The global reduced-motion rule shortens animations to nothing, which for a
     looping one means a flicker. This one simply stops. */
  @media (prefers-reduced-motion: reduce) {
    .buzzer {
      animation: none;
    }
  }

  @keyframes press {
    0%,
    70%,
    100% {
      transform: translateY(0);
      box-shadow:
        0 14px 0 var(--neon-pink-deep),
        0 0 70px 10px #ff2e9766;
    }
    76% {
      transform: translateY(11px);
      box-shadow:
        0 3px 0 var(--neon-pink-deep),
        0 0 110px 22px #ff2e97a6;
    }
  }

  /* ------------------------------------------------------------ round --- */
  .round {
    padding-block: clamp(48px, 8vw, 104px);
    border-top: 1px solid var(--line);
  }

  .round-head {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 16px;
    margin-bottom: clamp(24px, 4vw, 44px);
  }

  .play {
    padding: 7px 16px;
    border: 1px solid var(--line-strong);
    border-radius: var(--radius-pill);
    color: var(--ink);
    font-size: 14px;
  }

  .round-body {
    display: grid;
    grid-template-columns: minmax(0, 0.8fr) minmax(0, 1.4fr);
    gap: clamp(24px, 4vw, 56px);
    align-items: start;
  }

  .beats {
    display: grid;
    gap: 6px;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .beat {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 16px;
    width: 100%;
    padding: 14px 16px;
    border-radius: var(--radius-md);
    color: var(--ink-muted);
    text-align: left;
    transition: background 0.3s cubic-bezier(0.22, 1, 0.36, 1);
  }

  .beat:hover {
    background: var(--stage-raised);
  }

  .beat.on {
    background: var(--stage-raised);
    color: var(--ink);
  }

  .n {
    font-size: 30px;
    line-height: 1;
    color: var(--ink-muted);
  }

  .beat.on .n {
    color: var(--neon-cyan);
  }

  .beat-words {
    display: grid;
    gap: 4px;
    font-size: 15px;
    line-height: 1.45;
  }

  .beat-words strong {
    font-size: 17px;
    color: var(--ink);
  }

  .beat:not(.on) .beat-words span {
    display: none;
  }

  /* The room at this beat. Sized from its own width, so it reads the same in
     a phone's column as beside the steps on a laptop. */
  .stage {
    container-type: inline-size;
    position: relative;
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    grid-template-rows: auto auto;
    gap: 14px;
  }

  .wall,
  .phone,
  .desk {
    position: relative;
    border: 1px solid var(--line-strong);
    border-radius: var(--radius-lg);
    background: var(--stage-raised);
  }

  .wall-tag,
  .phone-tag,
  .desk-tag {
    position: absolute;
    top: -9px;
    left: 14px;
    padding: 0 8px;
    background: var(--stage);
    color: var(--ink-muted);
    font-size: 11px;
    letter-spacing: 0.16em;
    text-transform: uppercase;
  }

  .wall {
    grid-row: 1 / span 2;
    display: grid;
    align-content: center;
    gap: 3cqi;
    aspect-ratio: 16 / 10;
    padding: 4cqi;
  }

  .wall-q {
    margin: 0;
    font-size: clamp(18px, 4.6cqi, 34px);
    font-weight: 600;
    line-height: 1.1;
    text-wrap: balance;
  }

  .wall-foot {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .wall-prompt {
    margin: 0;
    color: var(--ink-muted);
    font-size: clamp(14px, 2.6cqi, 20px);
  }

  .wall-prompt strong {
    color: var(--neon-pink);
  }

  .floor {
    display: grid;
    justify-items: center;
    gap: 1cqi;
  }

  .floor-label {
    color: var(--ink-muted);
    font-size: clamp(11px, 1.8cqi, 14px);
    letter-spacing: 0.18em;
    text-transform: uppercase;
  }

  .floor-who {
    font-family: var(--display);
    font-size: clamp(40px, 11cqi, 96px);
    line-height: 1;
    color: var(--neon-pink);
    text-shadow: var(--text-glow-pink);
  }

  .tiles {
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
    min-width: 0;
    gap: 1.4cqi;
    font-size: 13px;
  }

  .tiles :global(.tile) {
    min-height: 0;
    padding: 1.6cqi 2cqi;
  }

  .tiles :global(.text) {
    font-size: clamp(13px, 2.4cqi, 20px);
  }

  .tiles :global(.letter) {
    width: clamp(24px, 4.4cqi, 40px);
    font-size: clamp(11px, 2cqi, 18px);
  }

  .points {
    margin: 0;
    font-size: clamp(14px, 2.4cqi, 20px);
    color: var(--ink-muted);
  }

  .points .bulbs {
    color: var(--gold-ink);
    font-size: 1.3em;
    margin-right: 6px;
  }

  .phone {
    display: grid;
    justify-items: center;
    align-content: center;
    gap: 10px;
    width: clamp(108px, 22cqi, 168px);
    aspect-ratio: 9 / 16;
    padding: 12px;
    border-radius: 22px;
  }

  .mini-buzzer {
    display: grid;
    place-items: center;
    width: 82%;
    aspect-ratio: 1;
    border-radius: 50%;
    background: var(--neon-pink);
    color: var(--on-pink);
    box-shadow:
      0 6px 0 var(--neon-pink-deep),
      0 0 22px 2px #ff2e9780;
    font-family: var(--display);
    font-size: clamp(14px, 3.4cqi, 22px);
    transition:
      transform 0.18s cubic-bezier(0.22, 1, 0.36, 1),
      box-shadow 0.18s cubic-bezier(0.22, 1, 0.36, 1);
  }

  .say {
    font-family: var(--display);
    font-size: clamp(18px, 4.4cqi, 30px);
    line-height: 1;
    color: var(--neon-pink);
    text-shadow: var(--text-glow-pink);
    text-transform: uppercase;
  }

  .say.gold {
    font-family: var(--bulbs);
    color: var(--gold-ink);
    text-shadow: none;
  }

  .phone-note {
    font-size: 12px;
    color: var(--ink-muted);
    text-align: center;
  }

  .desk {
    display: grid;
    gap: 10px;
    align-content: center;
    width: clamp(108px, 22cqi, 168px);
    padding: 16px 12px 12px;
    transition: border-color 0.3s cubic-bezier(0.22, 1, 0.36, 1);
  }

  .desk.lit {
    border-color: var(--neon-cyan);
    box-shadow: var(--glow-cyan);
  }

  .desk-answer {
    margin: 0;
    font-size: 12px;
    color: var(--ink-muted);
  }

  .desk-answer strong {
    display: block;
    color: var(--ink);
    font-size: 15px;
  }

  .desk-verdict {
    display: grid;
    gap: 6px;
  }

  .desk-verdict span {
    padding: 6px 8px;
    border-radius: 8px;
    color: var(--stage);
    font-size: 12px;
    font-weight: 700;
  }

  .yes {
    background: var(--correct);
  }

  .no {
    background: var(--wrong);
  }

  kbd {
    display: inline-block;
    padding: 1px 6px;
    border-radius: 4px;
    background: rgba(11, 7, 22, 0.25);
    font: inherit;
    font-size: 0.85em;
  }

  .round-live {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }

  /* ---------------------------------------------------------- screens --- */
  .screens {
    padding-block: clamp(48px, 8vw, 104px);
    border-top: 1px solid var(--line);
  }

  .screens dl {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 0 clamp(24px, 4vw, 56px);
    margin: clamp(28px, 4vw, 48px) 0 0;
  }

  .screens dt {
    font-family: var(--display);
    font-size: clamp(22px, 2.6vw, 34px);
    color: var(--neon-cyan);
    line-height: 1;
  }

  .screens dl > div:nth-child(2) dt {
    color: var(--neon-pink);
  }

  .screens dl > div:nth-child(3) dt {
    color: var(--neon-yellow);
  }

  .screens dd {
    margin: 14px 0 0;
    max-width: 34ch;
    font-size: 17px;
    line-height: 1.55;
    color: var(--ink-muted);
  }

  /* ---------------------------------------------------------- toolkit --- */
  .toolkit {
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(0, 1.2fr);
    gap: 32px clamp(32px, 5vw, 72px);
    padding-block: clamp(48px, 8vw, 104px);
    border-top: 1px solid var(--line);
  }

  .keys {
    grid-column: 1;
    display: flex;
    flex-wrap: wrap;
    gap: 12px 18px;
    align-content: start;
    font-size: 15px;
    color: var(--ink-muted);
  }

  .keys kbd {
    padding: 6px 10px;
    border: 1px solid var(--line-strong);
    border-bottom-width: 3px;
    border-radius: 8px;
    background: var(--stage-raised);
    color: var(--ink);
    font-family: var(--display);
    font-size: 15px;
  }

  .tools {
    grid-column: 2;
    grid-row: 1 / span 2;
    display: grid;
    gap: 26px;
    margin: 0;
    padding: 0;
    list-style: none;
    font-size: 17px;
    line-height: 1.55;
    color: var(--ink-muted);
  }

  .tools strong {
    display: block;
    margin-bottom: 4px;
    color: var(--ink);
    font-size: 19px;
  }

  /* ---------------------------------------------------------- privacy --- */
  .privacy {
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(0, 1.2fr);
    gap: 20px clamp(32px, 5vw, 72px);
    padding-block: clamp(48px, 8vw, 96px);
    border-top: 1px solid var(--line);
  }

  .privacy p {
    margin: 0;
    max-width: 58ch;
    font-size: 19px;
    line-height: 1.6;
  }

  /* ---------------------------------------------------------- pricing --- */
  .pricing {
    padding-block: clamp(48px, 8vw, 104px);
    border-top: 1px solid var(--line);
  }

  .pricing-head {
    display: flex;
    flex-wrap: wrap;
    align-items: end;
    justify-content: space-between;
    gap: 20px 32px;
    margin-bottom: clamp(28px, 4vw, 48px);
  }

  .pricing-head h2 {
    max-width: 16ch;
  }

  .period {
    display: inline-grid;
    grid-auto-flow: column;
    padding: 4px;
    border: 1px solid var(--line-strong);
    border-radius: var(--radius-pill);
  }

  .period button {
    padding: 8px 16px;
    border-radius: var(--radius-pill);
    color: var(--ink-muted);
    font-size: 14px;
    font-weight: 600;
    transition: background 0.2s cubic-bezier(0.22, 1, 0.36, 1);
  }

  .period button[aria-pressed='true'] {
    background: var(--stage-high);
    color: var(--ink);
  }

  .save {
    margin-left: 4px;
    color: var(--neon-pink);
    font-weight: 700;
  }

  .plans {
    display: grid;
    grid-template-columns: minmax(0, 0.85fr) minmax(0, 1fr);
    gap: clamp(16px, 3vw, 32px);
    align-items: stretch;
  }

  .plan {
    display: grid;
    grid-template-rows: auto auto auto 1fr auto;
    gap: 12px;
    padding: clamp(24px, 3vw, 36px);
    border: 1px solid var(--line-strong);
    border-radius: var(--radius-lg);
  }

  /* The paid plan carries the brand colour; the free one stays quiet. */
  .plan.paid {
    border: 2px solid var(--neon-pink);
    background: var(--stage-raised);
    box-shadow: var(--glow-pink);
  }

  .plan h3 {
    font-size: clamp(22px, 2.4vw, 30px);
  }

  .paid h3 {
    color: var(--neon-pink);
  }

  .price {
    display: flex;
    align-items: baseline;
    gap: 10px;
    margin: 4px 0 0;
  }

  .amount {
    font-family: var(--display);
    font-size: clamp(44px, 5.5vw, 68px);
    line-height: 1;
  }

  .per {
    color: var(--ink-muted);
    font-size: 17px;
  }

  .for {
    margin: 0;
    color: var(--ink-muted);
    font-size: 16px;
    min-height: 1.5em;
  }

  .plan ul {
    display: grid;
    gap: 10px;
    align-content: start;
    margin: 8px 0 0;
    padding: 0;
    list-style: none;
    font-size: 17px;
  }

  .plan li {
    display: grid;
    grid-template-columns: 18px 1fr;
    gap: 10px;
    align-items: baseline;
  }

  .plan li::before {
    content: '✓';
    color: var(--ink-muted);
    font-weight: 700;
  }

  .paid li::before {
    color: var(--neon-pink);
  }

  .plan-cta {
    justify-self: start;
    margin-top: 16px;
    padding: 13px 22px 11px;
    border-radius: var(--radius-md);
    background: var(--neon-pink);
    color: var(--on-pink);
    box-shadow: 0 5px 0 var(--neon-pink-deep);
    font-family: var(--display);
    font-size: 15px;
    letter-spacing: 0.03em;
    text-decoration: none;
    text-transform: uppercase;
  }

  .plan-cta.quiet-cta {
    background: none;
    color: var(--ink);
    box-shadow: none;
    border: 1px solid var(--line-strong);
  }

  .pricing-note {
    margin: 20px 0 0;
    color: var(--ink-muted);
    font-size: 14px;
  }

  @media (max-width: 760px) {
    .plans {
      grid-template-columns: minmax(0, 1fr);
    }

    /* On a phone the paid plan leads: it's the one with something to explain. */
    .plan.paid {
      order: -1;
    }
  }

  /* ------------------------------------------------------------- last --- */
  .last {
    display: grid;
    justify-items: start;
    gap: 20px;
    padding-block: clamp(64px, 10vw, 140px);
    border-top: 1px solid var(--line);
  }

  .last h2 {
    font-size: clamp(40px, 7vw, 104px);
  }

  .last h2 .wordmark {
    color: var(--neon-pink);
    text-shadow: var(--text-glow-pink);
  }

  .last p {
    margin: 0 0 8px;
    max-width: 46ch;
    font-size: 19px;
    line-height: 1.55;
    color: var(--ink-muted);
  }

  /* ----------------------------------------------------------- footer --- */
  footer {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 12px 28px;
    padding-block: 28px calc(28px + env(safe-area-inset-bottom, 0px));
    border-top: 1px solid var(--line);
    color: var(--ink-muted);
    font-size: 14px;
  }

  .small {
    margin-right: auto;
    font-size: 18px;
    color: var(--neon-pink);
    text-transform: uppercase;
  }

  footer a {
    color: inherit;
    text-underline-offset: 4px;
  }

  /* ------------------------------------------------------------ small --- */
  @media (max-width: 860px) {
    .hero,
    .round-body,
    .toolkit,
    .privacy {
      grid-template-columns: minmax(0, 1fr);
    }

    .hero-buzzer {
      order: -1;
      justify-items: start;
    }

    .buzzer {
      width: min(52vw, 220px);
    }

    .tools,
    .keys {
      grid-column: 1;
      grid-row: auto;
    }

    .screens dl {
      grid-template-columns: minmax(0, 1fr);
      gap: 32px;
    }

  }

  @media (max-width: 520px) {
    .stage {
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
      grid-template-rows: auto auto;
    }

    .wall {
      grid-row: auto;
      grid-column: 1 / -1;
    }

    .phone,
    .desk {
      width: auto;
    }

    .phone {
      aspect-ratio: auto;
      padding: 18px 12px 12px;
    }

    .mini-buzzer {
      width: 64%;
    }
  }
</style>
