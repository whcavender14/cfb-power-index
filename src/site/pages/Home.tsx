import type { ReactNode } from 'react'
import { DataGate, Freshness, Info, Movement, Num, Pct, TeamLink, useData } from '../components'
import type { IndexDoc, TeamRow } from '../data'
import { GameCard, QUALITY_INFO } from '../games'
import { Link } from '../router'

// The homepage answers four questions, each a short preview that links to its full page. It loads index.json
// only (ratings, movement, per-team odds and the week's top games): no game list, team files or simulation data.
function Question({ id, q, more, to, children, info }: { id: string; q: string; more: string; to: string; children: ReactNode; info?: ReactNode }) {
  return <section className="cf-panel cf-q" aria-labelledby={id}>
    <div className="cf-panel-head"><h2 id={id}>{q}{info}</h2></div>
    {children}
    <Link to={to} className="cf-more cf-q-more">{more}</Link>
  </section>
}

function Movers({ title, rows, kind }: { title: string; rows: TeamRow[]; kind: 'rank' | 'rating' }) {
  return <div className="cf-q-movers">
    <h3 className="cf-h3">{title}</h3>
    {rows.length === 0 ? <p className="cf-muted cf-small">None</p> : <ol className="cf-list">{rows.map(t => <li key={t.team_id} className="cf-list-row">
      <TeamLink id={t.team_id} size={22} sub={kind === 'rank' ? `No. ${t.rank_prev} → No. ${t.rank}` : undefined} />
      <span className="cf-list-val">{kind === 'rank' ? <Movement change={t.rank_change} /> : <><Num value={t.rating_change} signed /> <span className="cf-muted cf-small">pts</span></>}</span>
    </li>)}</ol>}
  </div>
}

export default function Home() {
  const index = useData<IndexDoc>('index.json')
  return <DataGate source={index} label="Ratings">{({ meta, teams, top_games }) => {
    const ranked = teams.filter(t => t.rank != null).sort((a, b) => a.rank! - b.rank!)
    const contenders = teams.filter(t => t.p_playoff != null && t.p_playoff > 0).sort((a, b) => b.p_playoff! - a.p_playoff! || (a.rank ?? 999) - (b.rank ?? 999)).slice(0, 8)
    const moved = teams.filter(t => t.rank_change != null)
    const risers = [...moved].filter(t => t.rank_change! > 0).sort((a, b) => b.rank_change! - a.rank_change! || a.rank! - b.rank!).slice(0, 3)
    const fallers = [...moved].filter(t => t.rank_change! < 0).sort((a, b) => a.rank_change! - b.rank_change! || a.rank! - b.rank!).slice(0, 3)
    const sims = meta.sim_status === 'available'
    return <>
      <header className="cf-hero">
        <p className="cf-eyebrow">{meta.season} college football</p>
        <h1>Every FBS team, rated.</h1>
        <p className="cf-lede">{sims && meta.sim_count ? `Opponent-adjusted power ratings and ${meta.sim_count.toLocaleString()} simulated seasons from CFPi+.` : 'Opponent-adjusted power ratings from CFPi+.'}</p>
        <Freshness meta={meta} />
      </header>

      <div className="cf-questions">
        <Question id="q-best" q="Who are the best teams?" more="Full rankings" to="/rankings/">
          <ol className="cf-list">
            {ranked.slice(0, 10).map(t => <li key={t.team_id} className="cf-list-row">
              <span className="cf-rank">{t.rank}</span>
              <TeamLink id={t.team_id} size={24} sub={t.wins != null ? `${t.wins}–${t.losses}` : undefined} />
              <span className="cf-list-move"><Movement change={t.rank_change} compared={meta.movement_compared_to_week} /></span>
              <span className="cf-list-val"><Num value={t.power} signed /></span>
            </li>)}
          </ol>
        </Question>

        <Question id="q-games" q={`Which games matter${meta.current_week != null ? ` in Week ${meta.current_week}` : ' this week'}?`} more="All games" to={meta.current_week != null ? `/games/?week=${meta.current_week}` : '/games/'}
          info={<Info text={QUALITY_INFO} label="How games are chosen" />}>
          {top_games && top_games.length
            ? <div className="cf-q-games">{top_games.slice(0, 4).map(g => <GameCard key={g.game_id} g={g} />)}</div>
            : <p className="cf-muted">No upcoming games with projections.</p>}
        </Question>

        <Question id="q-playoff" q="Who’s making the playoff?" more="Playoff odds and projected field" to="/playoff/">
          {sims ? <ol className="cf-list">
            {contenders.map(t => <li key={t.team_id} className="cf-list-row">
              <TeamLink id={t.team_id} size={24} sub={t.rank ? `No. ${t.rank}` : undefined} />
              <span className="cf-list-val cf-list-wide"><Pct value={t.p_playoff} bar /></span>
            </li>)}
          </ol> : <p className="cf-muted">Simulation results are unavailable for this update.</p>}
        </Question>

        <Question id="q-changed" q="What changed this week?" more="Every move, with the results behind it" to="/changes/">
          {meta.movement_compared_to_week == null ? <p className="cf-muted">No comparable previous week yet.</p> : <>
            <p className="cf-small cf-muted">Rank movement vs Week {meta.movement_compared_to_week}{meta.movement_source === 'reconstructed' ? ' (reconstructed)' : ''}.</p>
            <div className="cf-q-movers-grid">
              <Movers title="Risers" rows={risers} kind="rank" />
              <Movers title="Fallers" rows={fallers} kind="rank" />
            </div>
          </>}
        </Question>
      </div>
    </>
  }}</DataGate>
}
