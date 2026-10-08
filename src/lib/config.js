// Whether this build was given a database. Kept apart from supabase.js so the
// app's entry can ask without pulling in the Supabase client, which the landing
// page never uses and would otherwise download on every first visit.
export const configured = Boolean(
  import.meta.env.VITE_SUPABASE_URL && import.meta.env.VITE_SUPABASE_ANON_KEY,
)

// Where a teacher writes with a question. A real inbox, and the same address
// the sign-up and reset emails come from, so a reply to one of those lands here.
export const CONTACT = 'hello@blurt.it.com'
