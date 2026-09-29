import { useEffect, useState } from 'react'
import type { Game, GameSwing, HistoryDoc, Swing } from './data'
import { fmt, Info, Missing, pctText, TeamLink } from './components'
import { Link } from './router'

// Display helpers for games. Every number comes precomputed from games.json (R/publish/export_site_data.R).

export const QUALITY_INFO = 'Matchup quality (0–100) = 100 × average strength × closeness. Strength is 1 − √((rank − 1) ÷ (ranked teams − 1)), so the top teams stand well apart without flattening the rest of the top 25 (non-FBS = 0); closeness is 1 − (2p − 1)², where p is the model win probability. High scores mean two highly ranked teams in a close game.'
export const WINPROB_INFO = 'Probability the favorite wins under the model’s own game model: margin ~ Normal(projected margin, σ = 15.65 points), the same model the season simulation draws from.'

export function kickoffText(g: Game, withDate = true): string {
  const d = new Date(g.kickoff)
  const date = d.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' })
  if (g.time_tbd) return withDate ? `${date} · TBD` : 'TBD'
  const time = d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })
  return withDate ? `${date} · ${time}` : time
}

/** "Alabama by 7.5" from the home-perspective projected margin; null when there is no projection. */
export function projection(g: Game): { favoriteId: string; favorite: string; margin: number; prob: number | null } | null {
  if (g.spread_home == null) return null
  const home = g.spread_home >= 0
  return { favoriteId: home ? g.home_id : g.away_id, favorite: home ? g.home_team : g.away_team, margin: Math.abs(g.spread_home),
    prob: g.win_prob_home == null ? null : home ? g.win_prob_home : 1 - g.win_prob_home }
}

export function ProjectionText({ g }: { g: Game }) {
  if (g.status === 'final') {
    const homeWon = (g.home_points ?? 0) > (g.away_points ?? 0)
    return <span className="cf-final"><span className="cf-final-tag">Final</span>
      <span className="cf-num">{g.away_points}–{g.home_points}</span>
      <span className="cf-muted"> {homeWon ? g.home_team : g.away_team}</span></span>
  }
  const p = projection(g)
  if (!p) return <Missing why="No projection" />
  return <span className="cf-proj">{p.margin < 0.05 ? 'Even' : <>{p.favorite} <span className="cf-num">by {fmt(p.margin)}</span></>}</span>
}

export function Quality({ value }: { value: number | null }) {
  if (value == null) return <Missing why="Quality is shown for upcoming games" />
  return <span className="cf-quality" aria-label={`Matchup quality ${value} of 100`}>
    <span className="cf-quality-meter" aria-hidden="true"><i style={{ width: `${value}%` }} /></span>
    <span className="cf-num">{value}</span>
  </span>
}

export function Matchup({ g, size = 22, ranks }: { g: Game; size?: number; ranks?: Map<string, { rank: number; record: string | null }> }) {
  // Rank sits next to the logo, record on the outside, so the two sides mirror each other.
  const sub = (id: string, away: boolean) => {
    const r = ranks?.get(id)
    if (!r) return undefined
    const rank = <b style={{ fontWeight: 600, color: 'var(--cf-ink-2)' }}>{r.rank}</b>, rec = r.record && <span>{r.record}</span>
    return <span style={{ display: 'inline-flex', gap: 8 }}>{away ? <>{rec}{rank}</> : <>{rank}{rec}</>}</span>
  }
  return <span className="cf-matchup">
    <TeamLink id={g.away_id} name={g.away_team} size={size} sub={sub(g.away_id, true)} />
    <span className="cf-at" aria-label={g.neutral ? 'versus, neutral site' : 'at'}>{g.neutral ? 'vs' : 'at'}</span>
    <TeamLink id={g.home_id} name={g.home_team} size={size} sub={sub(g.home_id, false)} />
  </span>
}

