import ShareButton from '../ShareButton'
import { DataGate, Freshness, Movement, Num, PageHead, SortTh, sortRows, TeamLink, useData, useTeams, type Sort } from '../components'
import type { ChangesDoc, IndexDoc, TeamChange, TeamRow } from '../data'
import { Link, useQueryParam } from '../router'

const N = 8

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

function MoverList({ title, rows, kind, changes }: { title: string; rows: TeamRow[]; kind: 'rank' | 'rating'; changes: Map<string, TeamChange> }) {
  return <section className="cf-panel cf-movers" aria-label={title}>
    <h2 className="cf-h3">{title}</h2>
    {rows.length === 0 ? <p className="cf-muted">None this week.</p> : <ol className="cf-mover-list">
      {rows.map(r => <li key={r.team_id} className="cf-mover">
        <div className="cf-mover-head">
          <TeamLink id={r.team_id} size={24} sub={kind === 'rank' ? `No. ${r.rank_prev} → No. ${r.rank}` : `${r.rating_change! > 0 ? '+' : ''}${r.rating_change!.toFixed(1).replace('-', '−')} → ${r.power! > 0 ? '+' : ''}${r.power!.toFixed(1).replace('-', '−')}`} />
          <span className="cf-mover-val">{kind === 'rank' ? <Movement change={r.rank_change} /> : <span className="cf-num cf-pts"><Num value={r.rating_change} signed /> pts</span>}</span>
        </div>
        <Why c={changes.get(r.team_id)} />
      </li>)}
    </ol>}
  </section>
}

export default function Changes() {
  const directory = useTeams()
  const index = useData<IndexDoc>('index.json')
  const doc = useData<ChangesDoc>('changes.json')
  const [sk, setSk] = useQueryParam('sort', 'rating_change')
  const [sd, setSd] = useQueryParam('dir', 'desc')
  const sort: Sort = { key: sk, desc: sd !== 'asc' }
  const onSort = (s: Sort) => { setSk(s.key); setSd(s.desc ? 'desc' : 'asc') }
  return <>
    <PageHead title="What changed" lede="This week’s biggest moves. Rank movement (places in the ranking) and rating change (CFPi+ points) are listed separately: a team can gain points and still drop in rank." />
    <DataGate source={index} label="Rankings">{({ meta, teams }) => <DataGate source={doc} label="Weekly changes">{ch => {
      if (ch.compared_to_week == null) return <div className="cf-state"><p className="cf-state-title">No comparable previous week</p><p className="cf-muted">Changes appear once two consecutive weeks of CFPi+ ratings exist.</p></div>
      const changes = new Map(ch.teams.map(c => [c.team_id, c]))
      const rated = teams.filter(t => t.rank_change != null && t.rating_change != null)
      const byRank = (up: boolean) => rated.filter(t => up ? t.rank_change! > 0 : t.rank_change! < 0).sort((a, b) => up ? b.rank_change! - a.rank_change! || a.rank! - b.rank! : a.rank_change! - b.rank_change! || a.rank! - b.rank!).slice(0, N)
      const byRating = (up: boolean) => rated.filter(t => up ? t.rating_change! > 0 : t.rating_change! < 0).sort((a, b) => up ? b.rating_change! - a.rating_change! : a.rating_change! - b.rating_change!).slice(0, N)
      const val = (r: TeamRow) => {
        const c = changes.get(r.team_id)
        switch (sort.key) {
          case 'rank': return r.rank; case 'rank_change': return r.rank_change; case 'rating_change': return r.rating_change
          case 'power': return r.power; case 'off': return c?.off_change ?? null; case 'def': return c?.def_change == null ? null : -c.def_change
          default: return r.rating_change
        }
      }
      const all = sortRows(rated, val, sort.desc)
      return <>
        <div className="cf-subbar"><Freshness meta={meta} /><ShareButton run={async () => (await import('../graphics')).moversPng(meta, teams, ch, directory)} /></div>
        <p className="cf-note">Compared with Week {ch.compared_to_week} ratings{ch.compared_to_source === 'reconstructed' ? <> (a reconstruction: CFPi+ was not yet the published model that week; see <Link to="/compare/">Rating history</Link>)</> : null}. Games listed are the ones whose results entered the ratings since then. Each note states the result against the projection from the Week {ch.compared_to_week} ratings; it does not claim that game alone caused the change, because every rating is refit on all games each week.</p>
        <h2 className="cf-h2">Rank movement</h2>
        <div className="cf-movers-grid">
          <MoverList title="Biggest risers" rows={byRank(true)} kind="rank" changes={changes} />
          <MoverList title="Biggest fallers" rows={byRank(false)} kind="rank" changes={changes} />
        </div>
        <h2 className="cf-h2">Rating change (CFPi+ points)</h2>
        <div className="cf-movers-grid">
          <MoverList title="Largest increases" rows={byRating(true)} kind="rating" changes={changes} />
          <MoverList title="Largest decreases" rows={byRating(false)} kind="rating" changes={changes} />
        </div>
        <h2 className="cf-h2">Every team</h2>
        <div className="cf-table-wrap"><table className="cf-table">
          <thead><tr>
            <SortTh label="Rank" sortKey="rank" sort={sort} onSort={onSort} align="start" />
            <th scope="col" className="cf-th-start">Team</th>
            <SortTh label="Rank move" sortKey="rank_change" sort={sort} onSort={onSort} />
            <SortTh label="CFPi+" sortKey="power" sort={sort} onSort={onSort} className="cf-hide-sm" />
            <SortTh label="Rating Δ" sortKey="rating_change" sort={sort} onSort={onSort} info="Change in CFPi+ points since the comparison week." />
            <SortTh label="Off. Δ" sortKey="off" sort={sort} onSort={onSort} className="cf-hide-sm" info="Change in the offensive rating (higher is better)." />
            <SortTh label="Def. Δ" sortKey="def" sort={sort} onSort={onSort} className="cf-hide-sm" info="Change in the defensive rating (lower is better). Sorting puts the biggest improvement first." />
          </tr></thead>
          <tbody>{all.map(r => { const c = changes.get(r.team_id); return <tr key={r.team_id}>
            <td className="cf-num">{r.rank}</td>
            <td><TeamLink id={r.team_id} size={20} /></td>
            <td className="cf-td-end"><Movement change={r.rank_change} /></td>
            <td className="cf-td-end cf-hide-sm"><Num value={r.power} signed /></td>
            <td className="cf-td-end"><Num value={r.rating_change} signed /></td>
            <td className="cf-td-end cf-hide-sm"><Num value={c?.off_change} signed /></td>
            <td className="cf-td-end cf-hide-sm"><Num value={c?.def_change} signed /></td>
          </tr> })}</tbody>
        </table></div>
      </>
    }}</DataGate>}</DataGate>
  </>
}
