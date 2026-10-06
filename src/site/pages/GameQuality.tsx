import { Fragment, useMemo, useState } from 'react'
import { ChevronRight } from 'lucide-react'
import { DataGate, PageHead, SortTh, sortRows, useData, type Sort } from '../components'
import type { GamesDoc, HistoryDoc } from '../data'
import { gameQualities, kickoffText, Matchup, Quality } from '../games'
import { Link, useQueryParam } from '../router'

const C = { textAlign: 'center' } as const
const TOP_N = 10   // a week's rating is the average Game Quality of its 10 best games (all of them if the week has fewer)
const BEST = 25
const day = (t: number, o: Intl.DateTimeFormatOptions) => new Date(t).toLocaleDateString('en-US', o)
/** "Sep 12–14", or "Sep 30–Oct 3" when the week spans two months. */
const dates = (times: number[]) => { const a = Math.min(...times), b = Math.max(...times), x = day(a, { month: 'short', day: 'numeric' }), y = day(b, { month: 'short', day: 'numeric' })
  return x === y ? x : day(a, { month: 'short' }) === day(b, { month: 'short' }) ? `${x}–${day(b, { day: 'numeric' })}` : `${x}–${y}` }

export default function GameQuality() {
  const doc = useData<GamesDoc>('games.json')
  const history = useData<HistoryDoc>('history.json')
  const quality = useMemo(() => doc.data ? gameQualities(doc.data.games, history.data, doc.data.meta.hfa ?? null, doc.data.meta.sigma ?? null) : new Map<string, number>(), [doc.data, history.data])
  const [open, setOpen] = useState<Set<number>>(new Set())
  const [sortKey, setSortKey] = useQueryParam('sort', 'week')
  const [dir, setDir] = useQueryParam('dir', '')
  const natural = (k: string) => k !== 'week'
  const sort: Sort = { key: sortKey, desc: dir ? dir === 'desc' : natural(sortKey) }
  const onSort = (x: Sort) => { setSortKey(x.key); setDir(x.desc === natural(x.key) ? '' : x.desc ? 'desc' : 'asc') }
  const toggle = (w: number) => setOpen(o => { const n = new Set(o); if (n.has(w)) n.delete(w); else n.add(w); return n })
  return <>
    <PageHead title="Game Quality" />
    <DataGate source={doc} label="Games">{({ games, meta }) => {
      const scored = games.filter(g => quality.has(g.game_id)).map(g => ({ g, q: quality.get(g.game_id)! }))
      const weeks = [...new Set(scored.map(s => s.g.week))].sort((a, b) => a - b).map(week => {
        const list = scored.filter(s => s.g.week === week).sort((a, b) => b.q - a.q || Date.parse(a.g.kickoff) - Date.parse(b.g.kickoff))
        const top = list.slice(0, TOP_N)
        return { week, n: list.length, top, rating: top.reduce((s, x) => s + x.q, 0) / top.length, best: list[0], when: dates(list.map(x => Date.parse(x.g.kickoff))) }
      })
      const shownWeeks = sortRows(weeks, w => sort.key === 'rating' ? w.rating : sort.key === 'quality' ? w.best.q : w.week, sort.desc)
      const maxRating = Math.max(...weeks.map(w => w.rating), 1)
      const best = [...scored].sort((a, b) => b.q - a.q || Date.parse(a.g.kickoff) - Date.parse(b.g.kickoff)).slice(0, BEST)
      const pending = games.some(g => g.status === 'final') && !history.data
      return <>
        <section className="cf-section" style={{ marginTop: 'var(--s3)' }} aria-labelledby="gq-weeks">
          <div className="cf-panel-head"><h2 id="gq-weeks">Weekly Ratings</h2></div>
          <div className="cf-table-wrap"><table className="cf-table" style={{ tableLayout: 'fixed' }}>
            <caption className="cf-sr">Weekly Game Quality ratings; select a week to see its {TOP_N} best games</caption>
            <colgroup><col style={{ width: 110 }} /><col style={{ width: 130 }} /><col style={{ width: '26%' }} /><col style={{ width: 70 }} /><col /><col style={{ width: 90 }} /></colgroup>
            <thead><tr>
              <SortTh label="Week" sortKey="week" sort={sort} onSort={onSort} align="start" />
              <th scope="col" className="cf-th-start">Dates</th>
              <SortTh label="Weekly Rating" sortKey="rating" sort={sort} onSort={onSort} align="start" />
              <th scope="col" style={C}>Games</th>
              <th scope="col" style={C}>Best Game</th>
              <SortTh label="Quality" sortKey="quality" sort={sort} onSort={onSort} align="start" style={C} />
            </tr></thead>
            <tbody>{shownWeeks.map(w => { const on = open.has(w.week); return <Fragment key={w.week}>
              <tr className={`cf-row-link${w.week === meta.current_week ? ' is-picked' : ''}`} onClick={() => toggle(w.week)}>
                <td><button type="button" onClick={e => { e.stopPropagation(); toggle(w.week) }} aria-expanded={on} aria-label={`Week ${w.week}: ${on ? 'hide' : 'show'} the ${TOP_N} best games`}
                  style={{ display: 'inline-flex', alignItems: 'center', gap: 6, border: 0, background: 'none', padding: 0, font: 'inherit', fontWeight: 600, color: 'inherit', cursor: 'pointer' }}>
                  <ChevronRight size={14} aria-hidden="true" style={{ transform: on ? 'rotate(90deg)' : 'none', transition: 'transform var(--m-quick) var(--cf-ease)' }} />Week {w.week}</button></td>
                <td className="cf-num">{w.when}</td>
                <td><span style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <span className="cf-num" style={{ width: 34, fontWeight: 600 }}>{w.rating.toFixed(1)}</span>
                  <span className="cf-bar" style={{ flex: 1, maxWidth: 140 }} aria-hidden="true"><i style={{ width: `${100 * w.rating / maxRating}%` }} /></span></span></td>
                <td className="cf-num" style={C}>{w.n}</td>
                <td><Matchup g={w.best.g} /></td>
                <td className="cf-num" style={C}>{w.best.q}</td>
              </tr>
              {on && <tr><td colSpan={6} style={{ padding: 0, background: 'var(--cf-fill-2)' }}>
                <table className="cf-table" style={{ tableLayout: 'fixed', background: 'transparent' }}>
                  <colgroup><col style={{ width: 56 }} /><col style={{ width: 168 }} /><col /><col style={{ width: 130 }} /><col style={{ width: 110 }} /></colgroup>
                  <tbody>{w.top.map(({ g, q }, i) => <tr key={g.game_id} className="cf-row-link">
                    <td className="cf-num" style={{ ...C, fontWeight: 600 }}>{i + 1}</td>
                    <td><Link to={`/games/${g.game_id}/`} className="cf-rowlink"><span className="cf-small cf-muted">{kickoffText(g, true)}</span></Link></td>
                    <td><Matchup g={g} /></td>
                    <td style={C}><Quality value={q} /></td>
                    <td className="cf-num" style={C}>{g.status === 'final' ? `${g.away_points}–${g.home_points}` : 'Upcoming'}</td>
                  </tr>)}</tbody>
                </table></td></tr>}
            </Fragment> })}</tbody>
          </table></div>
          <p className="cf-small cf-muted" style={{ marginTop: 8 }}>Weekly Rating is the average Game Quality of the week’s {TOP_N} best games (all of them if there are fewer). Finished games are scored on the ratings published before that week, so a week’s score reflects how good it looked going in. Games still to come use the current ratings and will shift as ratings update.{pending ? ' Loading pre-game ratings for finished weeks…' : ''}</p>
        </section>
        <section className="cf-section" aria-labelledby="gq-best">
          <div className="cf-panel-head"><h2 id="gq-best">Best Games of the Year</h2></div>
          <div className="cf-table-wrap"><table className="cf-table" style={{ tableLayout: 'fixed' }}>
            <caption className="cf-sr">Highest Game Quality games this season</caption>
            <colgroup><col style={{ width: 168 }} /><col /><col style={{ width: 130 }} /><col style={{ width: 130 }} /></colgroup>
            <thead><tr><th scope="col" className="cf-th-start">Kickoff</th><th scope="col" style={C}>Matchup</th><th scope="col" style={C}>Game Quality</th><th scope="col" style={C}>Status</th></tr></thead>
            <tbody>{best.map(({ g, q }) => <tr key={g.game_id} className="cf-row-link">
              <td><Link to={`/games/${g.game_id}/`} className="cf-rowlink"><span style={{ display: 'block', fontWeight: 500 }}>Week {g.week}</span><span className="cf-small cf-muted">{kickoffText(g, true)}</span></Link></td>
              <td><Matchup g={g} /></td>
              <td style={C}><Quality value={q} /></td>
              <td className="cf-num" style={C}>{g.status === 'final' ? `${g.away_points}–${g.home_points}` : 'Upcoming'}</td>
            </tr>)}</tbody>
          </table></div>
        </section>
      </>
    }}</DataGate>
  </>
}
