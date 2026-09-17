// The checks need a teacher, because only a quiz's owner can open a room — which
// is the point. They sign in as a dedicated test account from .env.local:
//
//   BLURT_TEST_EMAIL=...
//   BLURT_TEST_PASSWORD=...
//
// Create that account once through the app's own sign-in screen. It is never
// created from here: a script that mints accounts is a script that can be pointed
// at the wrong project.

import { createClient } from '@supabase/supabase-js'

export async function signInTeacher(url, key) {
  const email = process.env.BLURT_TEST_EMAIL
  const password = process.env.BLURT_TEST_PASSWORD
  if (!email || !password) {
    console.error('\n  These checks act as a teacher and need a test account.')
    console.error('  1. Create one at /host (any email you control, a throwaway password).')
    console.error('  2. Add BLURT_TEST_EMAIL and BLURT_TEST_PASSWORD to .env.local.\n')
    process.exit(2)
  }

  const teacher = createClient(url, key, { auth: { persistSession: false } })
  const { error } = await teacher.auth.signInWithPassword({ email, password })
  if (error) {
    console.error(`\n  Could not sign in as ${email}: ${error.message}\n`)
    process.exit(2)
  }

  // A brand-new account has nothing to host yet.
  let { data: quizzes } = await teacher.from('quizzes').select('id').limit(1)
  if (!quizzes?.length) {
    await teacher.rpc('copy_sample_quiz')
    ;({ data: quizzes } = await teacher.from('quizzes').select('id').limit(1))
  }
  return { teacher, quizId: quizzes[0].id }
}
