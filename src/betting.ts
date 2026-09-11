// Both calculator and matchup table call these functions. Spreads are always
// home-perspective handicaps; retain precision until display formatting.
export function impliedSpread(away: number | null, home: number | null, neutral: boolean | null, hfa: number | null): number | null {
  if (away === null || home === null || !Number.isFinite(away) || !Number.isFinite(home) || neutral === null) return null
  if (!neutral && (hfa === null || !Number.isFinite(hfa))) return null
  return away - home - (neutral ? 0 : hfa!)
}
export function signedPoints(value: number | null): string {
  if (value === null) return 'Data unavailable'
  const rounded = Math.round(value * 10) / 10
  return `${rounded > 0 ? '+' : ''}${Object.is(rounded, -0) ? '0.0' : rounded.toFixed(1)}`
}
export function lineLabel(home: string, spread: number | null): string {
  if (spread === null) return 'Data unavailable'
  return `${home} ${Math.abs(spread) < 0.05 ? 'PK' : signedPoints(spread)}`
}
export function favoredSide(home: string, away: string, spread: number | null): string {
  if (spread === null) return 'Data unavailable'
  return Math.abs(spread) < 0.05 ? 'Pick’em' : spread < 0 ? home : away
}
export function difference(model: number | null, market: number | null): number | null {
  return model === null || market === null ? null : model - market
}
export function valueSide(home: string, away: string, delta: number | null): string {
  if (delta === null) return 'Data unavailable'
  return Math.abs(delta) < 0.05 ? 'No difference' : delta < 0 ? home : away
}
export function compareValues(a: string | number | null, b: string | number | null, descending: boolean): number {
  if (a === null && b === null) return 0
  if (a === null) return 1
  if (b === null) return -1
  const diff = typeof a === 'number' && typeof b === 'number' ? a - b : String(a).localeCompare(String(b))
  return descending ? -diff : diff
}
