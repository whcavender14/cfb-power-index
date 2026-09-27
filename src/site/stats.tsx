// Team stat definitions shared by the team page (Stats) and the matchup page, so labels, formats, rank direction and
// "lower is better" notes are identical. Values and FBS ranks come precomputed from efficiency.json
// (R/publish/team_efficiency.R, R/publish/team_basic_stats.R); rank 1 is always best.
import { fmt, fmtSigned, Info, Missing } from './components'
import type { Efficiency } from './data'

export type StatDef = { key: string; label: string; show: (v: number) => string; lower?: boolean; neutral?: boolean; info?: string }
export type StatGroup = { id: string; title: string; note?: string; defs: StatDef[]; raw?: boolean }

const n1 = (v: number) => fmt(v, 1)!
const pct = (v: number) => `${(v * 100).toFixed(1)}%`
const epa = (v: number) => fmtSigned(v, 2)!
export const STAT_GROUPS: StatGroup[] = [
  { id: 'scoring', title: 'Scoring and ball security', defs: [
    { key: 'ppg', label: 'Points per game', show: n1 },
    { key: 'papg', label: 'Points allowed per game', show: n1, lower: true },
    { key: 'third_pct', label: 'Third-down conversions', show: pct },
    { key: 'to_margin', label: 'Turnover margin', show: v => fmtSigned(v, 0)!, info: 'Opponent turnovers minus own turnovers, season total (not per game).' },
    { key: 'pen_ypg', label: 'Penalty yards per game', show: n1, lower: true },
  ] },
  { id: 'offense', title: 'Offense', note: 'yards per game', defs: [
    { key: 'ypg', label: 'Total yards', show: n1 },
    { key: 'pass_ypg', label: 'Passing yards', show: n1, info: 'Net passing yards (sack yardage subtracted).' },
    { key: 'rush_ypg', label: 'Rushing yards', show: n1 },
    { key: 'ypp', label: 'Yards per play', show: v => fmt(v, 2)!, info: 'Total yards divided by pass attempts plus rush attempts. Sacks count as rushes in the box score, so they are included.' },
    { key: 'fd_pg', label: 'First downs', show: n1 },
    { key: 'pass_share', label: 'Pass / rush split', show: v => `${Math.round(v * 100)}% / ${100 - Math.round(v * 100)}%`, neutral: true, info: 'Share of plays that were passes (pass attempts / (pass + rush attempts)). Rank 1 = most pass-heavy; neither end is better.' },
  ] },
  { id: 'defense', title: 'Defense', note: 'yards allowed per game · lower is better', defs: [
    { key: 'ya_pg', label: 'Total yards allowed', show: n1, lower: true },
    { key: 'pass_ya_pg', label: 'Passing yards allowed', show: n1, lower: true },
    { key: 'rush_ya_pg', label: 'Rushing yards allowed', show: n1, lower: true },
  ] },
  { id: 'efficiency', title: 'Efficiency', note: 'EPA per play, raw', raw: true, defs: [
    { key: 'net_epa', label: 'Net EPA/play', show: epa, info: 'Offense EPA per play minus defense EPA per play allowed. EPA = expected points added (CFBD’s ppa).' },
    { key: 'sr', label: 'Success rate', show: pct, info: 'Share of plays that gain enough: 50% of the distance on 1st down, 70% on 2nd, 100% on 3rd and 4th.' },
    { key: 'off_epa', label: 'Offense EPA/play', show: epa },
    { key: 'off_rush_epa', label: 'Offense, rushing', show: epa },
    { key: 'off_pass_epa', label: 'Offense, passing', show: epa },
    { key: 'def_epa', label: 'Defense EPA/play allowed', show: epa, lower: true },
    { key: 'def_rush_epa', label: 'Defense, rushing', show: epa, lower: true },
    { key: 'def_pass_epa', label: 'Defense, passing', show: epa, lower: true },
  ] },
]

export const statValue = (e: Efficiency | undefined, key: string) => (e as Record<string, number | null | undefined> | undefined)?.[key] ?? null
export const statRank = (e: Efficiency | undefined, key: string) => statValue(e, `${key}_rank`)
/** Share of FBS teams ranked below: 1 = best, 0 = worst (the same for "lower is better" stats, whose ranks are already inverted). */
export const goodness = (rank: number | null, total: number) => rank == null ? null : total > 1 ? (total - rank) / (total - 1) : 1
export const tone = (g: number | null) => g == null ? '' : g >= 2 / 3 ? 'is-good' : g < 1 / 3 ? 'is-bad' : ''

export function StatRow({ d, e, total }: { d: StatDef; e: Efficiency | undefined; total: number }) {
  const v = statValue(e, d.key), r = statRank(e, d.key), g = goodness(r, total)
  return <div className="cf-eff-row">
    <dt>{d.label}{d.lower && <span className="cf-lower" title="Lower is better">↓ better</span>}{d.info && <Info text={d.info} label={`About ${d.label.toLowerCase()}`} />}</dt>
    <dd className="cf-eff-val cf-num">{v == null ? <Missing /> : d.show(v)}</dd>
    <dd className="cf-eff-rank cf-num">{r ? `No. ${r}` : '—'}</dd>
    <dd className="cf-eff-bar" aria-hidden="true">{d.neutral
      ? v == null ? null : <><i className="is-split" style={{ width: `${v * 100}%` }} /></>
      : <i className={tone(g)} style={{ width: `${Math.max(3, (g ?? 0) * 100)}%` }} />}</dd>
  </div>
}
