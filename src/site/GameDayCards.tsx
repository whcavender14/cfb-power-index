// Games page, "Cards" view: the same games and filters as the table, grouped by day, one compact card per game.
// Each card is a single link to the matchup page (a stretched link, so keyboard and screen-reader users get one stop per game).
import { Fragment } from 'react'
import { Missing, pctText, TeamLogo, useTeams } from './components'
import type { Game } from './data'
import { gradePick, kickoffText, projection, Quality } from './games'
import { Link } from './router'

export type DayCardsContext = {
  rankOf: Map<string, { rank: number; record: string | null }>
  quoteOf: (g: Game) => number | null          // current sportsbook spread, home perspective
  edgeOf: (g: Game) => number | null           // model minus line, home perspective
  openingOf: (g: Game) => number | null        // opening spread for past games
  modelOf: (g: Game) => number | null          // pre-game model margin for past games
  showWeek: boolean                            // "All weeks": say which week each card is from
}

const MARQUEE = 30   // same rule as the ticker: both teams ranked this high or better get the gold outline
const dayKey = (g: Game) => new Date(g.kickoff).toDateString()
const dayLabel = (g: Game) => new Date(g.kickoff).toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' })

export default function GameDayCards({ games, ctx }: { games: Game[]; ctx: DayCardsContext }) {
  const teams = useTeams()
  const ab = (id: string) => teams.get(id)?.abbreviation ?? teams.get(id)?.team ?? ''
  const ordered = [...games].sort((a, b) => Date.parse(a.kickoff) - Date.parse(b.kickoff))
  const days: { key: string; label: string; games: Game[] }[] = []
  for (const g of ordered) {
    const last = days[days.length - 1]
    if (last && last.key === dayKey(g)) last.games.push(g); else days.push({ key: dayKey(g), label: dayLabel(g), games: [g] })
  }
  return <div className="cf-dg-days">{days.map(d => <section key={d.key} aria-label={d.label}>
    <h2 className="cf-dg-day">{d.label} <small>{d.games.length} {d.games.length === 1 ? 'game' : 'games'}</small></h2>
    <div className="cf-dg-grid">{d.games.map(g => <Card key={g.game_id} g={g} ctx={ctx} ab={ab} />)}</div>
  </section>)}</div>
}

function Card({ g, ctx, ab }: { g: Game; ctx: DayCardsContext; ab: (id: string) => string }) {
  const final = g.status === 'final'
  const p = projection(g)
  const homeWon = (g.home_points ?? 0) > (g.away_points ?? 0), awayWon = (g.away_points ?? 0) > (g.home_points ?? 0)
  const side = (id: string, name: string, home: boolean) => {
    const r = ctx.rankOf.get(id)
    const pts = home ? g.home_points : g.away_points
    const prob = p?.prob == null ? null : (p.favoriteId === id ? p.prob : 1 - p.prob)
    const won = final && (home ? homeWon : awayWon), lost = final && (home ? awayWon : homeWon)
    return <div className={`cf-dg-team${won ? ' is-win' : ''}${lost ? ' is-lose' : ''}`}>
      <span className="cf-dg-rank">{r?.rank ?? ''}</span>
      <TeamLogo id={id} name={name} size={24} />
      <span className="cf-dg-name">{name}{r?.record && <small> {r.record}</small>}</span>
      <span className="cf-dg-val cf-num">{final ? (pts ?? '—') : prob != null ? pctText(prob) : '—'}</span>
    </div>
  }
  const k = final ? ctx.openingOf(g) : ctx.quoteOf(g), e = final ? null : ctx.edgeOf(g)
  const m = final ? ctx.modelOf(g) : null
  const gr = final ? gradePick(g, m, k) : null
  const mark = (good: boolean) => <b style={{ color: good ? 'var(--cf-up)' : 'var(--cf-down)' }}>{good ? '✓' : '✗'}</b>
  const proj = (margin: number, favId: string) => margin < 0.05 ? 'Even' : <>{ab(favId)} <span className="cf-num">by {margin.toFixed(1)}</span></>
  const lineText = (v: number) => v === 0 ? 'Pick’em' : `${ab(v < 0 ? g.home_id : g.away_id)} −${Math.abs(v)}`
  const pickLine = (v: number) => v === 0 ? 'PK' : v < 0 ? `−${Math.abs(v)}` : `+${v}`
  const ra = ctx.rankOf.get(g.away_id)?.rank, rh = ctx.rankOf.get(g.home_id)?.rank
  const marquee = ra != null && rh != null && ra <= MARQUEE && rh <= MARQUEE
  return <article className={`cf-dg${marquee ? ' is-marquee' : ''}`}>
    <Link to={`/games/${g.game_id}/`} className="cf-dg-link" aria-label={`${g.away_team} ${g.neutral ? 'vs' : 'at'} ${g.home_team}: matchup breakdown`} />
    <header className="cf-dg-head"><span>{ctx.showWeek && `Wk ${g.week} · `}{kickoffText(g, false)}{g.neutral ? ' · Neutral' : ''}</span>{final ? <span>Final</span> : <Quality value={g.quality} />}</header>
    {side(g.away_id, g.away_team, false)}
    {side(g.home_id, g.home_team, true)}
    <footer className="cf-dg-foot">
      {final
        ? <>
          <span><span className="cf-muted">Model</span> {m == null ? <Missing why="No pre-game rating for this game" /> : Math.abs(m) < 0.05 ? 'Even' : proj(Math.abs(m), m > 0 ? g.home_id : g.away_id)}</span>
          {k != null && <span><span className="cf-muted">Open</span> <span className="cf-num">{lineText(k)}</span></span>}
          {gr && <span className="cf-muted">Winner {gr.su == null ? '—' : mark(gr.su)} · Spread {gr.ats == null ? '—' : gr.ats === 'push' ? 'Push' : mark(gr.ats)}</span>}
        </>
        : <Fragment>
          <span>{p ? proj(p.margin, p.favoriteId) : <Missing why="No projection" />}</span>
          {k != null && <span><span className="cf-muted">Line</span> <span className="cf-num">{lineText(k)}</span></span>}
          {e != null && k != null && Math.abs(e) >= 0.05 && <span style={{ flexBasis: '100%', display: 'flex', gap: '2px 14px' }}>
            <span><span className="cf-muted">Pick</span> <b className="cf-num">{ab(e > 0 ? g.home_id : g.away_id)} {pickLine(e > 0 ? k : -k)}</b></span>
            <span><span className="cf-muted">Edge</span> <b className="cf-num" style={{ color: 'var(--cf-accent)' }}>{ab(e > 0 ? g.home_id : g.away_id)} +{Math.abs(e).toFixed(1)}</b></span>
          </span>}
        </Fragment>}
    </footer>
  </article>
}
