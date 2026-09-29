import { Fragment, useEffect, useMemo, useState } from 'react'
import type { ChartPoint } from '../confChart'
import ShareButton from '../ShareButton'
import { DataGate, Freshness, Info, InfoLabel, Num, PageHead, Pct, SortTh, sortRows, TeamLink, TeamLogo, useData, useTeams, type Sort } from '../components'
import type { Conference, ConferencesDoc, ConfStanding, GamesDoc, IndexDoc, TeamRow } from '../data'
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
      const avgs = list.map(c => c.avg_power ?? 0), lo = Math.min(...avgs), span = Math.max(1, Math.max(...avgs) - lo)
      return <>
        <Freshness meta={meta} sims />
        <div className="cf-panel cf-cl" style={{ marginTop: 12 }} role="table" aria-label="Conferences by average CFPi+ rating">
          <div className="cf-cl-row cf-cl-head" role="row">
            <span role="columnheader" /><span role="columnheader">Conference</span><span role="columnheader">Avg CFPi+</span>
            <span role="columnheader" className="cf-cl-hide cf-cl-r">Median</span><span role="columnheader" className="cf-cl-hide cf-cl-r">Top 25</span>
            <span role="columnheader" style={{ textAlign: 'center' }}><InfoLabel focusable text={EXP_INFO}>Exp. playoff</InfoLabel></span>
            <span role="columnheader" className="cf-cl-hide">Highest rated</span>
          </div>
          {list.map(c => {
            const best = top.get(c.slug), to = `/conferences/${c.slug}/`
            return <div key={c.slug} className="cf-cl-row" role="row">
              <span className="cf-cl-n" role="cell"><img src={`${import.meta.env.BASE_URL}logos/conf/${c.is_conference ? c.slug : 'ncaa'}.png`} alt="" width={28} height={28} loading="lazy" style={{ display: "block" }} /></span>
              <span role="cell"><Link to={to} className="cf-cl-name">{title(c)}</Link><span className="cf-cl-sub">{c.is_conference ? c.kind : 'Not a conference'}</span></span>
              <span role="cell" className="cf-cl-avg"><b className="cf-num"><Num value={c.avg_power} signed /></b>
                <i aria-hidden="true"><u style={{ width: `${8 + ((c.avg_power ?? lo) - lo) / span * 92}%` }} /></i></span>
              <span role="cell" className="cf-cl-hide cf-cl-r cf-num"><Num value={c.median_power} signed /></span>
              <span role="cell" className="cf-cl-hide cf-cl-r cf-num">{c.top25}<span className="cf-muted cf-small"> / {c.n}</span></span>
              <span role="cell" className="cf-num" style={{ textAlign: 'center' }}><Num value={c.exp_playoff} digits={2} /></span>
              <span role="cell" className="cf-cl-hide">{best && <TeamLink id={best.team_id} size={20} sub={`No. ${best.rank}`} />}</span>
            </div>
          })}
        </div>
        {index.data && <ConferenceComparison meta={meta} conferences={list} rows={index.data.teams} />}
      </>
    }}</DataGate>
  </>
}

/** Conference comparison graphic: a preview of the downloadable PNG (src/site/confChart.ts), with the conferences to draw
 *  selectable. Every logo on the chart is an invisible link laid over the image: hover (or focus) shows the team's key numbers,
 *  and clicking opens its team page. */
