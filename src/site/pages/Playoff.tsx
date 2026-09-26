import ShareButton from '../ShareButton'
import { DataGate, Freshness, Info, Num, PageHead, Pct, pctText, SortTh, sortRows, TeamLink, useData, useTeams, type Sort } from '../components'
import type { PlayoffDoc, PlayoffTeam } from '../data'
import { Link, useQueryParam } from '../router'

const INFO: Record<string, string> = {
  p_playoff: 'Share of simulated seasons in which the team makes the 12-team field.',
  p_auto: 'Share of seasons in which the team gets in on an automatic bid: power-conference champion, the top-ranked team from the other six conferences, or Notre Dame when ranked in the top 12.',
  p_at_large: 'Share of seasons in which the team gets in on an at-large bid.',
  p_bye: 'Share of seasons as a top-4 seed (first-round bye).',
  p_host: 'Share of seasons as seed 5–8, which hosts a first-round game on campus.',
  p_qf: 'Share of seasons reaching the quarterfinals (bye or first-round win).',
  p_sf: 'Share of seasons reaching the semifinals.',
  p_final: 'Share of seasons reaching the national championship game.',
  p_champ: 'Share of seasons winning the national title.',
  mean_seed: 'Average seed in the seasons where the team makes the field.',
}
const COLS: [keyof PlayoffTeam, string][] = [['p_playoff', 'Playoff'], ['p_auto', 'Auto bid'], ['p_at_large', 'At-large'], ['p_bye', 'Bye'], ['p_host', 'Host'], ['p_qf', 'QF'], ['p_sf', 'Semis'], ['p_final', 'Final'], ['p_champ', 'Title']]

// First-round pairings and the quarterfinal each winner meets (the bracket cfbseedR builds for 12 teams).
const PAIRS: [number, number, number][] = [[8, 9, 1], [5, 12, 4], [7, 10, 2], [6, 11, 3]]

