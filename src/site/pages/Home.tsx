import type { ReactNode } from 'react'
import ShareButton from '../ShareButton'
import { DataGate, Freshness, Info, Movement, Num, Pct, pctText, TeamLink, useData, useTeams } from '../components'
import type { ChangesDoc, IndexDoc, Meta, TeamChange, TeamRow } from '../data'
import { GameCard, QUALITY_INFO } from '../games'
import { Link } from '../router'

// The homepage answers three questions, each a short preview that links to its full page, then shows this week's
// changes (the former What changed page). The previews use index.json only; changes.json loads with its own section.
function Question({ id, q, more, to, children, info }: { id: string; q: string; more: string; to: string; children: ReactNode; info?: ReactNode }) {
  return <section className="cf-panel cf-q" aria-labelledby={id}>
    <div className="cf-panel-head"><h2 id={id}>{q}{info}</h2></div>
    <div className="cf-q-body">{children}</div>
    <Link to={to} className="cf-more cf-q-more">{more}</Link>
  </section>
}

const N = 3

/** What moved a team, from model inputs only: its games in the window (with the pre-game projection), else raw deltas. */
function Why({ c }: { c: TeamChange | undefined }) {
  if (!c) return null
  return <div className="cf-why">
    {c.games.length > 0
      ? c.games.map(g => <p key={g.game_id}>{g.text}</p>)
      : <p className="cf-muted">No game entered the ratings this week; the change comes from other teams’ results.</p>}
    <p className="cf-why-deltas cf-muted">
      Offense <Num value={c.off_change} signed digits={1} /> · Defense <Num value={c.def_change} signed digits={1} />
      {c.def_change != null && Math.abs(c.def_change) >= 0.05 && <> ({c.def_change < 0 ? 'better' : 'worse'})</>}
    </p>
  </div>
}

const signedText = (v: number) => `${v > 0 ? '+' : ''}${v.toFixed(1).replace('-', '−')}`

function MoverList({ title, rows, kind, changes }: { title: string; rows: TeamRow[]; kind: 'rank' | 'rating'; changes: Map<string, TeamChange> }) {
  return <section className="cf-panel cf-movers" aria-label={title}>
    <h3 className="cf-h3">{title}</h3>
    {rows.length === 0 ? <p className="cf-muted">None this week.</p> : <ol className="cf-mover-list">
      {rows.map(r => <li key={r.team_id} className="cf-mover">
        <div className="cf-mover-head">
          <TeamLink id={r.team_id} size={24} sub={kind === 'rank' ? `No. ${r.rank_prev} → No. ${r.rank}` : `${signedText(r.rating_change!)} → ${signedText(r.power!)}`} />
          <span className="cf-mover-val">{kind === 'rank' ? <Movement change={r.rank_change} /> : <span className="cf-num cf-pts"><Num value={r.rating_change} signed /> pts</span>}</span>
        </div>
        <Why c={changes.get(r.team_id)} />
      </li>)}
    </ol>}
  </section>
}

function WhatChanged({ meta, teams }: { meta: Meta; teams: TeamRow[] }) {
  const directory = useTeams()
  const doc = useData<ChangesDoc>('changes.json')
  return <section className="cf-section" id="changed" aria-labelledby="h-changed">
    <div className="cf-section-head">
      <h2 id="h-changed">What changed this week?</h2>
      {doc.data && doc.data.compared_to_week != null && <ShareButton run={async () => (await import('../graphics')).moversPng(meta, teams, doc.data!, directory)} />}
    </div>
    <DataGate source={doc} label="Weekly changes">{ch => {
      if (ch.compared_to_week == null) return <p className="cf-muted">No comparable previous week yet. Changes appear once two consecutive weeks of CFPi+ ratings exist.</p>
      const changes = new Map(ch.teams.map(c => [c.team_id, c]))
      const rated = teams.filter(t => t.rank_change != null && t.rating_change != null)
      const byRank = (up: boolean) => rated.filter(t => up ? t.rank_change! > 0 : t.rank_change! < 0).sort((a, b) => up ? b.rank_change! - a.rank_change! || a.rank! - b.rank! : a.rank_change! - b.rank_change! || a.rank! - b.rank!).slice(0, N)
      const byRating = (up: boolean) => rated.filter(t => up ? t.rating_change! > 0 : t.rating_change! < 0).sort((a, b) => up ? b.rating_change! - a.rating_change! : a.rating_change! - b.rating_change!).slice(0, N)
      return <>
        <p className="cf-note">Compared with Week {ch.compared_to_week} ratings{ch.compared_to_source === 'reconstructed' ? <> (reconstructed: CFPi+ was not yet the published model that week)</> : null}. <Info text={`Rank movement (places) and rating change (CFPi+ points) are listed separately: a team can gain points and still drop in rank. Each note states the result against the projection from the Week ${ch.compared_to_week} ratings; it does not claim that game alone caused the change, because every rating is refit on all games each week.`} label="How to read these changes" /></p>
        <div className="cf-movers-grid cf-movers-compact">
          <MoverList title="Biggest risers" rows={byRank(true)} kind="rank" changes={changes} />
          <MoverList title="Biggest fallers" rows={byRank(false)} kind="rank" changes={changes} />
          <MoverList title="Largest rating increases" rows={byRating(true)} kind="rating" changes={changes} />
          <MoverList title="Largest rating decreases" rows={byRating(false)} kind="rating" changes={changes} />
        </div>
        <p className="cf-small cf-muted"><Link to="/rankings/?sort=move&dir=desc">Every team’s movement on the Rankings page</Link></p>
      </>
    }}</DataGate>
  </section>
}

