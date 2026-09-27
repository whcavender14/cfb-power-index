import { DataGate, Freshness, Info, Num, PageHead, Pct, SortTh, sortRows, TeamLink, useData, useTeams, type Sort } from '../components'
import type { Conference, ConferencesDoc, ConfStanding, IndexDoc, TeamRow } from '../data'
import { Link, useQueryParam } from '../router'
import NotFound from './NotFound'

const EXP_INFO = 'Expected number of this group’s teams in the 12-team playoff: the sum of its members’ playoff probabilities.'
const SOS_INFO = 'Average of the members’ full-season schedule strength (mean CFPi+ rating of all opponents).'
const record = (w: number | null, l: number | null) => w == null ? '—' : `${w}–${l}`
const title = (c: Conference) => c.is_conference ? c.name : 'Independents'

export function ConferenceList() {
  const doc = useData<ConferencesDoc>('conferences.json')
  const index = useData<IndexDoc>('index.json')
  const top = new Map<string, TeamRow>()
  for (const c of doc.data?.conferences ?? []) {
    const best = (index.data?.teams ?? []).filter(t => c.team_ids.includes(t.team_id) && t.rank != null).sort((a, b) => a.rank! - b.rank!)[0]
    if (best) top.set(c.slug, best)
  }
  return <>
    <PageHead title="Conferences" lede={<>How each conference stacks up as a group: average and median strength, depth, and expected playoff teams. For individual team ratings, use <Link to="/teams/">Teams</Link>.</>} />
    <DataGate source={doc} label="Conferences">{({ meta, conferences }) => {
      const list = [...conferences].sort((a, b) => Number(b.is_conference) - Number(a.is_conference) || (b.avg_power ?? -99) - (a.avg_power ?? -99))
      return <>
        <Freshness meta={meta} sims />
        <ol className="cf-conf-cards" aria-label="Conferences by average CFPi+ rating">{list.map(c => <li key={c.slug} className="cf-panel cf-conf-card">
          <div className="cf-conf-card-head">
            <h2 className="cf-h3"><Link to={`/conferences/${c.slug}/`}>{title(c)}</Link></h2>
            <span className="cf-badge">{c.is_conference ? `${c.kind} · No. ${c.avg_rank} of ${conferences.filter(x => x.is_conference).length}` : 'Not a conference'}</span>
          </div>
          <dl className="cf-conf-stats">
            <div><dt>Avg CFPi+</dt><dd><Num value={c.avg_power} signed /></dd></div>
            <div><dt>Median</dt><dd><Num value={c.median_power} signed /></dd></div>
            <div><dt>Top 25</dt><dd className="cf-num">{c.top25} <span className="cf-muted cf-small">of {c.n}</span></dd></div>
            <div><dt>Exp. playoff teams <Info text={EXP_INFO} label="About expected playoff teams" /></dt><dd><Num value={c.exp_playoff} digits={2} /></dd></div>
          </dl>
          {top.get(c.slug) && <p className="cf-conf-top"><span className="cf-muted cf-small">Highest rated</span> <TeamLink id={top.get(c.slug)!.team_id} size={20} sub={`No. ${top.get(c.slug)!.rank}`} /></p>}
          <Link to={`/conferences/${c.slug}/`} className="cf-more">View details</Link>
        </li>)}</ol>
      </>
    }}</DataGate>
  </>
}

/** Member strength: one bar per team from 0 (average FBS team) to its rating, on the full FBS range. */
function StrengthChart({ rows, fbsMin, fbsMax, median }: { rows: TeamRow[]; fbsMin: number; fbsMax: number; median: number }) {
  const lo = Math.floor(Math.min(fbsMin, 0) / 5) * 5, hi = Math.ceil(fbsMax / 5) * 5
  const pos = (v: number) => ((v - lo) / (hi - lo)) * 100
  const ticks: number[] = []; for (let t = Math.ceil(lo / 10) * 10; t <= hi; t += 10) ticks.push(t)
  const teams = useTeams()
  return <figure className="cf-strength">
    <div className="cf-strength-rows">
      {rows.map(r => <div key={r.team_id} className="cf-strength-row">
        <span className="cf-strength-name">{teams.get(r.team_id)?.team}</span>
        <span className="cf-strength-track">
          <i className={r.power! >= 0 ? 'is-pos' : 'is-neg'} style={{ left: `${pos(Math.min(0, r.power!))}%`, width: `${Math.abs(pos(r.power!) - pos(0))}%` }} />
          <b className="cf-strength-zero" style={{ left: `${pos(0)}%` }} />
          <b className="cf-strength-med" style={{ left: `${pos(median)}%` }} />
        </span>
        <span className="cf-strength-val cf-num"><Num value={r.power} signed /></span>
      </div>)}
    </div>
    <div className="cf-strength-axis" aria-hidden="true"><span />{/* name column */}
      <span className="cf-strength-ticks">{ticks.map(t => <em key={t} style={{ left: `${pos(t)}%` }}>{t > 0 ? `+${t}` : t < 0 ? `−${-t}` : '0'}</em>)}</span><span />
    </div>
    <figcaption className="cf-small cf-muted">Bars run from 0 (an average FBS team) to each rating; the scale spans every FBS team (weakest {fbsMin.toFixed(1).replace('-', '−')}, strongest +{fbsMax.toFixed(1)}). The dashed line is the FBS median.</figcaption>
  </figure>
}

