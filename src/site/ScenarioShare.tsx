import { pctText } from './components'
import { COUNTS_BELOW } from './scenario'

/** A share of the matching seasons: a percentage, or "k of n" when there are too few seasons for percentages. */
export function Share({ k, n, base }: { k: number; n: number; base?: number | null }) {
  if (n < COUNTS_BELOW) return <span className="cf-num">{k} of {n}</span>
  const p = k / n
  const d = base == null ? null : p - base
  return <span className="cf-num">{pctText(p)}{d != null && Math.abs(d) >= 0.0005 && <span className={`cf-delta ${d > 0 ? 'is-up' : 'is-down'}`}> {d > 0 ? '▲' : '▼'}{Math.abs(d * 100).toFixed(1)}</span>}</span>
}