/** Compact card for the homepage module and phone layouts. */
const MIN_SEASONS = 100   // fewer matching simulated seasons: no percentage (same floor as the What If? warning)
function SwingFigure({ sw, team }: { sw: Swing; team: string }) {
  const one = (kind: 'W' | 'L', v: number, n: number) => n < MIN_SEASONS
    ? <b className="cf-swing-x" title={`Too few simulated seasons (${n}) for a reliable figure`}>{kind} —</b>
    : <b className={kind === 'W' ? 'cf-swing-w' : 'cf-swing-l'}>{kind === 'W' ? '▲' : '▼'} <span className="cf-num">{Math.round(v * 100) === 0 && v > 0 ? '<1' : Math.round(v * 100)}%</span></b>
  return <span className="cf-swing" title={`${team}: playoff chance ${pctText(sw.base)} now; ${pctText(sw.win)} if it wins, ${pctText(sw.lose)} if it loses`}>
    {one('W', sw.win, sw.n_win)}{one('L', sw.lose, sw.n_lose)}
  </span>
}
/** The two teams of a card, each with its playoff chance if it wins (▲) or loses (▼) this game. */
function SwingMatchup({ g, swing }: { g: Game; swing: GameSwing }) {
  const row = (id: string, name: string, sw?: Swing) => <div className="cf-swing-row"><TeamLink id={id} name={name} size={26} />{sw && <SwingFigure sw={sw} team={name} />}</div>
  return <div className="cf-swing-rows">{row(g.away_id, g.away_team, swing.away)}{row(g.home_id, g.home_team, swing.home)}</div>
}

export function GameCard({ g, swing }: { g: Game; swing?: GameSwing }) {
  const p = projection(g)
  return <article className="cf-gamecard">
    <div className="cf-gamecard-top"><Link to={`/games/${g.game_id}/`} className="cf-rowlink cf-muted" aria-label={`${g.away_team} ${g.neutral ? 'vs' : 'at'} ${g.home_team}: matchup breakdown`}>{kickoffText(g)}{g.neutral ? ' · Neutral' : ''}</Link><Quality value={g.quality} /></div>
    {swing && (swing.home || swing.away) ? <SwingMatchup g={g} swing={swing} /> : <Matchup g={g} size={26} />}
    <div className="cf-gamecard-foot">
      <ProjectionText g={g} />
      {p?.prob != null && <span className="cf-muted">Win prob. <span className="cf-num">{pctText(p.prob)}</span> <Info text={WINPROB_INFO} label="About win probability" /></span>}
    </div>
  </article>
}

/** One sportsbook quote per game for the upcoming week (public/data/betting.json), home perspective. Evaluation and
 *  display only: never an input to CFPi+. Optional: an empty map when the file or a game's quote is missing. */
export type Line = { game_id: string; market_spread: number | null; market_total?: number | null; market_provider: string | null; home_team: string; away_team: string; market_retrieved_at?: string | null
  week?: number; kickoff?: string; time_tbd?: boolean | null; away_team_id?: string; home_team_id?: string }
export function useLines(): Map<string, Line> {
  const [lines, setLines] = useState(new Map<string, Line>())
  useEffect(() => {
    fetch(`${import.meta.env.BASE_URL}data/betting.json`).then(r => r.ok ? r.json() : null).then(body => {
      if (body?.schema_version === 1 && Array.isArray(body.games)) setLines(new Map((body.games as Line[]).filter(g => g.market_spread != null).map(g => [g.game_id, g])))
    }).catch(() => { /* lines are optional */ })
  }, [])
  return lines
}
export const lineText = (l: Line) => l.market_spread === 0 ? 'Pick’em' : l.market_spread! < 0
  ? `${l.home_team} ${String(l.market_spread).replace('-', '−')}` : `${l.away_team} −${l.market_spread}`

/** Pre-game model margin (home perspective) for every final game, and each game's OPENING sportsbook spread, so games
 *  can be compared with what the model and the market expected. The margin is the same formula as the site's projections
 *  (home rating - away rating + home-field advantage, neutral sites 0) applied to the ratings published BEFORE the
 *  game's week (history.json; week 1 uses the preseason ratings); verified against changes.json. Opening spreads come
 *  from public/data/<season>/opening_lines.json (R/publish/export_opening_lines.R): home perspective, negative = the
 *  home team is favored. Reference only, never a model input. */