const STANDINGS_INFO = 'Each cell is the share of the simulated seasons in which the team wins at least that many conference games (regular season). ✓ marks the win total the team has already secured; ✗ a total it can no longer reach. A blank cell is under 1% or already certain. Avg. is the expected final conference wins.'

/** Projected conference standings: chance to win at least N conference games, from the simulated seasons. */
function ConfWinOdds({ rows, sims }: { rows: ConfStanding[]; sims: number | null }) {
  const top = Math.max(...rows.map(r => r.conf_games))
  const cols = Array.from({ length: top + 1 }, (_, i) => top - i)
  const sorted = [...rows].sort((a, b) => b.avg_wins - a.avg_wins || b.conf_wins - a.conf_wins)
  return <div className="cf-table-wrap"><table className="cf-table cf-table-compact cf-confodds">
    <caption className="cf-sr">Chance to win at least N conference games</caption>
    <thead><tr>
      <th scope="col" className="cf-th-start cf-hide-sm">Rk</th>
      <th scope="col" className="cf-th-start">Team</th>
      <th scope="col">Conf.</th>
      <th scope="col">Avg.</th>
      {cols.map(n => <th scope="col" key={n} className="cf-co-n">{n}</th>)}
    </tr></thead>
    <tbody>{sorted.map((r, i) => <tr key={r.team_id}>
      <td className="cf-td-end cf-num cf-muted cf-hide-sm">{i + 1}</td>
      <td><TeamLink id={r.team_id} size={20} /></td>
      <td className="cf-td-end cf-num">{r.conf_wins}–{r.conf_losses}</td>
      <td className="cf-td-end cf-num">{r.avg_wins.toFixed(1)}</td>
      {cols.map(n => {
        if (n > r.conf_games - r.conf_losses) return <td key={n} className="cf-co-cell cf-co-out" aria-label={`${n}: no longer possible`}>✗</td>
        if (n === r.conf_wins) return <td key={n} className="cf-co-cell cf-co-done" aria-label={`${n}: secured`}>✓</td>
        const p = n < r.conf_wins ? 1 : r.p_ge[n]
        if (p < 0.005 || p >= 0.995) return <td key={n} className="cf-co-cell" />
        return <td key={n} className="cf-co-cell cf-num" style={{ backgroundColor: `rgb(var(--cf-heat) / ${(0.06 + p * 0.5).toFixed(2)})` }}>{Math.round(p * 100)}%</td>
      })}
    </tr>)}</tbody>
  </table>{sims ? <p className="cf-small cf-muted cf-co-note">Share of {sims.toLocaleString()} simulated seasons with at least this many conference wins. <Info text={STANDINGS_INFO} label="How to read this table" /></p> : null}</div>
}

