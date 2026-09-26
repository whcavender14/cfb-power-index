import { RankingTabs } from './Resume'
import { useMemo } from 'react'
import { Search, X } from 'lucide-react'
import ShareButton from '../ShareButton'
import { DataGate, Freshness, Info, Movement, Num, PageHead, Pct, Select, SortTh, sortRows, TeamLink, useData, useTeams, type Sort } from '../components'
import type { IndexDoc, TeamRow } from '../data'
import { Link, useQueryParam } from '../router'
import { fetchDataset, type Rating } from '../../data'

const INFO = {
  rank: 'CFPi+ rank by power rating, computed by the pipeline.',
  move: 'Rank change since the previous week, from the same model. Up arrows mean the team moved up. Rating change is shown separately.',
  power: 'Opponent-adjusted strength in points relative to an average FBS team (offense minus defense). The spread between two teams on a neutral field is roughly the difference in power.',
  change: 'Power-rating change since the previous week, in points. Separate from rank change: a team can gain rating and still drop in rank.',
  off: 'Offensive rating: points above an average FBS offense. Higher is better. Small number = national rank.',
  def: 'Defensive rating: points allowed relative to an average FBS defense. Lower (more negative) is better. Small number = national rank.',
  wins: 'Mean regular-season wins across the simulated seasons. Conference title games are not simulated.',
  playoff: 'Share of simulated seasons in which the team makes the 12-team playoff.',
  record: 'Wins and losses in games the ratings have processed (through the ratings week), including games against FCS opponents.',
}

const SORTS: Record<string, (t: TeamRow) => number | null> = {
  rank: t => t.rank, move: t => t.rank_change, power: t => t.power, change: t => t.rating_change,
  off: t => t.off, def: t => t.def == null ? null : -t.def, wins: t => t.proj_wins, playoff: t => t.p_playoff,
}

