// Whether this build was given a database. Kept apart from supabase.js so the
// app's entry can ask without pulling in the Supabase client, which the landing
// page never uses and would otherwise download on every first visit.
export const configured = Boolean(
  import.meta.env.VITE_SUPABASE_URL && import.meta.env.VITE_SUPABASE_ANON_KEY,
)