export function ConferenceDetail({ slug }: { slug: string }) {
  const doc = useData<ConferencesDoc>('conferences.json')
  const index = useData<IndexDoc>('index.json')
  const [sk, setSk] = useQueryParam('sort', 'power')
  const [sd, setSd] = useQueryParam('dir', 'desc')
  const sort: Sort = { key: sk, desc: sd !== 'asc' }
  const onSort = (s: Sort) => { setSk(s.key); setSd(s.desc ? 'desc' : 'asc') }
  return <DataGate source={doc} label="Conference">{({ conferences }) => {
    const c = conferences.find(x => x.slug === slug)
    if (!c) return <NotFound />
    return <DataGate source={index} label="Ratings">{({ meta, teams }) => {
      const members = teams.filter(t => c.team_ids.includes(t.team_id))
      const powers = teams.map(t => t.power).filter((v): v is number => v != null).sort((a, b) => a - b)
      const median = powers.length ? (powers[(powers.length - 1) >> 1] + powers[powers.length >> 1]) / 2 : 0
      const val = (r: TeamRow) => ({ power: r.power, rank: r.rank == null ? null : -r.rank, conf: r.conf_wins == null ? null : r.conf_wins - (r.conf_losses ?? 0), wins: r.wins == null ? null : r.wins - (r.losses ?? 0), p_conf: r.p_conf, p_playoff: r.p_playoff } as Record<string, number | null>)[sort.key] ?? r.power
      const rows = sortRows(members, val, sort.desc)
      const byPower = [...members].sort((a, b) => (b.power ?? -99) - (a.power ?? -99))
      return <>
        <nav className="cf-crumbs" aria-label="Breadcrumb"><Link to="/conferences/">Conferences</Link><span aria-hidden="true"> / </span><span aria-current="page">{title(c)}</span></nav>
        <PageHead title={title(c)} lede={c.is_conference ? `${c.kind} conference · ${c.n} FBS teams in ${meta.season}. Membership comes from the season’s team metadata.` : `${c.n} FBS independents in ${meta.season}. They play no conference schedule and cannot win a conference title; they are grouped here for comparison only.`} />
        <Freshness meta={meta} sims />
        <dl className="cf-statgrid">
          <div><dt>Average CFPi+</dt><dd className="cf-big"><Num value={c.avg_power} signed /></dd><dd className="cf-small cf-muted">{c.is_conference ? `No. ${c.avg_rank} of ${conferences.filter(x => x.is_conference).length} conferences` : ''}</dd></div>
          <div><dt>Median CFPi+</dt><dd className="cf-big"><Num value={c.median_power} signed /></dd></div>
          <div><dt>Top-25 teams</dt><dd className="cf-big cf-num">{c.top25}</dd><dd className="cf-small cf-muted">Best: No. {c.best_rank ?? '—'}</dd></div>
          <div><dt>Exp. playoff teams <Info text={EXP_INFO} label="About expected playoff teams" /></dt><dd className="cf-big"><Num value={c.exp_playoff} digits={2} /></dd></div>
          <div><dt>Schedule strength <Info text={SOS_INFO} label="About schedule strength" /></dt><dd className="cf-big"><Num value={c.sos_avg} signed /></dd></div>
          <div><dt>Non-conference record</dt><dd className="cf-big cf-num">{record(c.nonconf_wins, c.nonconf_losses)}</dd><dd className="cf-small cf-muted">{record(c.nonconf_fbs_wins, c.nonconf_fbs_losses)} vs FBS</dd></div>
        </dl>
        {c.is_conference && c.standings && c.standings.length > 0 && <section className="cf-section" aria-labelledby="cf-odds">
          <div className="cf-section-head"><h2 id="cf-odds">Projected conference standings</h2></div>
          <ConfWinOdds rows={c.standings} sims={meta.sim_count} />
        </section>}
        <div className="cf-conf-grid">
          <section className="cf-panel" aria-labelledby="cf-str"><h2 id="cf-str" className="cf-h2">Team strength</h2>
            <StrengthChart rows={byPower} fbsMin={powers[0] ?? 0} fbsMax={powers[powers.length - 1] ?? 0} median={median} />
          </section>
          <section className="cf-panel" aria-labelledby="cf-tm"><h2 id="cf-tm" className="cf-h2">Teams</h2>
            <div className="cf-table-wrap"><table className="cf-table cf-table-compact">
              <thead><tr>
                <th scope="col" className="cf-th-start">Team</th>
                <SortTh label="CFPi+" sortKey="power" sort={sort} onSort={onSort} />
                <SortTh label="Rank" sortKey="rank" sort={sort} onSort={onSort} className="cf-hide-sm" />
                <SortTh label="Record" sortKey="wins" sort={sort} onSort={onSort} />
                {c.is_conference && <SortTh label="Conf." sortKey="conf" sort={sort} onSort={onSort} />}
                {c.is_conference && <SortTh label="Title" sortKey="p_conf" sort={sort} onSort={onSort} className="cf-hide-sm" info="Probability of winning the conference title in the simulations." />}
                <SortTh label="Playoff" sortKey="p_playoff" sort={sort} onSort={onSort} />
              </tr></thead>
              <tbody>{rows.map(r => <tr key={r.team_id}>
                <td><TeamLink id={r.team_id} size={20} /></td>
                <td className="cf-td-end"><Num value={r.power} signed /></td>
                <td className="cf-td-end cf-num cf-hide-sm">{r.rank ?? '—'}</td>
                <td className="cf-td-end cf-num">{record(r.wins, r.losses)}</td>
                {c.is_conference && <td className="cf-td-end cf-num">{record(r.conf_wins, r.conf_losses)}</td>}
                {c.is_conference && <td className="cf-td-end cf-hide-sm"><Pct value={r.p_conf} /></td>}
                <td className="cf-td-end"><Pct value={r.p_playoff} /></td>
              </tr>)}</tbody>
            </table></div>
          </section>
        </div>
      </>
    }}</DataGate>
  }}</DataGate>
}
