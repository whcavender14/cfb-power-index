import '../conferences.css'
import { teamTheme, CONF_COLORS } from '../teamTheme'
import { Fragment, useMemo, useState } from 'react'
import { ConferenceSvg, confColor, confShort, layoutChart, useElementWidth } from '../ConferenceChart'
import { Search, X } from 'lucide-react'
import ShareButton from '../ShareButton'
import { DataGate, fmt, Freshness, InfoLabel, InView, Num, PageHead, Pct, SortTh, sortRows, TeamLink, TeamLogo, useData, useTeams, useThemeName, type Sort } from '../components'
import { kickoffText, projection } from '../games'
import type { Conference, ConferencesDoc, Game, ConfStanding, GamesDoc, IndexDoc, TeamRow } from '../data'
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
    <PageHead title="Conferences" />
    <DataGate source={doc} label="Conferences">{({ meta, conferences }) => {
      const list = [...conferences].sort((a, b) => Number(b.is_conference) - Number(a.is_conference) || (b.avg_power ?? -99) - (a.avg_power ?? -99))
      const avgs = list.map(c => c.avg_power ?? 0), lo = Math.min(...avgs), span = Math.max(1, Math.max(...avgs) - lo)
      return <>
        <Freshness meta={meta} sims />
        <InView className="cf-panel cf-cl" style={{ marginTop: 12 }} role="table" aria-label="Conferences by average CFPi+ rating">
          <div className="cf-cl-row cf-cl-head" role="row">
            <span role="columnheader" /><span role="columnheader">Conference</span><span role="columnheader">Avg CFPi+</span>
            <span role="columnheader" className="cf-cl-hide cf-cl-r">Median</span><span role="columnheader" className="cf-cl-hide cf-cl-r">Top 25</span>
            <span role="columnheader" style={{ textAlign: 'center' }}><InfoLabel focusable text={EXP_INFO}>Exp. playoff</InfoLabel></span>
            <span role="columnheader" className="cf-cl-hide">Highest rated</span>
          </div>
          {list.map(c => {
            const best = top.get(c.slug), to = `/conferences/${c.slug}/`
            return <div key={c.slug} className="cf-cl-row" role="row">
              <span className="cf-cl-n" role="cell"><img src={`${import.meta.env.BASE_URL}logos/conf/${c.slug}.png`} alt="" width={72} height={72} loading="lazy" style={{ display: "block", objectFit: "contain", width: 72, height: 72 }} /></span>
              <span role="cell"><Link to={to} className="cf-cl-name">{title(c)}</Link><span className="cf-cl-sub">{c.is_conference ? c.kind : 'Not a conference'}</span></span>
              <span role="cell" className="cf-cl-avg"><b className="cf-num"><Num value={c.avg_power} signed /></b>
                <i aria-hidden="true"><u style={{ width: `${8 + ((c.avg_power ?? lo) - lo) / span * 92}%` }} /></i></span>
              <span role="cell" className="cf-cl-hide cf-cl-r cf-num"><Num value={c.median_power} signed /></span>
              <span role="cell" className="cf-cl-hide cf-cl-r cf-num">{c.top25}<span className="cf-muted cf-small"> / {c.n}</span></span>
              <span role="cell" className="cf-num" style={{ textAlign: 'center' }}><Num value={c.exp_playoff} digits={2} /></span>
              <span role="cell" className="cf-cl-hide">{best && <TeamLink id={best.team_id} size={20} sub={`No. ${best.rank}`} />}</span>
            </div>
          })}
        </InView>
        {index.data && <ConferenceComparison meta={meta} conferences={list} rows={index.data.teams} />}
      </>
    }}</DataGate>
  </>
}

/** Conference comparison chart: native SVG (src/site/ConferenceChart.tsx) with the conferences to draw selectable; the PNG
 *  download is drawn separately by src/site/confChart.ts. Every logo is an invisible link laid over the chart: hover (or focus)
 *  shows the team's key numbers, and clicking opens its team page. */
