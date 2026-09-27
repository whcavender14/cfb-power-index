import { useMemo, useState } from 'react'
import { Pause, Play } from 'lucide-react'
import { TeamLogo, useData, useTeams } from './components'
import type { GamesDoc, TeamRow } from './data'
import { useLines, type Line } from './games'
import { Link } from './router'

/** Home ticker: the ten Vegas-quoted games of the week (public/data/betting.json) that feature the highest-ranked CFPi+
 *  teams. Kickoffs and O/U come from the quote; the spread shown is the CFPi implied line, rounded to the nearest half point. Pauses on hover,
 *  focus or the button; static and scrollable under reduced motion. */
const SIZE = 10
const UNRANKED = 9999
const MARQUEE = 30   // both teams ranked this high or better get a highlight
/** Static strip of logo + rank only (no scrolling). Set false for the scrolling Vegas/CFPi line ticker. */
const LOGO_ONLY = false

type Card = { line: Line; away: string; home: string; awayRank: number | null; homeRank: number | null }

const signed = (v: number) => v === 0 ? 'PK' : `${v < 0 ? '−' : '+'}${Math.abs(v)}`

function kickoff(l: Line) {
  if (!l.kickoff) return ''
  const d = new Date(l.kickoff)
  const day = d.toLocaleDateString(undefined, { weekday: 'short' })
  return l.time_tbd ? `${day} · TBD` : `${day} ${d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}`
}

function Row({ id, name, abbr, rank, spread, fav, total }: { id: string; name: string; abbr: string; rank: number | null; spread: number | null; fav: boolean; total: number | null }) {
  if (LOGO_ONLY) return <div className="cf-tk-team" title={name}><TeamLogo id={id} name={name} size={26} /><span className="cf-tk-rk cf-tk-rk-solo">{rank ?? ''}</span></div>
  return <div className={`cf-tk-team${fav ? ' cf-tk-fav' : ''}`}>
    <TeamLogo id={id} name={name} size={20} />
    <span className="cf-tk-rk">{rank ?? ''}</span>
    <span className="cf-tk-ab" title={name}>{abbr}</span>
    <span className="cf-tk-sp">{spread != null && (fav || spread === 0) ? signed(spread) : total != null ? total : ''}</span>
  </div>
}

function Item({ c, hidden, proj }: { c: Card; hidden?: boolean; proj: Map<string, number> }) {
  const teams = useTeams()
  const { line: l } = c
  const p = proj.get(l.game_id)                    // CFPi projected margin, home perspective, positive = home favored
  // Betting convention, nearest half point, negative = home favored. Never PK unless the margin is exactly 0.
  const s = p == null ? null : p === 0 ? 0 : -Math.sign(p) * Math.max(0.5, Math.round(Math.abs(p) * 2) / 2)
  const abbr = (id: string, name: string) => teams.get(id)?.abbreviation ?? name
  const both = c.awayRank != null && c.homeRank != null && c.awayRank <= MARQUEE && c.homeRank <= MARQUEE
  const hid = l.home_team_id!, aid = l.away_team_id!
  return <li className="cf-tk-item">
    <Link to={`/games/${l.game_id}/`} className={`cf-tk-link${both ? ' cf-tk-marquee' : ''}`} tabIndex={hidden ? -1 : undefined}
      aria-label={`${l.away_team} at ${l.home_team}: matchup breakdown${both ? ` (top ${MARQUEE} matchup)` : ''}`}>
      {!LOGO_ONLY && <div className="cf-tk-top cf-muted">{kickoff(l)}</div>}
      <Row id={aid} name={l.away_team} abbr={abbr(aid, l.away_team)} rank={c.awayRank} spread={s == null ? null : -s} fav={s != null && s > 0} total={l.market_total ?? null} />
      <Row id={hid} name={l.home_team} abbr={abbr(hid, l.home_team)} rank={c.homeRank} spread={s} fav={s != null && s < 0} total={l.market_total ?? null} />
    </Link>
  </li>
}

/** Deterministic pick: best (lowest) rank among the two teams, then the other team's rank, then kickoff, then game id.
 *  Unranked (non-FBS or unrated) teams sort last. */
export function pickGames(lines: Map<string, Line>, ranks: Map<string, number>): Card[] {
  const r = (id?: string) => (id ? ranks.get(id) : undefined) ?? UNRANKED
  return [...lines.values()]
    .filter(l => l.market_spread != null && l.home_team_id && l.away_team_id)
    .map(l => ({ line: l, away: l.away_team_id!, home: l.home_team_id!, awayRank: ranks.get(l.away_team_id!) ?? null, homeRank: ranks.get(l.home_team_id!) ?? null }))
    .sort((a, b) => {
      const [a1, a2] = [r(a.away), r(a.home)].sort((x, y) => x - y), [b1, b2] = [r(b.away), r(b.home)].sort((x, y) => x - y)
      return a1 - b1 || a2 - b2 || (a.line.kickoff ?? '').localeCompare(b.line.kickoff ?? '') || a.line.game_id.localeCompare(b.line.game_id)
    })
    .slice(0, SIZE)
}

export default function Ticker({ teams }: { teams: TeamRow[] }) {
  const lines = useLines()
  const [paused, setPaused] = useState(false)
  const games = useData<GamesDoc>('games.json')
  const proj = useMemo(() => new Map((games.data?.games ?? []).filter(g => g.spread_home != null).map(g => [g.game_id, g.spread_home!])), [games.data])
  const cards = useMemo(() => pickGames(lines, new Map(teams.filter(t => t.rank != null).map(t => [t.team_id, t.rank!]))), [lines, teams])
  if (!cards.length) return null
  if (LOGO_ONLY) return <section className="cf-tk cf-tk-static" aria-label="Top-ranked matchups this week">
    <ul className="cf-tk-row">{cards.map(c => <Item key={c.line.game_id} c={c} proj={proj} />)}</ul>
  </section>
  return <section className={`cf-tk${paused ? ' is-paused' : ''}`} aria-label="CFPi lines for top-ranked matchups this week">
    <div className="cf-tk-track">
      <ul className="cf-tk-row">{cards.map(c => <Item key={c.line.game_id} c={c} proj={proj} />)}</ul>
      <ul className="cf-tk-row" aria-hidden="true">{cards.map(c => <Item key={c.line.game_id} c={c} proj={proj} hidden />)}</ul>
    </div>
    <button type="button" className="cf-icon-btn cf-tk-btn" onClick={() => setPaused(p => !p)} aria-label={paused ? 'Resume ticker' : 'Pause ticker'}>{paused ? <Play size={14} /> : <Pause size={14} />}</button>
  </section>
}
