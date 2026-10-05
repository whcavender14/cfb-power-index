import ShareButton from '../ShareButton'
import { useMemo } from 'react'
import { ChevronDown, ChevronRight } from 'lucide-react'
import { DataGate, Freshness, InfoLabel, Missing, PageHead, pctText, SortTh, sortRows, useData, useTeams, type Sort } from '../components'
import type { GamesDoc, Game, HistoryDoc, IndexDoc } from '../data'
import { GameCard, kickoffText, lineText, gradePick, Matchup, projection, ProjectionText, Quality, QUALITY_INFO, useLines, useReview, WINPROB_INFO } from '../games'
import LineCalculator from '../LineCalculator'
import { Link, useQueryParam } from '../router'

const C = { textAlign: 'center' } as const
const BIG_GAP = 4   // "model disagrees" filter: |model margin - line| in points

function Sel({ label, value, onChange, children }: { label: string; value: string; onChange: (v: string) => void; children: React.ReactNode }) {
  return <span className="cf-select"><select aria-label={label} value={value} onChange={e => onChange(e.target.value)}>{children}</select><ChevronDown size={14} aria-hidden="true" /></span>
}

export default function Games() {
  const doc = useData<GamesDoc>('games.json')
  const teams = useTeams()
  const lines = useLines()
  const history = useData<HistoryDoc>('history.json')
  const index = useData<IndexDoc>('index.json')
  const rankOf = useMemo(() => new Map((index.data?.teams ?? []).filter(t => t.rank != null).map(t => [t.team_id, { rank: t.rank!, record: t.wins != null ? `${t.wins}–${t.losses}` : null }])), [index.data])
  const review = useReview(doc.data?.games ?? [], history.data, doc.data?.meta.season ?? 2026, doc.data?.meta.hfa ?? null)
  // Past weeks: Line = OPENING spread (home perspective, negative = home favored); Model = the pre-game projection recomputed
  // from the ratings published before that week. Current and future weeks: the current quote and the current projection.
  const openingOf = (g: Game) => review.get(g.game_id)?.market ?? null
  const quoteOf = (g: Game) => lines.get(g.game_id)?.market_spread ?? null
  // Model vs line in points, home perspective: past games use the pre-game projection and the opening spread
  const gapOf = (g: Game) => { const m = g.status === 'final' && g.week < (doc.data?.meta.current_week ?? 0) ? review.get(g.game_id)?.model ?? null : g.spread_home, k = g.week < (doc.data?.meta.current_week ?? 0) ? openingOf(g) : quoteOf(g); return m == null || k == null ? null : Math.abs(m + k) }
  const edgeOf = (g: Game) => { const k = quoteOf(g); return g.status === 'scheduled' && g.spread_home != null && k != null ? g.spread_home + k : null }
  const [week, setWeek] = useQueryParam('week')
  const [conf, setConf] = useQueryParam('conf')
  const [team, setTeam] = useQueryParam('team')
  const [gap, setGap] = useQueryParam('gap')
  const [sortKey, setSortKey] = useQueryParam('sort', 'kickoff')
  const [dir, setDir] = useQueryParam('dir', '')
  const natural = (key: string) => key !== 'kickoff'
  const sort: Sort = { key: sortKey, desc: dir ? dir === 'desc' : natural(sortKey) }
  const onSort = (s: Sort) => { setSortKey(s.key); setDir(s.desc === natural(s.key) ? '' : s.desc ? 'desc' : 'asc') }
  const conferences = useMemo(() => [...new Set([...teams.values()].map(t => t.conference).filter(Boolean) as string[])].sort(), [teams])
  const teamOptions = useMemo(() => [...teams.values()].sort((a, b) => a.team.localeCompare(b.team)), [teams])

  return <>
    <PageHead title="Games"><p className="cf-small" style={{ margin: 'var(--s2) 0 0' }}><Link to="/games/quality/" className="cf-more">Game Quality</Link></p></PageHead>
    <DataGate source={doc} label="Games">{({ meta, games }) => {
      const weeks = [...new Set(games.map(g => g.week))].sort((a, b) => a - b)
      const slug = teams.get(team) ? team : [...teams.values()].find(t => t.slug === team)?.team_id ?? ''
      const activeWeek = week === 'all' ? null : week ? Number(week) : slug ? null : meta.current_week
      const rows = games.filter(g => (activeWeek == null || g.week === activeWeek)
        && (!conf || g.home_conference === conf || g.away_conference === conf)
        && (!slug || g.home_id === slug || g.away_id === slug)
        && (!gap || (gapOf(g) ?? 0) > BIG_GAP))
      const value: Record<string, (g: Game) => number | null> = {
        kickoff: g => Date.parse(g.kickoff), quality: g => g.quality, prob: g => projection(g)?.prob ?? null, week: g => g.week,
        edge: g => { const e = edgeOf(g); return e == null ? null : Math.abs(e) },
      }
      const sorted = sortRows(rows, value[sort.key] ?? value.kickoff, sort.desc)
      const slateWeek = activeWeek ?? meta.current_week   // the weekly graphic covers every game of the shown week (filters ignored)
      const isPast = (g: Game) => meta.current_week != null && g.week < meta.current_week
      const past = sorted.filter(isPast).sort((a, b) => Date.parse(a.kickoff) - Date.parse(b.kickoff) || 0)
      if (sort.key === 'kickoff' && sort.desc) past.reverse()
      const upcoming = sorted.filter(g => !isPast(g))
      // The model's record in each past week (pre-game projection and opening spread; pushes and ungraded games excluded from the rates)
      type T = { w: number; l: number; p: number }
      const tally = (t: T) => t.w + t.l ? `${(100 * t.w / (t.w + t.l)).toFixed(1)}%` : '—'
      const byWeek = new Map<number, { su: T; ats: T }>()
      for (const g of past) {
        const gr = gradePick(g, review.get(g.game_id)?.model ?? null, openingOf(g)), rec = byWeek.get(g.week) ?? { su: { w: 0, l: 0, p: 0 }, ats: { w: 0, l: 0, p: 0 } }
        if (gr.su != null) rec.su[gr.su ? 'w' : 'l']++
        if (gr.ats != null) rec.ats[gr.ats === 'push' ? 'p' : gr.ats ? 'w' : 'l']++
        byWeek.set(g.week, rec)
      }
      const weekRecords = [...byWeek].sort((a, b) => a[0] - b[0]).map(([week, r]) => ({ week, ...r }))
      const showLines = upcoming.some(g => quoteOf(g) != null)
      return <>
        <div className="cf-toolbar" style={{ marginTop: 12, marginBottom: 0, alignItems: 'center', gap: 12 }}>
          <Sel label="Week" value={week || (slug ? 'all' : String(meta.current_week ?? 'all'))} onChange={v => setWeek(v === String(meta.current_week) && !slug ? '' : v)}>
            <option value="all">All weeks</option>
            {weeks.map(w => <option key={w} value={String(w)}>Week {w}{w === meta.current_week ? ' (this week)' : ''}</option>)}
          </Sel>
          <Sel label="Conference" value={conf} onChange={setConf}>
            <option value="">All conferences</option>
            {conferences.map(c => <option key={c} value={c}>{c}</option>)}
          </Sel>
          <Sel label="Team" value={slug ? teams.get(slug)!.slug : ''} onChange={v => setTeam(v)}>
            <option value="">All teams</option>
            {teamOptions.map(t => <option key={t.team_id} value={t.slug}>{t.team}</option>)}
          </Sel>
          <label className="cf-check"><input type="checkbox" checked={!!gap} onChange={e => setGap(e.target.checked ? '1' : '')} /> Model Edge &gt; {BIG_GAP} Pts</label>
          <p className="cf-muted cf-small" style={{ margin: 0 }} role="status">{sorted.length} {sorted.length === 1 ? 'game' : 'games'}</p>
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'flex-end', justifyContent: 'space-between', gap: 12, margin: '6px 0 12px' }}>
          <div style={{ marginTop: 'calc(-1 * var(--s3))' }}><Freshness meta={meta} /></div>
          <ShareButton label={`Week ${slateWeek ?? ''} Slate`} disabled={slateWeek == null || slateWeek < (meta.current_week ?? 0)} run={async () => (await import('../graphics')).gamesPng(meta, games, teams, slateWeek!, g => quoteOf(g), new Map((index.data?.teams ?? []).filter(t => t.rank != null).map(t => [t.team_id, t.rank!])))} />
        </div>
        {sorted.length === 0 ? <div className="cf-state"><p className="cf-state-title">No games match these filters</p></div> : <>
          {upcoming.length > 0 && <div className="cf-table-wrap cf-desktop">
            <table className="cf-table cf-games-table" style={{ tableLayout: 'fixed' }}>
              <caption className="cf-sr">Games, sortable</caption>
              <colgroup><col style={{ width: 104 }} /><col /><col style={{ width: 150 }} /><col style={{ width: 84 }} /><col style={{ width: 118 }} />{showLines && <><col style={{ width: 96 }} /><col style={{ width: 108 }} /></>}<col style={{ width: 32 }} /></colgroup>
              <thead><tr>
                <SortTh label="Kickoff" sortKey="kickoff" sort={sort} onSort={onSort} align="start" />
                <th scope="col" className="cf-th-start cf-th-match"><span className="cf-match-head"><span>Away</span><span aria-hidden="true" /><span>Home</span></span></th>
                <th scope="col" className="cf-th-start">Projection / Result</th>
                <SortTh label="Win Prob." sortKey="prob" sort={sort} onSort={onSort} info={WINPROB_INFO} />
                <SortTh label="Game Quality" sortKey="quality" sort={sort} onSort={onSort} info={QUALITY_INFO} align="start" style={C} />
                {showLines && <th scope="col" className="cf-th-start" style={C}><span className="cf-th"><InfoLabel focusable text="A single sportsbook line retrieved from CollegeFootballData for this week's games. It is shown for reference only and is never an input to CFPi+.">Line</InfoLabel></span></th>}
                {showLines && <SortTh label="Model Edge" sortKey="edge" sort={sort} onSort={onSort} align="start" style={C} info="How far the model's projected margin is from the sportsbook line, in points, and the team the model likes more than the market does. Sorting shows the biggest disagreements first. Reference only: lines are never an input to CFPi+, and this is not betting advice." />}
                <th scope="col" className="cf-th-go"><span className="cf-sr">Open matchup</span></th>
              </tr></thead>
              <tbody>{upcoming.map(g => { const p = projection(g); const k = quoteOf(g); const e = edgeOf(g); const ab = (id: string) => teams.get(id)?.abbreviation ?? teams.get(id)?.team ?? ''
                const when = new Date(g.kickoff); return <tr key={g.game_id} className="cf-row-link">
                <td className="cf-nowrap"><Link to={`/games/${g.game_id}/`} className="cf-rowlink" aria-label={`${g.away_team} ${g.neutral ? 'vs' : 'at'} ${g.home_team}: matchup breakdown`}>
                  <span style={{ display: 'block', fontWeight: 500 }}>{activeWeek == null && <span className="cf-muted">Wk {g.week} · </span>}{when.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' })}</span>
                  <span className="cf-small cf-muted">{kickoffText(g, false)}</span></Link></td>
                <td><Matchup g={g} ranks={rankOf} /></td>
                <td>{g.status === 'final' || !p ? <ProjectionText g={g} /> : p.margin < 0.05 ? 'Even' : <span className="cf-proj">{ab(p.favorite === g.home_team ? g.home_id : g.away_id)} <span className="cf-num">by {p.margin.toFixed(1)}</span></span>}</td>
                <td className="cf-num">{p?.prob != null ? pctText(p.prob) : <Missing why="No projection" />}</td>
                <td style={C}><Quality value={g.quality} /></td>
                {showLines && <td className="cf-num" style={C}>{k != null ? (k === 0 ? 'Pick’em' : `${ab(k < 0 ? g.home_id : g.away_id)} −${Math.abs(k)}`) : <Missing why="No line" />}</td>}
                {showLines && <td className="cf-num" style={C}>{e == null ? <Missing why="No line or projection" /> : Math.abs(e) < 0.05 ? <span className="cf-muted">Even</span> : <b style={{ color: 'var(--cf-accent)' }}>{ab(e > 0 ? g.home_id : g.away_id)} +{Math.abs(e).toFixed(1)}</b>}</td>}
                <td className="cf-td-go"><ChevronRight size={16} aria-hidden="true" /></td>
              </tr> })}</tbody>
            </table>
          </div>}
          {past.length > 0 && <>
            {upcoming.length > 0 && <h2 className="cf-h3" style={{ margin: '24px 0 8px' }}>Past weeks</h2>}
            <ul className="cf-small" style={{ listStyle: 'none', margin: '0 0 12px', padding: 0, display: 'grid', gap: 4 }} aria-label="The model's record by week">
              {weekRecords.map(r => <li key={r.week}><b>{weekRecords.length > 1 || activeWeek == null ? `Week ${r.week}` : `Week ${r.week} model record`}</b>{' '}
                <span className="cf-muted">Winner</span> <span className="cf-num">{r.su.w}–{r.su.l}</span> <span className="cf-muted">({tally(r.su)})</span> <span className="cf-muted">· Spread</span> <span className="cf-num">{r.ats.w}–{r.ats.l}{r.ats.p ? `–${r.ats.p}` : ''}</span> <span className="cf-muted">({tally(r.ats)})</span></li>)}
            </ul>
            <div className="cf-table-wrap cf-desktop">
            <table className="cf-table cf-games-table" style={{ tableLayout: 'fixed' }}>
              <caption className="cf-sr">Past games with the model's pre-game projection, the opening spread and the result</caption>
              <colgroup><col style={{ width: 112 }} /><col /><col style={{ width: 176 }} /><col style={{ width: 120 }} /><col style={{ width: 150 }} /><col style={{ width: 32 }} /></colgroup>
              <thead><tr>
                <SortTh label="Kickoff" sortKey="kickoff" sort={sort} onSort={onSort} align="start" />
                <th scope="col" className="cf-th-start cf-th-match"><span className="cf-match-head"><span>Away</span><span aria-hidden="true" /><span>Home</span></span></th>
                <th scope="col" className="cf-th-start">Model Projection</th>
                <th scope="col" className="cf-th-start" style={C}><span className="cf-th"><InfoLabel focusable text="The opening spread: the first line CollegeFootballData recorded for the game (DraftKings first, then ESPN Bet, Bovada, Caesars). Reference only, never an input to CFPi+.">Line</InfoLabel></span></th>
                <th scope="col" className="cf-th-start" style={C}><span className="cf-th"><InfoLabel focusable text="Final score. Winner: did the model's pre-game projected winner win? Spread: did the side the model liked against the opening spread cover? The projection uses the ratings published before that week.">Result</InfoLabel></span></th>
                <th scope="col" className="cf-th-go"><span className="cf-sr">Open matchup</span></th>
              </tr></thead>
              <tbody>{past.map(g => { const m = review.get(g.game_id)?.model ?? null; const k = openingOf(g)
                const ab = (id: string) => teams.get(id)?.abbreviation ?? teams.get(id)?.team ?? ''
                const when = new Date(g.kickoff)
                const actual = (g.home_points ?? 0) - (g.away_points ?? 0)
                const mark = (good: boolean) => <b style={{ color: good ? 'var(--cf-up)' : 'var(--cf-down)' }}>{good ? '✓' : '✗'}</b>
                const gr = gradePick(g, m, k)
                return <tr key={g.game_id} className="cf-row-link">
                <td className="cf-nowrap"><Link to={`/games/${g.game_id}/`} className="cf-rowlink" aria-label={`${g.away_team} ${g.neutral ? 'vs' : 'at'} ${g.home_team}: matchup breakdown`}>
                  <span style={{ display: 'block', fontWeight: 500 }}>{activeWeek == null && <span className="cf-muted">Wk {g.week} · </span>}{when.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' })}</span>
                  <span className="cf-small cf-muted">{kickoffText(g, false)}</span></Link></td>
                <td><Matchup g={g} ranks={rankOf} /></td>
                <td>{m == null ? <Missing why="No pre-game rating for this game" /> : Math.abs(m) < 0.05 ? 'Even' : <span className="cf-proj">{ab(m > 0 ? g.home_id : g.away_id)} <span className="cf-num">by {Math.abs(m).toFixed(1)}</span></span>}</td>
                <td className="cf-num" style={C}>{k != null ? (k === 0 ? 'Pick’em' : `${ab(k < 0 ? g.home_id : g.away_id)} −${Math.abs(k)}`) : <Missing why="No opening spread" />}</td>
                <td style={C}>
                  <span className="cf-num" style={{ display: 'block', fontWeight: 500 }}>{ab(actual >= 0 ? g.home_id : g.away_id)} {Math.max(g.home_points ?? 0, g.away_points ?? 0)}–{Math.min(g.home_points ?? 0, g.away_points ?? 0)}</span>
                  <span className="cf-small cf-muted">Winner {gr.su == null ? '—' : mark(gr.su)} · Spread {gr.ats == null ? '—' : gr.ats === 'push' ? 'Push' : mark(gr.ats)}</span></td>
                <td className="cf-td-go"><ChevronRight size={16} aria-hidden="true" /></td>
              </tr> })}</tbody>
            </table>
          </div></>}
          <div className="cf-phone cf-gamelist">{sorted.map(g => <div key={g.game_id}>
            <GameCard g={g} />
            {lines.get(g.game_id) && <p className="cf-small cf-line-note">Line: {lineText(lines.get(g.game_id)!)}</p>}
          </div>)}</div>
        </>}
        <LineCalculator />
      </>
    }}</DataGate>
  </>
}
