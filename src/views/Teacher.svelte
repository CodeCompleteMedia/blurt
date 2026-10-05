<script>
  // The teacher's places, behind sign-in and inside the shell. One download for
  // the three a teacher uses all lesson, and none of it is anything a student's
  // phone should fetch. The admin page loads separately: almost nobody sees it.
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
    {:else if route.view === 'admin'}
      {#await import('./Admin.svelte') then module}
        <module.default />
      {/await}
    {:else}
      <Edit quizId={route.quizId} />
    {/if}
  </TeacherShell>
</AuthGate>