function ConferenceComparison({ meta, conferences, rows }: { meta: ConferencesDoc['meta']; conferences: Conference[]; rows: TeamRow[] }) {
  const dir = useTeams()
  const [picked, setPicked] = useState<string[]>(() => conferences.map(c => c.slug))
  const chosen = useMemo(() => conferences.filter(c => picked.includes(c.slug)), [conferences, picked])
  const dark = useThemeName() === 'dark'
  const [find, setFind] = useState('')
  const [wrap, width] = useElementWidth<HTMLDivElement>()
  const chart = useMemo(() => width > 0 && chosen.length && dir.size ? layoutChart(width, chosen, conferences, rows, dark) : null, [width, chosen, conferences, rows, dark, dir])
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
  // Team finder: teams on the chart whose name, mascot or abbreviation matches (2+ characters); null = no search.
  const hits = useMemo(() => {
    const norm = (s: string) => s.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9 ]/g, '').trim()
    const n = norm(find)
    if (n.length < 2 || !chart) return null
    const out = new Set<string>()
    for (const p of chart.points) { const t = dir.get(p.id); if (t && (norm(`${t.team} ${t.mascot ?? ''}`).includes(n) || norm(t.abbreviation ?? '') === n)) out.add(p.id) }
    return out
  }, [find, chart, dir])
  const toggle = (slug: string) => setPicked(p => p.includes(slug) ? p.filter(x => x !== slug) : [...p, slug])
  const games = useData<GamesDoc>('games.json')
  const totalGames = useMemo(() => { const n = new Map<string, number>(); for (const g of games.data?.games ?? []) for (const id of [g.home_id, g.away_id]) n.set(id, (n.get(id) ?? 0) + 1); return n }, [games.data])
  const confProj = useMemo(() => new Map(conferences.flatMap(c => (c.standings ?? []).map(x => [x.team_id, x] as [string, ConfStanding]))), [conferences])
  const wl = (w: number | null | undefined, g: number | undefined) => w == null || !g ? '—' : `${w.toFixed(1)}–${(g - w).toFixed(1)}`
  const hover = chart?.points.find(p => p.id === hot), hr = hot ? byId.get(hot) : undefined, ht = hot ? dir.get(hot) : undefined
  const rk = (v: number | null | undefined, r: number | null | undefined, signed = true, d = 1) => v == null ? '—' : <><Num value={v} signed={signed} digits={d} />{r != null && <span className="cf-muted" style={{ fontSize: '.75rem', marginLeft: 5 }}>({r})</span>}</>
  return <section className="cf-section" aria-labelledby="cc-h">
    <div className="cf-panel-head"><h2 id="cc-h">Conference Comparison</h2>
      <span className="cf-cc-tools">
      <label className="cf-search"><Search size={15} aria-hidden="true" />
        <input type="search" placeholder="Find a team…" aria-label="Find a team on the chart" autoComplete="off" spellCheck={false} value={find} onChange={e => setFind(e.target.value)} onKeyDown={e => { if (e.key === 'Escape') setFind('') }} />
        {find && <button type="button" aria-label="Clear search" onClick={() => setFind('')}><X size={14} aria-hidden="true" /></button>}
      </label>
      <ShareButton label="Download PNG" disabled={!chosen.length} run={async () => {
        const [{ conferenceChartCanvas }, { savePng }] = await Promise.all([import('../confChart'), import('../../exportImage')])
        await savePng(await conferenceChartCanvas(meta, rows, chosen, dir), `cfpi-conference-comparison-${meta.season}-wk${String(meta.ratings_week ?? 0).padStart(2, '0')}.png`)
      }} /></span></div>
    <div className="cf-cc-toggles" role="group" aria-label="Conferences to compare">
      {conferences.map(c => <button key={c.slug} type="button" className="cf-btn cf-cc-toggle" aria-pressed={picked.includes(c.slug)} onClick={() => toggle(c.slug)}
        style={picked.includes(c.slug) ? { background: 'var(--cf-ink)', color: 'var(--cf-bg)' } : undefined}>
        <i className={`cf-cc-swatch${c.is_conference ? '' : ' is-dot'}`} style={{ background: confColor(conferences.indexOf(c), dark) }} aria-hidden="true" /><span className="cf-cc-full">{c.is_conference ? c.name : 'Independents'}</span><span className="cf-cc-short" aria-hidden="true">{confShort(c)}</span></button>)}
    </div>
    <div className="cf-panel" ref={wrap}>
      {find.trim().length >= 2 && chart && hits && hits.size === 0 && <p className="cf-muted cf-small" role="status" style={{ margin: '4px 0 0' }}>No team matching “{find.trim()}” in the selected conferences.</p>}
      {chosen.length === 0 ? <p className="cf-muted" style={{ margin: 12 }}>Select at least one conference.</p>
        : chart ? <InView key={chosen.map(c => c.slug).join()} style={{ position: 'relative' }}>
          <ConferenceSvg L={chart} dir={dir} hits={hits} />
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
        </InView>
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
  return <InView as="figure" className="cf-strength">
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
  </InView>
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
  </table>{sims ? <p className="cf-small cf-muted cf-co-note"><InfoLabel focusable text={STANDINGS_INFO}>Share of {sims.toLocaleString()} simulated seasons with at least this many conference wins.</InfoLabel></p> : null}</div>
}