function ConferenceComparison({ meta, conferences, rows }: { meta: ConferencesDoc['meta']; conferences: Conference[]; rows: TeamRow[] }) {
  const dir = useTeams()
  const [picked, setPicked] = useState<string[]>(() => conferences.map(c => c.slug))
  const chosen = useMemo(() => conferences.filter(c => picked.includes(c.slug)), [conferences, picked])
  const [chart, setChart] = useState<{ src: string; W: number; H: number; points: ChartPoint[] } | null>(null)
  const [hot, setHot] = useState<string | null>(null)
  const byId = useMemo(() => new Map(rows.map(r => [r.team_id, r])), [rows])
  // Current place in each conference's standings (by conference record, then overall record; equal records share a place, shown "T-")
  const place = useMemo(() => {
    const out = new Map<string, string>()
    for (const c of conferences) {
      if (!c.is_conference || !c.standings) continue
      const key = (id: string) => { const st = c.standings!.find(x => x.team_id === id), r = byId.get(id), cg = (st?.conf_wins ?? 0) + (st?.conf_losses ?? 0), og = (r?.wins ?? 0) + (r?.losses ?? 0)
        return [cg ? (st!.conf_wins) / cg : 0, og ? (r!.wins ?? 0) / og : 0] }
      const ids = c.standings.map(x => x.team_id).sort((x, y) => { const a = key(x), b = key(y); return b[0] - a[0] || b[1] - a[1] })
      ids.forEach(id => {
        const k = key(id), same = ids.filter(o => key(o)[0] === k[0] && key(o)[1] === k[1]), first = ids.indexOf(same[0]) + 1
        const ord = (n: number) => `${n}${n % 100 >= 11 && n % 100 <= 13 ? 'th' : ['th', 'st', 'nd', 'rd'][n % 10 > 3 ? 0 : n % 10]}`
        out.set(id, `${same.length > 1 ? 'T-' : ''}${ord(first)}`)
      })
    }
    return out
  }, [conferences, byId])
  useEffect(() => {
    if (!chosen.length || !dir.size) { setChart(null); return }
    let live = true, url = ''
    ;(async () => {
      const { conferenceChart } = await import('../confChart')
      const c = await conferenceChart(meta, rows, chosen, dir)
      const blob = await new Promise<Blob | null>(r => c.canvas.toBlob(r, 'image/png'))
      if (live && blob) { url = URL.createObjectURL(blob); setChart({ src: url, W: c.W, H: c.H, points: c.points }) }
    })().catch(() => { if (live) setChart(null) })
    return () => { live = false; if (url) URL.revokeObjectURL(url) }
  }, [chosen, dir, meta, rows])
  const toggle = (slug: string) => setPicked(p => p.includes(slug) ? p.filter(x => x !== slug) : [...p, slug])
  const games = useData<GamesDoc>('games.json')
  const totalGames = useMemo(() => { const n = new Map<string, number>(); for (const g of games.data?.games ?? []) for (const id of [g.home_id, g.away_id]) n.set(id, (n.get(id) ?? 0) + 1); return n }, [games.data])
  const confProj = useMemo(() => new Map(conferences.flatMap(c => (c.standings ?? []).map(x => [x.team_id, x] as [string, ConfStanding]))), [conferences])
  const wl = (w: number | null | undefined, g: number | undefined) => w == null || !g ? '—' : `${w.toFixed(1)}–${(g - w).toFixed(1)}`
  const hover = chart?.points.find(p => p.id === hot), hr = hot ? byId.get(hot) : undefined, ht = hot ? dir.get(hot) : undefined
  const rk = (v: number | null | undefined, r: number | null | undefined, signed = true, d = 1) => v == null ? '—' : <><Num value={v} signed={signed} digits={d} />{r != null && <span className="cf-muted" style={{ fontSize: '.75rem', marginLeft: 5 }}>({r})</span>}</>
  return <section className="cf-section" aria-labelledby="cc-h">
    <div className="cf-panel-head"><h2 id="cc-h">Conference Comparison</h2>
      <ShareButton label="Download PNG" disabled={!chosen.length} run={async () => {
        const [{ conferenceChartCanvas }, { savePng }] = await Promise.all([import('../confChart'), import('../../exportImage')])
        await savePng(await conferenceChartCanvas(meta, rows, chosen, dir), `cfpi-conference-comparison-${meta.season}-wk${String(meta.ratings_week ?? 0).padStart(2, '0')}.png`)
      }} /></div>
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, margin: '0 0 12px' }} role="group" aria-label="Conferences to compare">
      {conferences.map(c => <button key={c.slug} type="button" className="cf-btn" aria-pressed={picked.includes(c.slug)} onClick={() => toggle(c.slug)}
        style={picked.includes(c.slug) ? { background: 'var(--cf-ink)', color: 'var(--cf-bg)' } : undefined}>{c.is_conference ? c.name : 'Independents'}</button>)}
    </div>
    <div className="cf-panel" style={{ padding: 8 }}>
      {chosen.length === 0 ? <p className="cf-muted" style={{ margin: 12 }}>Select at least one conference.</p>
        : chart ? <div style={{ position: 'relative' }}>
          <img src={chart.src} alt="Line chart of CFPi+ power rating by rank within each selected conference, with every team's logo on its point" style={{ display: 'block', width: '100%', height: 'auto', borderRadius: 8 }} />
          {chart.points.map(p => { const t = dir.get(p.id); return t ? <Link key={p.id} to={`/teams/${t.slug}/`} aria-label={`${t.team}: open team page`}
            onMouseEnter={() => setHot(p.id)} onMouseLeave={() => setHot(h => h === p.id ? null : h)} onFocus={() => setHot(p.id)} onBlur={() => setHot(h => h === p.id ? null : h)}
            style={{ position: 'absolute', left: `${100 * p.x / chart.W}%`, top: `${100 * p.y / chart.H}%`, width: `${100 * p.size / chart.W}%`, aspectRatio: '1', transform: 'translate(-50%, -50%)', outline: 'none' }} /> : null })}
          {hover && hr && ht && <div role="tooltip" style={{ position: 'absolute', zIndex: 5, pointerEvents: 'none', width: 250, padding: '12px 14px', borderRadius: 12, background: 'var(--cf-surface)', boxShadow: '0 0 0 1px var(--cf-line), 0 12px 32px rgb(0 0 0 / .18)',
            left: `${100 * hover.x / chart.W}%`, top: `${Math.min(70, Math.max(6, 100 * hover.y / chart.H - 8))}%`, transform: hover.x / chart.W > 0.6 ? `translateX(calc(-100% - ${hover.size}px))` : `translateX(${hover.size}px)` }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 10 }}>
              <TeamLogo id={hot!} name={ht.team} size={52} />
              <div style={{ minWidth: 0 }}>
                <div style={{ fontWeight: 700, fontSize: '1.125rem', lineHeight: 1.2 }}>{ht.team}</div>
                <div className="cf-muted" style={{ fontSize: '.75rem', marginTop: 2 }}>{ht.conference ?? ''}{place.get(hot!) ? ` · ${place.get(hot!)}` : ''}</div>
              </div>
            </div>
            <dl style={{ display: 'grid', gridTemplateColumns: 'auto 1fr', gap: '3px 14px', margin: 0, fontSize: '.875rem' }}>
              {([['Record', hr.wins == null ? '—' : `${hr.wins}–${hr.losses}`], ['Conf. Record', hr.conf_wins == null ? '—' : `${hr.conf_wins}–${hr.conf_losses}`],
                ['Rating', rk(hr.power, hr.rank)], ['Offense', rk(hr.off, hr.off_rank)], ['Defense', rk(hr.def, hr.def_rank)], ['SOR', rk(hr.sor, hr.sor_rank, true, 2)], ['SOS', rk(hr.sos, hr.sos_rank)],
                ['Proj. Record', wl(hr.proj_wins, totalGames.get(hot!))], ['Proj. Conf. Record', wl(confProj.get(hot!)?.avg_wins, confProj.get(hot!)?.conf_games)], ['Playoff', hr.p_playoff == null ? '—' : `${(hr.p_playoff * 100).toFixed(1)}%`]] as [string, React.ReactNode][])
                .map(([k, v]) => <Fragment key={k}><dt className="cf-muted">{k}</dt><dd className="cf-num" style={{ margin: 0, textAlign: 'right', fontWeight: 500 }}>{v}</dd></Fragment>)}
            </dl>
            <div className="cf-muted" style={{ fontSize: '.75rem', marginTop: 8 }}>Click for the team page</div>
          </div>}
        </div>
        : <p className="cf-muted" style={{ margin: 12 }} role="status">Drawing the chart…</p>}
    </div>
  </section>
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