export default function Home() {
  const index = useData<IndexDoc>('index.json')
  return <DataGate source={index} label="Ratings">{({ meta, teams, top_games, top_swing }) => {
    const ranked = teams.filter(t => t.rank != null).sort((a, b) => a.rank! - b.rank!)
    const contenders = teams.filter(t => t.p_playoff != null && t.p_playoff > 0).sort((a, b) => b.p_playoff! - a.p_playoff! || (a.rank ?? 999) - (b.rank ?? 999)).slice(0, 12)
    const sims = meta.sim_status === 'available'
    const top = (key: 'p_champ' | 'off_rank' | 'def_rank') => key === 'p_champ'
      ? teams.filter(t => t.p_champ != null).sort((a, b) => b.p_champ! - a.p_champ!)[0]
      : teams.find(t => t[key] === 1)
    const fav = sims ? top('p_champ') : undefined, off = top('off_rank'), def = top('def_rank')
    const snap = [
      ranked[0] && { label: 'No. 1 overall', row: ranked[0], value: `${signedText(ranked[0].power!)} pts vs average` },
      off && { label: 'Best offense', row: off, value: `${signedText(off.off!)} pts vs average` },
      def && { label: 'Best defense', row: def, value: `${Math.abs(def.def!).toFixed(1)} pts better than average` },
      fav && { label: 'Title favorite', row: fav, value: `${pctText(fav.p_champ, 1)} to win it all` },
    ]
    return <>
      <h1 className="cf-sr">CFPi+ college football power ratings</h1>
      <Freshness meta={meta} />
      <ul className="cf-snap" aria-label="Season snapshot">
        {snap.map(t => t && <li key={t.label} className="cf-snap-tile">
          <span className="cf-snap-label">{t.label}</span>
          <TeamLink id={t.row.team_id} size={32} />
          <span className="cf-snap-val cf-num">{t.value}</span>
        </li>)}
      </ul>

      <div className="cf-questions">
        <Question id="q-best" q="Who are the best teams?" more="Full rankings" to="/rankings/">
          <ol className="cf-list">
            {ranked.slice(0, 12).map(t => <li key={t.team_id} className="cf-list-row">
              <span className="cf-rank">{t.rank}</span>
              <TeamLink id={t.team_id} size={24} sub={t.wins != null ? `${t.wins}–${t.losses}` : undefined} />
              <span className="cf-list-move"><Movement change={t.rank_change} compared={meta.movement_compared_to_week} /></span>
              <span className="cf-list-val"><Num value={t.power} signed /></span>
            </li>)}
          </ol>
        </Question>

        <Question id="q-playoff" q="Who’s making the playoff?" more="Playoff odds and projected field" to="/playoff/">
          {sims ? <ol className="cf-list">
            {contenders.map(t => <li key={t.team_id} className="cf-list-row">
              <TeamLink id={t.team_id} size={24} sub={t.rank ? `No. ${t.rank}` : undefined} />
              <span className="cf-list-val cf-list-wide"><Pct value={t.p_playoff} bar /></span>
            </li>)}
          </ol> : <p className="cf-muted">Simulation results are unavailable for this update.</p>}
        </Question>

        <Question id="q-games" q={`Which games matter${meta.current_week != null ? ` in Week ${meta.current_week}` : ' this week'}?`} more="All games" to={meta.current_week != null ? `/games/?week=${meta.current_week}` : '/games/'}
          info={<Info text={QUALITY_INFO} label="How games are chosen" />}>
          {top_games && top_games.length
            ? <><div className="cf-q-games">{top_games.slice(0, 4).map(g => <GameCard key={g.game_id} g={g} swing={top_swing?.[g.game_id]} />)}</div>
              {top_swing && <p className="cf-small cf-muted cf-swing-note"><b className="cf-swing-w">▲</b> / <b className="cf-swing-l">▼</b> = the team’s playoff chance if it wins / loses that game, from the simulated seasons (same filter as <Link to="/whatif/">What if?</Link>).</p>}</>
            : <p className="cf-muted">No upcoming games with projections.</p>}
        </Question>
      </div>

      {meta.movement_compared_to_week != null && <WhatChanged meta={meta} teams={teams} />}
    </>
  }}</DataGate>
}
