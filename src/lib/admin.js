// The platform admin's reads and actions. Every one of these is checked in the
// database against the admin list (migration 0033); this file decides nothing.
// A teacher who calls them gets "admins only", whatever the page shows.

import { db } from './supabase.js'

function fail(error) {
  throw new Error(error.message ?? 'Something went wrong')
}

/** Whether the signed-in account is on the admin list. Says nothing about anyone else. */
export async function amAdmin() {
  const { data, error } = await db.rpc('is_platform_admin')
  if (error) return false
  return data === true
}

export async function adminOverview() {
  const { data, error } = await db.rpc('admin_overview')
  if (error) fail(error)
  return data?.[0] ?? null
}

export async function adminSignups(days = 30) {
  const { data, error } = await db.rpc('admin_signups', { p_days: days })
  if (error) fail(error)
  return data ?? []
}

export async function adminTeachers() {
  const { data, error } = await db.rpc('admin_teachers')
  if (error) fail(error)
  return data ?? []
}

export async function suspendTeacher(userId, suspend) {
  const { error } = await db.rpc('admin_suspend_teacher', { p_user: userId, p_suspend: suspend })
  if (error) fail(error)
}

export async function deleteTeacher(userId) {
  const { error } = await db.rpc('admin_delete_teacher', { p_user: userId })
  if (error) fail(error)
}