export type Review = { model: number | null; market: number | null }
export function useReview(games: Game[], history: HistoryDoc | null, season: number, hfa: number | null): Map<string, Review> {
  const [opening, setOpening] = useState(new Map<string, number>())
  useEffect(() => {
    let live = true
    fetch(`${import.meta.env.BASE_URL}data/${season}/opening_lines.json`).then(r => r.ok ? r.json() : null).catch(() => null).then(f => {
      if (!live || !Array.isArray(f?.games)) return
      setOpening(new Map((f.games as { game_id: string; opening_spread: number | null }[]).filter(x => x.opening_spread != null).map(x => [x.game_id, x.opening_spread!])))
    })
    return () => { live = false }
  }, [season])
  const out = new Map<string, Review>()
  for (const g of games) {
    let model: number | null = null
    if (g.status === 'final' && history && hfa != null && g.home_fbs && g.away_fbs) {
      const at = g.week <= 1 ? 0 : history.points.findIndex(p => p.week === g.week - 1)
      const ph = history.teams[g.home_id]?.power[at], pa = history.teams[g.away_id]?.power[at]
      if (at >= 0 && ph != null && pa != null) model = ph - pa + (g.neutral ? 0 : hfa)
    }
    out.set(g.game_id, { model, market: opening.get(g.game_id) ?? null })
  }
  return out
}

/** Grades one finished game from the model's pre-game margin and the opening spread (both home perspective; spread negative = home favored).
 *  su: the projected winner won (null = no pick or a tie). ats: the side the model liked against the line covered ('push' on a push; null = no pick/line). */
export function gradePick(g: Game, model: number | null, market: number | null): { su: boolean | null; ats: boolean | 'push' | null } {
  const actual = (g.home_points ?? 0) - (g.away_points ?? 0)
  const su = model == null || model === 0 || actual === 0 ? null : Math.sign(model) === Math.sign(actual)
  const edge = model == null || market == null ? 0 : model + market, cover = market == null ? 0 : actual + market
  const ats = edge === 0 ? null : cover === 0 ? 'push' : Math.sign(edge) === Math.sign(cover)
  return { su, ats }
}

/** Game Quality for every game of the season. Upcoming games use the published score (current ratings). Finished games
 *  are scored as they looked BEFORE kickoff: the same formula (100 x average strength x closeness) applied to the ratings
 *  published before that game's week (history.json; week 1 uses the preseason ratings). Non-FBS teams count as 0 strength. */
const phi = (z: number) => { const t = 1 / (1 + 0.2316419 * Math.abs(z)), d = 0.3989423 * Math.exp(-z * z / 2)
  const p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274)))); return z > 0 ? 1 - p : p }
export function gameQualities(games: Game[], history: HistoryDoc | null, hfa: number | null, sigma: number | null): Map<string, number> {
  const out = new Map<string, number>()
  for (const g of games) {
    if (g.status !== 'final') { if (g.quality != null) out.set(g.game_id, g.quality); continue }
    if (!history || hfa == null || !sigma) continue
    const at = g.week <= 1 ? 0 : history.points.findIndex(p => p.week === g.week - 1)
    if (at < 0) continue
    const series = (id: string) => history.teams[id]
    const ranked = Object.values(history.teams).filter(t => t.rank[at] != null).length
    const strength = (id: string, fbs: boolean) => { const r = series(id)?.rank[at]; return fbs && r != null && ranked > 1 ? 1 - Math.sqrt((r - 1) / (ranked - 1)) : 0 }
    const ph = series(g.home_id)?.power[at], pa = series(g.away_id)?.power[at]
    if (ph == null || pa == null) continue
    const p = phi((ph - pa + (g.neutral ? 0 : hfa)) / sigma)
    out.set(g.game_id, Math.round(100 * ((strength(g.home_id, g.home_fbs) + strength(g.away_id, g.away_fbs)) / 2) * (1 - (2 * p - 1) ** 2)))
  }
  return out
}
