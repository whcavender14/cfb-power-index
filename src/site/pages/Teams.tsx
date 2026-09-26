import { Search, X } from 'lucide-react'
import { DataGate, Freshness, Num, PageHead, Select, SortTh, sortRows, TeamLink, useData, useTeams, type Sort } from '../components'
import type { IndexDoc, TeamRow } from '../data'
import { Link, useQueryParam } from '../router'

const SOS_INFO = 'Schedule strength: the mean CFPi+ rating of all opponents on the full schedule (played and remaining). Higher = harder.'
const SOR_INFO = 'Strength of record: wins so far minus the wins a benchmark team (the No. 60 CFPi+ team, the simulation’s CFP-ranking benchmark) would expect against the same opponents and sites.'

/** Power bar: from 0 (average FBS team) to the rating, on the full FBS range. */
function PowerBar({ v, lo, hi }: { v: number | null; lo: number; hi: number }) {
  if (v == null) return null
  const pos = (x: number) => ((x - lo) / (hi - lo)) * 100
  return <span className="cf-pbar" aria-hidden="true"><i className={v >= 0 ? 'is-pos' : 'is-neg'} style={{ left: `${pos(Math.min(0, v))}%`, width: `${Math.abs(pos(v) - pos(0))}%` }} /><b style={{ left: `${pos(0)}%` }} /></span>
}

export default function Teams() {
  const index = useData<IndexDoc>('index.json')
  const directory = useTeams()
  const [q, setQ] = useQueryParam('q')
  const [conf, setConf] = useQueryParam('conf')
  const [sk, setSk] = useQueryParam('sort', 'power')
  const [sd, setSd] = useQueryParam('dir', 'desc')
  const sort: Sort = { key: sk, desc: sd !== 'asc' }
  const onSort = (s: Sort) => { setSk(s.key); setSd(s.desc ? 'desc' : 'asc') }
  return <>
    <PageHead title="Teams" lede={<>Every FBS team, searchable and sortable by its CFPi+ power rating and its parts. For how conferences compare as groups, see <Link to="/conferences/">Conferences</Link>.</>} />
    <DataGate source={index} label="Teams">{({ meta, teams }) => {
      const needle = q.trim().toLowerCase()
      const confs = [...new Set([...directory.values()].map(t => t.conference).filter(Boolean) as string[])].sort()
      const shown = teams.filter(r => {
        const t = directory.get(r.team_id)
        if (conf && t?.conference !== conf) return false
        return !needle || [t?.team, t?.mascot, t?.abbreviation].some(s => (s ?? '').toLowerCase().includes(needle))
      })
      const val = (r: TeamRow) => ({ power: r.power, rank: r.rank == null ? null : -r.rank, off: r.off, def: r.def == null ? null : -r.def, sos: r.sos, sor: r.sor, name: directory.get(r.team_id)?.team ?? '' } as Record<string, number | string | null>)[sort.key] ?? r.power
      const rows = sortRows(shown, val, sort.key === 'name' ? !sort.desc : sort.desc)
      const powers = teams.map(t => t.power).filter((v): v is number => v != null)
      const lo = Math.floor(Math.min(0, ...powers) / 5) * 5, hi = Math.ceil(Math.max(...powers) / 5) * 5
      return <>
        <Freshness meta={meta} />
        <div className="cf-toolbar">
          <label className="cf-search"><Search size={15} aria-hidden="true" />
            <input type="search" placeholder="Search teams" aria-label="Search teams" value={q} onChange={e => setQ(e.target.value)} />
            {q && <button type="button" aria-label="Clear search" onClick={() => setQ('')}><X size={14} /></button>}
          </label>
          <Select label="Conference" value={conf} onChange={setConf}>
            <option value="">All conferences</option>
            {confs.map(c => <option key={c} value={c}>{c}</option>)}
          </Select>
          <p className="cf-muted cf-small" role="status">{rows.length} of {teams.length} teams</p>
        </div>
        {rows.length === 0 ? <div className="cf-state"><p className="cf-state-title">No teams match</p></div> :
        <div className="cf-table-wrap"><table className="cf-table cf-teams-table">
          <thead><tr>
            <SortTh label="CFPi+ rank" sortKey="rank" sort={sort} onSort={onSort} align="start" info="Predictive rank by CFPi+ power rating. The résumé rank (strength of record) is on the Résumé ranking page." />
            <SortTh label="Team" sortKey="name" sort={sort} onSort={onSort} align="start" />
            <SortTh label="CFPi+" sortKey="power" sort={sort} onSort={onSort} info="Power rating: points better than an average FBS team on a neutral field (offense − defense)." />
            <th scope="col" className="cf-th-start cf-pbar-col"><span className="cf-sr">Rating bar</span></th>
            <SortTh label="Off." sortKey="off" sort={sort} onSort={onSort} className="cf-hide-sm" />
            <SortTh label="Def." sortKey="def" sort={sort} onSort={onSort} className="cf-hide-sm" info="Lower is better; sorting puts the best defense first." />
            <SortTh label="SOS" sortKey="sos" sort={sort} onSort={onSort} className="cf-hide-sm" info={SOS_INFO} />
            <SortTh label="SOR" sortKey="sor" sort={sort} onSort={onSort} className="cf-hide-sm" info={SOR_INFO} />
          </tr></thead>
          <tbody>{rows.map(r => <tr key={r.team_id}>
            <td className="cf-num">{r.rank ?? '—'}</td>
            <td><TeamLink id={r.team_id} size={22} sub={directory.get(r.team_id)?.conference ?? undefined} /></td>
            <td className="cf-td-end cf-strong"><Num value={r.power} signed /></td>
            <td className="cf-pbar-col"><PowerBar v={r.power} lo={lo} hi={hi} /></td>
            <td className="cf-td-end cf-hide-sm"><Num value={r.off} signed /></td>
            <td className="cf-td-end cf-hide-sm"><Num value={r.def} signed /></td>
            <td className="cf-td-end cf-hide-sm"><Num value={r.sos} signed /></td>
            <td className="cf-td-end cf-hide-sm"><Num value={r.sor} signed digits={2} /></td>
          </tr>)}</tbody>
        </table></div>}
        <p className="cf-small cf-muted">Rank, record, movement and playoff odds are on <Link to="/rankings/">Rankings</Link>.</p>
      </>
    }}</DataGate>
  </>
}
