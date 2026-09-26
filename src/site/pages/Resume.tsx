import { DataGate, Freshness, Missing, Num, PageHead, SortTh, sortRows, TeamLink, useData, type Sort } from '../components'
import type { NotableGame, ResumeDoc, ResumeRow } from '../data'
import { Link, useQueryParam } from '../router'

export const RESUME_INFO = 'Résumé rank orders teams by strength of record: wins so far minus the wins the No. 60 CFPi+ team would expect against the same opponents and sites. Ties: fewer losses, then harder schedule played, then team id. It measures what a team has done, not how good it is.'

export function RankingTabs({ active }: { active: 'predictive' | 'resume' }) {
  return <nav className="cf-seg cf-rank-tabs" aria-label="Ranking type">
    <Link to="/rankings/" className={active === 'predictive' ? 'is-on' : ''} aria-current={active === 'predictive' ? 'page' : undefined}>CFPi+ (predictive)</Link>
    <Link to="/rankings/resume/" className={active === 'resume' ? 'is-on' : ''} aria-current={active === 'resume' ? 'page' : undefined}>Résumé</Link>
  </nav>
}

function Game({ g }: { g: NotableGame | null }) {
  if (!g) return <Missing why="None" />
  return <span className="cf-notable"><span className="cf-at">{g.loc < 0 ? 'at' : 'vs'}</span>{g.opp_fbs ? <TeamLink id={g.opp_id} name={g.opp} size={18} sub={`${g.opp_rank ? `No. ${g.opp_rank} · ` : ''}${g.pts}–${g.opp_pts}`} /> : <span>{g.opp} <span className="cf-small cf-muted">(non-FBS) {g.pts}–{g.opp_pts}</span></span>}</span>
}

export default function Resume() {
  const doc = useData<ResumeDoc>('resume.json')
  const [sk, setSk] = useQueryParam('sort', 'resume')
  const [sd, setSd] = useQueryParam('dir', 'asc')
  const sort: Sort = { key: sk, desc: sd === 'desc' }
  const onSort = (s: Sort) => { setSk(s.key); setSd(s.desc ? 'desc' : 'asc') }
  return <>
    <PageHead title="Résumé ranking" lede={<>What each team has accomplished so far. It is not a prediction: for how good teams are, see the <Link to="/rankings/">CFPi+ (predictive) rankings</Link>.</>}><RankingTabs active="resume" /></PageHead>
    <DataGate source={doc} label="Résumé ranking">{({ meta, teams, method }) => {
      const val = (r: ResumeRow) => ({ resume: r.resume_rank, predictive: r.predictive_rank, sor: r.sor == null ? null : -r.sor, sos: r.sos_played == null ? null : -r.sos_played } as Record<string, number | null>)[sort.key] ?? r.resume_rank
      const rows = sortRows(teams, val, sort.desc)
      return <>
        <Freshness meta={meta} />
        <div className="cf-table-wrap"><table className="cf-table">
          <thead><tr>
            <SortTh label="Résumé rank" sortKey="resume" sort={sort} onSort={onSort} align="start" info={RESUME_INFO} />
            <th scope="col" className="cf-th-start">Team</th>
            <th scope="col" className="cf-th-end">Record</th>
            <SortTh label="SOR" sortKey="sor" sort={sort} onSort={onSort} info="Strength of record: wins minus the benchmark team's expected wins on the same schedule." />
            <SortTh label="Schedule played" sortKey="sos" sort={sort} onSort={onSort} className="cf-hide-sm" info="Mean current CFPi+ rating of the opponents faced so far (rank among FBS)." />
            <th scope="col" className="cf-th-start cf-hide-sm">Best win</th>
            <th scope="col" className="cf-th-start cf-hide-sm">Worst loss</th>
            <SortTh label="CFPi+ (predictive) rank" sortKey="predictive" sort={sort} onSort={onSort} info="The CFPi+ power-rating rank: how good the team is, not what it has done." />
          </tr></thead>
          <tbody>{rows.map(r => <tr key={r.team_id}>
            <td className="cf-num cf-strong">{r.resume_rank ?? '—'}</td>
            <td><TeamLink id={r.team_id} size={22} /></td>
            <td className="cf-td-end cf-num">{r.wins == null ? '—' : `${r.wins}–${r.losses}`}</td>
            <td className="cf-td-end"><Num value={r.sor} signed digits={2} /></td>
            <td className="cf-td-end cf-hide-sm"><Num value={r.sos_played} signed /> <span className="cf-small cf-muted">{r.sos_played_rank ? `No. ${r.sos_played_rank}` : ''}</span></td>
            <td className="cf-hide-sm"><Game g={r.best_win} /></td>
            <td className="cf-hide-sm"><Game g={r.worst_loss} /></td>
            <td className="cf-td-end cf-num cf-muted">{r.predictive_rank ?? '—'}</td>
          </tr>)}</tbody>
        </table></div>
        <section className="cf-prose cf-resume-method">
          <h2 className="cf-h3">How the résumé rank works</h2>
          <p>{method.metric}. The benchmark is {method.benchmark}; it is the same term the simulation uses when it ranks teams for the playoff. There are no hand-set weights. Opponents are judged by their current CFPi+ rating (FCS teams by the model’s own FCS ratings), so a win’s value moves as the opponent’s season plays out. Ties go to {method.tiebreaks}.</p>
          <p>Early in the season one or two games decide it. The predictive rank is shown alongside for contrast, never combined with it.</p>
        </section>
      </>
    }}</DataGate>
  </>
}
