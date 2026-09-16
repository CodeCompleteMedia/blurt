/** 1st, 2nd, 3rd, 4th — including the 11th/12th/13th exceptions. */
export function ordinal(n) {
  if (n == null) return '—'
  const tens = n % 100
  if (tens >= 11 && tens <= 13) return `${n}th`
  return `${n}${['th', 'st', 'nd', 'rd'][n % 10] ?? 'th'}`
}
