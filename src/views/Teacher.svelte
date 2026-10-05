<script>
  // The teacher's three places, behind sign-in and inside the shell. One
  // download for all three: a teacher moves between them all lesson, and none
  // of it is anything a student's phone should fetch.
  import AuthGate from '../components/AuthGate.svelte'
  import TeacherShell from '../components/TeacherShell.svelte'
  import Edit from './Edit.svelte'
  import Games from './Games.svelte'
  import Host from './Host.svelte'

  let { route } = $props()
</script>

<AuthGate>
  <TeacherShell current={route.view}>
    {#if route.view === 'host'}
      <Host />
    {:else if route.view === 'games'}
      <Games gameId={route.gameId} />
    {:else}
      <Edit quizId={route.quizId} />
    {/if}
  </TeacherShell>
</AuthGate>
