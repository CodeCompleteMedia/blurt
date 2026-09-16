// One client for the whole app, holding the publishable key that ships in the
// bundle. Nothing here is a secret: the boundary is the policies and functions
// in the database, not this file. See supabase/migrations/0002_functions.sql.

import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_ANON_KEY

export const configured = Boolean(url && key)

export const db = configured
  ? createClient(url, key, {
      // Nobody signs in. Players are identified by a seat token the database
      // issued, not by a Supabase session.
      auth: { persistSession: false, autoRefreshToken: false },
    })
  : null