/** Head-to-head record against every other conference, from final games in games.json (both teams FBS, different groups). */
function VsConferences({ c, conferences }: { c: Conference; conferences: Conference[] }) {
  const games = useData<GamesDoc>('games.json')
  if (!games.data) return null
  const rows = new Map<string, { w: number; l: number; t: number; diff: number }>()
  for (const g of games.data.games) {
    if (g.status !== 'final' || g.home_points == null || g.away_points == null || !g.home_fbs || !g.away_fbs) continue
    const homeIs = g.home_conference === c.name, awayIs = g.away_conference === c.name
    if (homeIs === awayIs) continue
    const opp = homeIs ? g.away_conference : g.home_conference
    if (!opp) continue
    const mine = homeIs ? g.home_points : g.away_points, theirs = homeIs ? g.away_points : g.home_points
    const r = rows.get(opp) ?? { w: 0, l: 0, t: 0, diff: 0 }
    if (mine > theirs) r.w++; else if (mine < theirs) r.l++; else r.t++
    r.diff += mine - theirs
    rows.set(opp, r)
  }
  const list = conferences.filter(x => x.name !== c.name && rows.has(x.name)).map(x => ({ x, ...rows.get(x.name)! }))
    .sort((a, b) => (b.w - b.l) - (a.w - a.l) || b.w - a.w)
  const total = list.reduce((a, r) => ({ w: a.w + r.w, l: a.l + r.l }), { w: 0, l: 0 })
  return <section className="cf-panel cf-vs" aria-labelledby="cf-vs">
    <div className="cf-panel-head"><h2 id="cf-vs" className="cf-h2">Record vs. Other Conferences</h2><span className="cf-small cf-muted">{total.w}–{total.l} against FBS conferences</span></div>
    {list.length === 0 ? <p className="cf-muted">No games against other conferences yet.</p> : <ul className="cf-vs-list" style={{ ['--rows' as string]: Math.ceil(list.length / 2) }}>{list.map(({ x, w, l, t, diff }) => {
      const n = w + l + t
      return <li key={x.slug}><Link to={`/conferences/${c.slug}/vs/${x.slug}/`} className="cf-vs-row" aria-label={`${title(c)} vs. ${title(x)}: ${w}–${l}. See the games`}>
        <span className="cf-vs-id"><img src={`${import.meta.env.BASE_URL}logos/conf/${x.slug}.png`} alt="" width={40} height={40} loading="lazy" /><span>{title(x)}</span></span>
        <b className="cf-num cf-vs-rec">{w}–{l}{t ? `–${t}` : ''}</b>
        <span className="cf-vs-bar" role="img" aria-label={`${w} wins, ${l} losses`}><i className="is-w" style={{ width: `${(w / n) * 100}%` }} /><i className="is-l" style={{ width: `${(l / n) * 100}%` }} /></span>
        <span className="cf-small cf-muted cf-num cf-vs-diff">{diff > 0 ? '+' : diff < 0 ? '−' : ''}{Math.abs(diff)} pts</span>
      </Link></li> })}</ul>}
  </section>
}

