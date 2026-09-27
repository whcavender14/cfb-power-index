import { useState } from 'react'
import { Pause, Play } from 'lucide-react'
import { fmt, TeamLogo } from './components'
import type { Game } from './data'
import { kickoffText, projection } from './games'
import { Link } from './router'

/** Home ticker: this week's biggest games (the same list as "Which games matter"), scrolling slowly. Each item opens
 *  the matchup page. Pauses on hover, focus or the button; static and scrollable under reduced motion. */
function Item({ g, hidden }: { g: Game; hidden?: boolean }) {
  const p = projection(g)
  return <li className="cf-tk-item">
    <Link to={`/games/${g.game_id}/`} className="cf-tk-link" tabIndex={hidden ? -1 : undefined}
      aria-label={`${g.away_team} ${g.neutral ? 'vs' : 'at'} ${g.home_team}: matchup breakdown`}>
      <TeamLogo id={g.away_id} name={g.away_team} size={22} />
      <span className="cf-tk-teams">{g.away_team} <span className="cf-muted">{g.neutral ? 'vs' : 'at'}</span> {g.home_team}</span>
      <TeamLogo id={g.home_id} name={g.home_team} size={22} />
      <span className="cf-tk-meta cf-muted">{kickoffText(g)}{p ? <> · {p.margin < 0.05 ? 'Even' : <>{p.favorite} by <span className="cf-num">{fmt(p.margin)}</span></>}</> : null}</span>
    </Link>
  </li>
}

export default function Ticker({ games, week }: { games: Game[]; week: number | null }) {
  const [paused, setPaused] = useState(false)
  if (!games.length) return null
  return <section className={`cf-tk${paused ? ' is-paused' : ''}`} aria-label={`Big games${week != null ? ` in Week ${week}` : ' this week'}`}>
    <span className="cf-tk-label">{week != null ? `Week ${week}` : 'This week'}</span>
    <div className="cf-tk-track">
      <ul className="cf-tk-row">{games.map(g => <Item key={g.game_id} g={g} />)}</ul>
      <ul className="cf-tk-row" aria-hidden="true">{games.map(g => <Item key={g.game_id} g={g} hidden />)}</ul>
    </div>
    <button type="button" className="cf-icon-btn cf-tk-btn" onClick={() => setPaused(p => !p)} aria-label={paused ? 'Resume ticker' : 'Pause ticker'}>{paused ? <Play size={14} /> : <Pause size={14} />}</button>
  </section>
}