export default function Playoff() {
  const doc = useData<PlayoffDoc>('playoff.json')
  const teams = useTeams()
  const [sortKey, setSortKey] = useQueryParam('sort', 'p_playoff')
  const [dir, setDir] = useQueryParam('dir', '')
  const [scope, setScope] = useQueryParam('show', '')
  const natural = (k: string) => k !== 'mean_seed'
  const sort: Sort = { key: sortKey, desc: dir ? dir === 'desc' : natural(sortKey) }
  const onSort = (s: Sort) => { setSortKey(s.key); setDir(s.desc === natural(s.key) ? '' : s.desc ? 'desc' : 'asc') }

  return <>
    <PageHead title="Playoff" lede={<>Odds for the 12-team College Football Playoff, from the simulated seasons. Each season is played out, ranked, seeded and bracketed with the rules below. Try <Link to="/whatif/">What if?</Link> to see how picks change them.</>} />
    <DataGate source={doc} label="Playoff odds">{({ meta, format, teams: rows, representative_field: field }) => {
      if (meta.sim_status !== 'available' || !rows.length) return <div className="cf-state" role="status"><p className="cf-state-title">Simulation results are unavailable for this update</p><p className="cf-muted">Ratings are still current. Playoff odds return with the next successful simulation.</p></div>
      const contenders = rows.filter(r => r.p_playoff > 0)
      const shown = scope === 'all' ? rows : contenders
      const key = (sort.key in INFO ? sort.key : 'p_playoff') as keyof PlayoffTeam
      const sorted = sortRows(shown, r => r[key] as number | null, sort.desc)
      const bySeed = new Map(field?.seeds.map(s => [s.seed, s]) ?? [])
      const seedTeams = [...contenders].sort((a, b) => b.p_playoff - a.p_playoff).slice(0, 24)
      const name = (id: string) => teams.get(id)?.team ?? id
      const Seed = ({ n }: { n: number }) => { const s = bySeed.get(n); return s ? <div className="cf-seed">
        <span className="cf-seed-n">{n}</span><TeamLink id={s.team_id} size={22} />
        <span className={`cf-bid${s.bid === 'auto' ? ' is-auto' : ''}`}>{s.bid === 'auto' ? 'Auto' : 'At-large'}</span>
      </div> : null }
      return <>
        <Freshness meta={meta} sims />

        <section className="cf-section" aria-labelledby="po-field">
          <div className="cf-panel-head">
            <h2 id="po-field">Projected field <Info text="The single simulated season whose seeding is most consistent with all 1,000 simulations (the highest joint probability of each team landing on its seed). Because it is a real simulated outcome, it follows the selection rules exactly. It is one plausible field, not a forecast that every seed will hold." label="How the projected field is chosen" /></h2>
            {field && <ShareButton label="Projected field PNG" run={async () => (await import('../graphics')).playoffFieldPng(doc.data!, teams)} />}
          </div>
          {field ? <>
            <div className="cf-bracket">
              <div className="cf-bracket-col"><h3 className="cf-h3">Byes</h3>{[1, 2, 3, 4].map(n => <Seed key={n} n={n} />)}</div>
              <div className="cf-bracket-col"><h3 className="cf-h3">First round <span className="cf-muted cf-small">(higher seed hosts)</span></h3>
                {PAIRS.map(([a, b, q]) => <div key={a} className="cf-pair"><Seed n={a} /><Seed n={b} /><p className="cf-small cf-muted">Winner plays No. {q} {bySeed.get(q) ? name(bySeed.get(q)!.team_id) : ''}</p></div>)}
              </div>
            </div>
            <p className="cf-small cf-muted">This exact 12-team seeding occurred in {field.sims_with_identical_field} of {meta.sim_count?.toLocaleString()} simulated seasons; individual seed odds are in the table below.</p>
          </> : <p className="cf-muted">No projected field is available.</p>}
          <details className="cf-rules">
            <summary>Selection rules used by the simulation</summary>
            <ul><li>{format.autobids}.</li><li>{format.ranking}.</li><li>{format.seeding}.</li></ul>
          </details>
        </section>

        <section className="cf-section" aria-labelledby="po-odds">
          <div className="cf-panel-head">
            <h2 id="po-odds">Playoff odds</h2>
            <span className="cf-share-row"><label className="cf-check"><input type="checkbox" checked={scope === 'all'} onChange={e => setScope(e.target.checked ? 'all' : '')} /> Show all {rows.length} teams</label>
              <ShareButton label="CFP odds PNG" run={async () => (await import('../graphics')).playoffOddsPng(doc.data!, teams)} /></span>
          </div>
          <div className="cf-table-wrap cf-desktop">
            <table className="cf-table">
              <caption className="cf-sr">Playoff probabilities, sortable</caption>
              <thead><tr>
                <th scope="col" className="cf-th-start">Team</th>
                {COLS.map(([k, label]) => <SortTh key={k} label={label} sortKey={k} sort={sort} onSort={onSort} info={INFO[k]} />)}
                <SortTh label="Avg seed" sortKey="mean_seed" sort={sort} onSort={onSort} info={INFO.mean_seed} />
              </tr></thead>
              <tbody>{sorted.map(r => <tr key={r.team_id}>
                <td><TeamLink id={r.team_id} sub={teams.get(r.team_id)?.conference} /></td>
                {COLS.map(([k]) => <td key={k} className={`cf-td-end${k === 'p_playoff' ? ' cf-strong' : ''}`}><Pct value={r[k] as number} /></td>)}
                <td className="cf-td-end"><Num value={r.mean_seed} why="Never selected" /></td>
              </tr>)}</tbody>
            </table>
          </div>
          <ol className="cf-cards cf-phone">{sorted.map(r => <li key={r.team_id} className="cf-card">
            <div className="cf-card-top"><TeamLink id={r.team_id} size={28} sub={teams.get(r.team_id)?.conference} /><span className="cf-card-power"><Pct value={r.p_playoff} /></span></div>
            <dl className="cf-card-stats">
              <div><dt>Auto bid</dt><dd><Pct value={r.p_auto} /></dd></div>
              <div><dt>Bye</dt><dd><Pct value={r.p_bye} /></dd></div>
              <div><dt>Semis</dt><dd><Pct value={r.p_sf} /></dd></div>
              <div><dt>Title</dt><dd><Pct value={r.p_champ} /></dd></div>
              <div><dt>Avg seed</dt><dd><Num value={r.mean_seed} /></dd></div>
            </dl>
          </li>)}</ol>
        </section>

        <section className="cf-section" aria-labelledby="po-seeds">
          <div className="cf-panel-head"><h2 id="po-seeds">Seed probabilities <Info text="Share of simulated seasons in which the team receives each seed. Rows sum to the team’s playoff probability." label="About seed probabilities" /></h2></div>
          <div className="cf-table-wrap cf-desktop">
            <table className="cf-table cf-seedtable">
              <caption className="cf-sr">Probability of each seed, top {seedTeams.length} teams by playoff odds</caption>
              <thead><tr><th scope="col" className="cf-th-start">Team</th>{Array.from({ length: 12 }, (_, i) => <th key={i} scope="col" className="cf-th-end">{i + 1}</th>)}</tr></thead>
              <tbody>{seedTeams.map(r => <tr key={r.team_id}>
                <td><TeamLink id={r.team_id} size={20} /></td>
                {(r.seed_dist ?? []).map((p, i) => <td key={i} className="cf-td-end cf-heat" style={{ ['--heat' as string]: Math.min(1, p / 0.5) }}>
                  {p > 0 ? <span className="cf-num">{pctText(p, 0) === '0%' ? '<1%' : pctText(p, 0)}</span> : <span className="cf-faint" aria-label="none">·</span>}
                </td>)}
              </tr>)}</tbody>
            </table>
          </div>
          <ol className="cf-cards cf-phone">{seedTeams.map(r => { const d = r.seed_dist ?? []; const top = d.indexOf(Math.max(...d)); return <li key={r.team_id} className="cf-card">
            <div className="cf-card-top"><TeamLink id={r.team_id} size={24} /><span className="cf-small">Most likely: <strong>No. {top + 1}</strong> ({pctText(d[top], 0)})</span></div>
            <div className="cf-spark" role="img" aria-label={`Seed probabilities: ${d.map((p, i) => `${i + 1}: ${pctText(p, 0)}`).join(', ')}`}>
              {d.map((p, i) => <span key={i} className="cf-spark-col"><i style={{ height: `${Math.max(2, (p / Math.max(...d)) * 100)}%` }} /><b>{i + 1}</b></span>)}
            </div>
          </li> })}</ol>
        </section>

        <p className="cf-small cf-muted">Also available: the <Link to="/simulations/">season simulation table and shareable graphics</Link>.</p>
      </>
    }}</DataGate>
  </>
}