export default function Rankings() {
  const index = useData<IndexDoc>('index.json')
  const teams = useTeams()
  const [q, setQ] = useQueryParam('q')
  const [conf, setConf] = useQueryParam('conf')
  const [sortKey, setSortKey] = useQueryParam('sort', 'rank')
  const [dir, setDir] = useQueryParam('dir', '')
  const sort: Sort = { key: SORTS[sortKey] ? sortKey : 'rank', desc: dir ? dir === 'desc' : sortKey !== 'rank' }
  const onSort = (s: Sort) => {
    setSortKey(s.key)
    const natural = s.key !== 'rank'
    setDir(s.desc === natural ? '' : s.desc ? 'desc' : 'asc')
  }

  const conferences = useMemo(() => [...new Set([...teams.values()].map(t => t.conference).filter(Boolean) as string[])].sort(), [teams])

  return <>
    <PageHead title="Rankings" lede="All FBS teams ordered by CFPi+ power rating: how good each team is (predictive). Rank movement and rating change are listed separately."><RankingTabs active="predictive" /></PageHead>
    <DataGate source={index} label="Rankings">{({ meta, teams: rows }) => {
      const needle = q.trim().toLowerCase()
      const filtered = rows.filter(r => {
        const t = teams.get(r.team_id)
        if (conf && t?.conference !== conf) return false
        return !needle || (t?.team ?? '').toLowerCase().includes(needle) || (t?.abbreviation ?? '').toLowerCase() === needle || (t?.mascot ?? '').toLowerCase().includes(needle)
      })
      const sorted = sortRows(filtered, SORTS[sort.key], sort.desc)
      const png = async () => {
        const legacy = await fetchDataset<Rating>('ratings')
        const order = new Map(rows.map(r => [r.team_id, r.rank ?? Infinity]))
        // Same previous-week source as the site's movement (history.json via index.json), not the v1 file's own comparison.
        const change = new Map(rows.map(r => [r.team_id, r.rating_change]))
        const ordered = [...legacy.teams].map(t => ({ ...t, weekly_change: change.get(t.team_id) ?? null }))
          .sort((a, b) => (order.get(a.team_id) ?? Infinity) - (order.get(b.team_id) ?? Infinity))
        const { exportRankingsPng } = await import('../../exportImage')
        await exportRankingsPng({ teams: ordered, season: legacy.season, week: legacy.week, updatedAt: legacy.updated_at })
      }
      const compared = meta.movement_compared_to_week
      return <>
        <div className="cf-toolbar">
          <label className="cf-search">
            <Search size={15} aria-hidden="true" />
            <input type="search" placeholder="Search teams" aria-label="Search teams" value={q} onChange={e => setQ(e.target.value)} />
            {q && <button type="button" aria-label="Clear search" onClick={() => setQ('')}><X size={14} /></button>}
          </label>
          <Select label="Conference" value={conf} onChange={setConf}>
            <option value="">All conferences</option>
            {conferences.map(c => <option key={c} value={c}>{c}</option>)}
          </Select>
          <div className="cf-toolbar-end">
            <span className="cf-share-row"><ShareButton label="Top 25 PNG" run={async () => (await import('../graphics')).top25Png(meta, rows, teams)} /><ShareButton label="All teams PNG" run={png} /></span>
          </div>
        </div>
        <div className="cf-subbar">
          <Freshness meta={meta} />
          <p className="cf-muted" role="status">{filtered.length === rows.length ? `${rows.length} teams` : `${filtered.length} of ${rows.length} teams`}
            {compared == null ? <> · Movement unavailable: no CFPi+ ratings for the previous week</> : <> · Movement vs Week {compared}{meta.movement_source === 'reconstructed' ? ' (reconstructed)' : ''}. <Link to="/changes/">What changed</Link></>}</p>
        </div>

        {sorted.length === 0 ? <div className="cf-state"><p className="cf-state-title">No teams match</p><button type="button" className="cf-btn" onClick={() => { setQ(''); setConf('') }}>Clear filters</button></div> : <>
        <div className="cf-table-wrap cf-desktop">
          <table className="cf-table">
            <caption className="cf-sr">CFPi+ rankings, sortable</caption>
            <thead><tr>
              <SortTh label="Rk" sortKey="rank" sort={sort} onSort={s => onSort({ ...s, desc: sort.key === 'rank' ? !sort.desc : false })} info={INFO.rank} align="start" />
              <SortTh label="Move" sortKey="move" sort={sort} onSort={onSort} info={INFO.move} align="start" />
              <th scope="col" className="cf-th-start">Team</th>
              <th scope="col" className="cf-th-end"><span className="cf-th">Record <Info text={INFO.record} label="About record" /></span></th>
              <SortTh label="Power" sortKey="power" sort={sort} onSort={onSort} info={INFO.power} />
              <SortTh label="Δ Rating" sortKey="change" sort={sort} onSort={onSort} info={INFO.change} />
              <SortTh label="Offense" sortKey="off" sort={sort} onSort={onSort} info={INFO.off} />
              <SortTh label="Defense" sortKey="def" sort={sort} onSort={onSort} info={INFO.def} />
              <SortTh label="Proj. W" sortKey="wins" sort={sort} onSort={onSort} info={INFO.wins} />
              <SortTh label="Playoff" sortKey="playoff" sort={sort} onSort={onSort} info={INFO.playoff} />
            </tr></thead>
            <tbody>{sorted.map(r => <tr key={r.team_id}>
              <td className="cf-rank">{r.rank ?? '—'}</td>
              <td><Movement change={r.rank_change} compared={compared} /></td>
              <td><TeamLink id={r.team_id} sub={teams.get(r.team_id)?.conference} /></td>
              <td className="cf-td-end cf-num">{r.wins != null ? `${r.wins}–${r.losses}` : '—'}</td>
              <td className="cf-td-end cf-strong"><Num value={r.power} signed /></td>
              <td className="cf-td-end"><Num value={r.rating_change} signed why="No comparable previous week" /></td>
              <td className="cf-td-end"><Num value={r.off} signed /> <span className="cf-small">{r.off_rank ?? ''}</span></td>
              <td className="cf-td-end"><Num value={r.def} signed /> <span className="cf-small">{r.def_rank ?? ''}</span></td>
              <td className="cf-td-end"><Num value={r.proj_wins} /></td>
              <td className="cf-td-end"><Pct value={r.p_playoff} /></td>
            </tr>)}</tbody>
          </table>
        </div>

        <ol className="cf-cards cf-phone" aria-label="CFPi+ rankings">
          {sorted.map(r => <li key={r.team_id} className="cf-card">
            <div className="cf-card-top">
              <span className="cf-rank">{r.rank ?? '—'}</span>
              <TeamLink id={r.team_id} size={30} sub={<>{teams.get(r.team_id)?.conference}{r.wins != null ? ` · ${r.wins}–${r.losses}` : ''}</>} />
              <span className="cf-card-power"><Num value={r.power} signed /></span>
            </div>
            <dl className="cf-card-stats">
              <div><dt>Move</dt><dd><Movement change={r.rank_change} compared={compared} /></dd></div>
              <div><dt>Δ Rating</dt><dd><Num value={r.rating_change} signed /></dd></div>
              <div><dt>Off / Def rank</dt><dd className="cf-num">{r.off_rank ?? '—'} / {r.def_rank ?? '—'}</dd></div>
              <div><dt>Proj. W</dt><dd><Num value={r.proj_wins} /></dd></div>
              <div><dt>Playoff</dt><dd><Pct value={r.p_playoff} /></dd></div>
            </dl>
          </li>)}
        </ol></>}
      </>
    }}</DataGate>
  </>
}