/** Vegas-style model line: favorite and negative margin (Northwestern −35.5), or Pick’em / no line. */
function LineText({ g }: { g: Game }) {
  const p = projection(g)
  if (!p) return <span className="cf-muted">No line</span>
  return p.margin < 0.05 ? <span className="cf-muted">Pick’em</span> : <><span>{p.favorite}</span> <b className="cf-num">−{fmt(p.margin)}</b></>
}

/** Every game between two conferences (final and upcoming), from the first conference's point of view. */
export function ConferenceVs({ slug, other }: { slug: string; other: string }) {
  const doc = useData<ConferencesDoc>('conferences.json')
  const gamesDoc = useData<GamesDoc>('games.json')
  return <DataGate source={doc} label="Conference">{({ conferences }) => <DataGate source={gamesDoc} label="Games">{({ games, meta }) => {
    const a = conferences.find(x => x.slug === slug), b = conferences.find(x => x.slug === other)
    if (!a || !b || a.slug === b.slug) return <NotFound />
    const list = games.filter(g => g.home_fbs && g.away_fbs && ((g.home_conference === a.name && g.away_conference === b.name) || (g.home_conference === b.name && g.away_conference === a.name)))
      .sort((x, y) => x.kickoff.localeCompare(y.kickoff))
    const mine = (g: Game) => g.home_conference === a.name ? { pts: g.home_points, opp: g.away_points } : { pts: g.away_points, opp: g.home_points }
    const done = list.filter(g => g.status === 'final' && g.home_points != null && g.away_points != null)
    let w = 0, l = 0, diff = 0
    for (const g of done) { const m = mine(g); if (m.pts! > m.opp!) w++; else if (m.pts! < m.opp!) l++; diff += m.pts! - m.opp! }
    const [pc, ac] = CONF_COLORS[a.slug] ?? CONF_COLORS['fbs-independents']
    const logo = (x: Conference) => <span className="cf-confhero-logo"><img src={`${import.meta.env.BASE_URL}logos/conf/${x.slug}.png`} alt="" width={160} height={160} /></span>
    return <div className="cf-themed" style={teamTheme(pc, ac)}>
      <nav className="cf-crumbs" aria-label="Breadcrumb"><Link to="/conferences/">Conferences</Link><span aria-hidden="true"> / </span><Link to={`/conferences/${a.slug}/`}>{title(a)}</Link><span aria-hidden="true"> / </span><span aria-current="page">vs. {title(b)}</span></nav>
      <header className="cf-teamhead cf-confhead cf-vshead">
        <span className="cf-vshead-logos">{logo(a)}<em>vs.</em>{logo(b)}</span>
        <div className="cf-teamhead-id"><h1>{title(a)} vs. {title(b)}</h1>
          <p className="cf-lede">{done.length === 0 ? 'No games played yet' : <>{w}–{l} · {diff > 0 ? '+' : diff < 0 ? '−' : ''}{Math.abs(diff)} points</>}</p></div>
      </header>
      <Freshness meta={meta} />
      <section className="cf-panel cf-vsgames" aria-labelledby="cf-vsg">
        <div className="cf-panel-head"><h2 id="cf-vsg" className="cf-h2">Games</h2><span className="cf-small cf-muted">{list.length} {list.length === 1 ? 'game' : 'games'} · {done.length} played</span></div>
        {list.length === 0 ? <p className="cf-muted">These conferences do not play each other this season.</p> : <ol className="cf-vsg-list">{list.map(g => {
          const fin = done.includes(g), m = mine(g), won = fin && m.pts! > m.opp!
          return <li key={g.game_id} className={fin ? (won ? 'is-w' : 'is-l') : ''}>
            <span className="cf-vsg-when"><b>Wk {g.week}</b><span className="cf-muted cf-small">{kickoffText(g)}</span></span>
            <span className="cf-vsg-team"><TeamLink id={g.away_id} name={g.away_team} size={28} /></span>
            <span className="cf-vsg-at cf-muted">{g.neutral ? 'vs' : 'at'}</span>
            <span className="cf-vsg-team"><TeamLink id={g.home_id} name={g.home_team} size={28} /></span>
            {fin ? <><b className="cf-vsg-badge">{won ? 'W' : 'L'}</b><span className="cf-num cf-vsg-score">{m.pts}–{m.opp}</span></>
              : <span className="cf-vsg-upcoming" title="Model line: favorite and projected margin"><LineText g={g} /></span>}
            <Link to={`/games/${g.game_id}/`} className="cf-vsg-more" aria-label={`${g.away_team} ${g.neutral ? 'vs' : 'at'} ${g.home_team}: matchup breakdown`}>Details</Link>
          </li> })}</ol>}
      </section>
    </div>
  }}</DataGate>}</DataGate>
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
      return <div className="cf-themed" style={teamTheme(...(CONF_COLORS[c.slug] ?? CONF_COLORS['fbs-independents']))}>
        <nav className="cf-crumbs" aria-label="Breadcrumb"><Link to="/conferences/">Conferences</Link><span aria-hidden="true"> / </span><span aria-current="page">{title(c)}</span></nav>
        <header className="cf-teamhead cf-confhead">
          <span className="cf-confhero-logo"><img src={`${import.meta.env.BASE_URL}logos/conf/${c.slug}.png`} alt="" width={160} height={160} /></span>
          <div className="cf-teamhead-id"><h1>{title(c)}</h1><p className="cf-lede">{c.n} {c.n === 1 ? 'Team' : 'Teams'}</p></div>
        <dl className="cf-teamhead-stats">{(() => {
          type Conf = (typeof conferences)[number]
          const peers = conferences.filter(x => x.is_conference)
          const rk = (f: (x: Conf) => number | null | undefined) => {
            const v = f(c); if (!c.is_conference || v == null) return null
            return 1 + peers.filter(x => (f(x) ?? -Infinity) > v).length
          }
          const rank = (f: (x: Conf) => number | null | undefined, extra?: string) => {
            const r = rk(f); const bits = [r ? `No. ${r} of ${peers.length}` : null, extra].filter(Boolean)
            return <dd className="cf-small cf-muted">{bits.join(' · ') || '\u00a0'}</dd>
          }
          const ncPct = (x: Conf) => x.nonconf_wins != null && x.nonconf_losses != null && x.nonconf_wins + x.nonconf_losses > 0 ? x.nonconf_wins / (x.nonconf_wins + x.nonconf_losses) : null
          return <>
            <div><dt>Average CFPi+</dt><dd className="cf-big"><Num value={c.avg_power} signed /></dd>{rank(x => x.avg_power)}</div>
            <div><dt>Median CFPi+</dt><dd className="cf-big"><Num value={c.median_power} signed /></dd>{rank(x => x.median_power)}</div>
            <div><dt>Top-25 teams</dt><dd className="cf-big cf-num">{c.top25}</dd>{rank(x => x.top25, `Best: No. ${c.best_rank ?? '—'}`)}</div>
            <div><dt><InfoLabel focusable text={EXP_INFO}>Exp. playoff teams</InfoLabel></dt><dd className="cf-big"><Num value={c.exp_playoff} digits={2} /></dd>{rank(x => x.exp_playoff)}</div>
            <div><dt><InfoLabel focusable text={SOS_INFO}>Schedule strength</InfoLabel></dt><dd className="cf-big"><Num value={c.sos_avg} signed /></dd>{rank(x => x.sos_avg)}</div>
            <div><dt>Non-conference record</dt><dd className="cf-big cf-num">{record(c.nonconf_wins, c.nonconf_losses)}</dd>{rank(ncPct, `${record(c.nonconf_fbs_wins, c.nonconf_fbs_losses)} vs FBS`)}</div>
          </>
        })()}
        </dl>
        </header>
        <Freshness meta={meta} sims />
        {c.is_conference && c.standings && c.standings.length > 0 && <section className="cf-section" aria-labelledby="cf-odds">
          <div className="cf-section-head"><h2 id="cf-odds">Projected Conference Standings</h2></div>
          <ConfWinOdds rows={c.standings} sims={meta.sim_count} />
        </section>}
        <VsConferences c={c} conferences={conferences} />
        <div className="cf-conf-grid">
          <section className="cf-panel" aria-labelledby="cf-str"><h2 id="cf-str" className="cf-h2">Team Strength</h2>
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
      </div>
    }}</DataGate>
  }}</DataGate>
}
