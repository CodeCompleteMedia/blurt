<script>
  // A static set for looking at the design without a database behind it.
  // Not part of the app: served only at /harness.html in dev.
  import '../app.css'
  import AnswerTile from '../components/AnswerTile.svelte'
  import CountdownRing from '../components/CountdownRing.svelte'
  import Leaderboard from '../components/Leaderboard.svelte'
  import Podium from '../components/Podium.svelte'
  import { choiceFor } from '../lib/answers.js'

  // Every pair still in the room-code alphabet that a dot-matrix face could
  // blur together, plus one real-looking code. I/O/Q/0/1 are already gone.
  const CODES = ['B8S5Z2', 'UVWXYM', 'PT85U', 'GJKLNR']

  const standings = [
    { id: 'a', rank: 1, name: 'Rosa', score: 4820 },
    { id: 'b', rank: 2, name: 'Dev', score: 4110 },
    { id: 'c', rank: 3, name: 'Patiño', score: 3640 },
    { id: 'd', rank: 4, name: 'Bex', score: 2900 },
    { id: 'e', rank: 5, name: 'Sam', score: 2210 },
  ]

  const started = Date.now() - 12000
</script>

<main>
  <h2 class="eyebrow">Wordmark</h2>
  <div class="row">
    <span class="wordmark big">blurt!</span>
  </div>

  <h2 class="eyebrow">Room code — every confusable pair left in the alphabet</h2>
  <div class="codes">
    {#each CODES as c}
      <div class="code-big">{c}</div>
    {/each}
  </div>

  <h2 class="eyebrow">Answer tiles</h2>
  <div class="tiles">
    <AnswerTile choice={choiceFor(0)} text="Cascading Style Sheets" count={12} share={0.5} state="correct" />
    <AnswerTile choice={choiceFor(1)} text="Counter Strike Source" count={6} share={0.25} state="wrong" />
    <AnswerTile choice={choiceFor(2)} text="Computer Style Syntax" count={4} share={0.17} state="wrong" />
    <AnswerTile choice={choiceFor(3)} text="Cascading Sheet Styles" count={2} share={0.08} state="wrong" />
  </div>

  <h2 class="eyebrow">The phone — no question text, just the letter</h2>
  <div class="phone">
    {#each [0, 1, 2, 3] as i}
      <AnswerTile choice={choiceFor(i)} showText={false} onclick={() => {}} />
    {/each}
  </div>

  <h2 class="eyebrow">Countdown</h2>
  <div class="row">
    <CountdownRing startedAt={started} limit={30000} />
    <CountdownRing startedAt={started} limit={14000} />
    <CountdownRing startedAt={started} limit={30000} frozenAt={started + 5000} />
  </div>

  <h2 class="eyebrow">Leaderboard</h2>
  <Leaderboard {standings} />

  <h2 class="eyebrow">Podium</h2>
  <div class="podium-box"><Podium {standings} ceremony={false} /></div>
</main>

<style>
  main {
    max-width: 1100px;
    margin: 0 auto;
    padding: 40px var(--gutter) 120px;
    display: grid;
    gap: 14px;
  }

  h2 {
    margin-top: 34px;
    padding-bottom: 6px;
    border-bottom: 1px solid var(--line);
  }

  .row {
    display: flex;
    gap: 28px;
    align-items: center;
    flex-wrap: wrap;
  }

  .big {
    font-size: 72px;
    text-transform: uppercase;
  }

  .codes {
    display: flex;
    gap: 18px;
    flex-wrap: wrap;
  }

  /* Copied from Present.svelte's .code-big so this shows the real thing. */
  .code-big {
    padding: 0.12em 0.3em 0.12em 0.42em;
    border: 3px solid var(--neon-cyan);
    border-radius: var(--radius-lg);
    background: var(--stage-raised);
    box-shadow: var(--glow-cyan);
    font-family: var(--display);
    font-size: 64px;
    letter-spacing: 0.12em;
  }

  .tiles {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 14px;
  }

  /* Roughly an iPhone SE, the floor this has to work at. */
  .phone {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
    width: 320px;
    padding: 12px;
    border: 1px solid var(--line);
    border-radius: var(--radius-lg);
  }

  .podium-box {
    padding-top: 40px;
  }
</style>
