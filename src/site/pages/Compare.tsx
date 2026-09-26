import ShareButton from '../ShareButton'
import { useRef } from 'react'
import { X } from 'lucide-react'
import { DataGate, Freshness, PageHead, Select, TeamLogo, useData, useTeams } from '../components'
import type { HistoryDoc, HistoryPoint } from '../data'
import HistoryChart, { HistoryTable, type ChartSeries } from '../HistoryChart'
import { useQueryParam } from '../router'

const MAX = 5

/** Explains where each point comes from; shown wherever the history chart appears. */
export function HistoryNote({ points }: { points: HistoryPoint[] }) {
  const rec = points.filter(p => p.source === 'reconstructed').map(p => p.week)
  const pub = points.filter(p => p.source === 'published').map(p => p.week)
  return <p className="cf-note">
    {points.some(p => p.source === 'preseason') && <>Preseason is the model’s rating before any games. </>}
    {pub.length > 0 && <>Week {pub.join(', ')}: ratings as published. </>}
    {rec.length > 0 && <>Week {rec.join(', ')} (hollow points): CFPi+ was not yet the published model, so these are reconstructions: the unchanged model re-run at each week’s cutoff on the data it used. Re-running the published week this way reproduces it exactly. </>}
    Missing weeks are left blank, never filled in.
  </p>
}

export default function Compare() {
  const history = useData<HistoryDoc>('history.json')
  const directory = useTeams()
  const [param, setParam] = useQueryParam('teams')
  const slots = useRef(new Map<string, number>())
  const bySlug = new Map([...directory.values()].map(t => [t.slug, t]))
  return <>
    <PageHead title="Rating history" lede="How CFPi+ ratings have moved this season. Compare up to five teams; the link to this page keeps your selection." />
    <DataGate source={history} label="Rating history">{doc => {
      const ranked = Object.entries(doc.teams).filter(([, s]) => s.rank[s.rank.length - 1] != null).sort((a, b) => a[1].rank[a[1].rank.length - 1]! - b[1].rank[b[1].rank.length - 1]!)
      const requested = param.split(',').map(s => s.trim()).filter(s => bySlug.has(s))
      const chosen = [...new Set(requested)].slice(0, MAX)
      const shown = chosen.length ? chosen : ranked.slice(0, 3).map(([id]) => directory.get(id)?.slug).filter(Boolean) as string[]
      // Colour follows the team: a team keeps its colour slot while it stays selected.
      for (const k of [...slots.current.keys()]) if (!shown.includes(k)) slots.current.delete(k)
      for (const s of shown) if (!slots.current.has(s)) { let n = 1; while ([...slots.current.values()].includes(n)) n++; slots.current.set(s, n) }
      const series: ChartSeries[] = shown.map(slug => {
        const t = bySlug.get(slug)!
        const h = doc.teams[t.team_id]
        return { id: t.team_id, name: t.team, slot: slots.current.get(slug)!, power: h?.power ?? [], rank: h?.rank ?? [] }
      })
      const set = (list: string[]) => setParam(list.join(','))
      const options = [...directory.values()].filter(t => !shown.includes(t.slug)).sort((a, b) => a.team.localeCompare(b.team))
      return <>
        <div className="cf-subbar"><Freshness meta={doc.meta} /><ShareButton run={async () => (await import('../graphics')).comparePng(doc.meta, doc, series, directory)} /></div>
        <div className="cf-toolbar cf-compare-bar">
          <ul className="cf-chips" aria-label="Teams in the chart">
            {series.map(s => <li key={s.id} className="cf-chip">
              <span className={`cf-series-${s.slot} cf-hist-key`} aria-hidden="true">●</span>
              <TeamLogo id={s.id} name={s.name} size={18} />{s.name}
              {shown.length > 1 && <button type="button" aria-label={`Remove ${s.name}`} onClick={() => set(shown.filter(x => bySlug.get(x)?.team_id !== s.id))}><X size={13} /></button>}
            </li>)}
          </ul>
          {shown.length < MAX
            ? <Select label="Add a team" value="" onChange={v => v && set([...shown, v])}>
                <option value="">Choose…</option>
                {options.map(t => <option key={t.slug} value={t.slug}>{t.team}</option>)}
              </Select>
            : <p className="cf-muted cf-small">Five teams is the maximum. Remove one to add another.</p>}
        </div>
        <section className="cf-panel">
          <HistoryChart points={doc.points} series={series} label={`CFPi+ rating by week for ${series.map(s => s.name).join(', ')}`} />
          <HistoryNote points={doc.points} />
          <details className="cf-details"><summary>Show as a table</summary><HistoryTable points={doc.points} series={series} /></details>
        </section>
      </>
    }}</DataGate>
  </>
}
