import { useEffect, useState } from 'react'
import type { Game, GameSwing, Swing } from './data'
import { fmt, Info, Missing, pctText, TeamLink } from './components'
import { Link } from './router'

// Display helpers for games. Every number comes precomputed from games.json (R/publish/export_site_data.R).

export const QUALITY_INFO = 'Matchup quality (0–100) = 100 × average strength × closeness. Strength is each team’s power-rating percentile among FBS teams (non-FBS = 0); closeness is 1 − |2p − 1|, where p is the model win probability. High scores mean two strong teams in a close game.'
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

export function Matchup({ g, size = 22 }: { g: Game; size?: number }) {
  return <span className="cf-matchup">
    <TeamLink id={g.away_id} name={g.away_team} size={size} />
    <span className="cf-at" aria-label={g.neutral ? 'versus, neutral site' : 'at'}>{g.neutral ? 'vs' : 'at'}</span>
    <TeamLink id={g.home_id} name={g.home_team} size={size} />
  </span>
}

/** Compact card for the homepage module and phone layouts. */
const MIN_SEASONS = 100   // fewer matching simulated seasons: no percentage (same floor as the What if? warning)
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
export type Line = { game_id: string; market_spread: number | null; market_total?: number | null; market_provider: string | null; home_team: string; away_team: string; market_retrieved_at?: string | null }
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
