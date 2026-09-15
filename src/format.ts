// Display-only formatting. Values keep full precision everywhere else.
const MINUS = '−'

export const isNum = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value)

function round(value: number, digits: number): number {
  const rounded = Number(value.toFixed(digits))
  return Object.is(rounded, -0) ? 0 : rounded
}

/** Typographic minus for numbers inside display strings such as "Texas -4.5". */
export const minus = (text: string) => text.replace(/-(?=\d)/g, MINUS)

export function num(value: number | null | undefined, digits = 1): string {
  return isNum(value) ? minus(round(value, digits).toFixed(digits)) : '—'
}

export function signed(value: number | null | undefined, digits = 1): string {
  if (!isNum(value)) return '—'
  const rounded = round(value, digits)
  return `${rounded > 0 ? '+' : ''}${minus(rounded.toFixed(digits))}`
}

export function pct(value: number | null | undefined): string {
  if (!isNum(value)) return '—'
  if (value > 0 && value < 0.0005) return '<0.1%'
  return `${(value * 100).toFixed(1)}%`
}

export function formatUpdated(value?: string | null): string {
  if (!value) return 'Data unavailable'
  return `${new Date(value).toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit', timeZone: 'UTC' })} UTC`
}

export function formatLocal(value?: string | null): string {
  return value ? new Date(value).toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', timeZoneName: 'short' }) : 'Data unavailable'
}

export const weekLabel = (week: number | null | undefined) => week == null ? 'Week unavailable' : `Week ${week}`
export const weekSlug = (week: number | null | undefined) => week == null ? 'latest' : `week-${String(week).padStart(2, '0')}`
