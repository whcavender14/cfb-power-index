// Conference comparison chart on the Conferences page, drawn as native SVG so it uses the page's type, follows the
// theme and animates like the rating-history chart (lines draw left to right, logos settle in as the line passes).
// The downloadable PNG is still drawn by confChart.ts. Colours are per conference (stable while you toggle others).
import { useLayoutEffect, useRef, useState } from 'react'
import type { Conference, TeamMeta, TeamRow } from './data'

import { conferenceColors } from './confColors'
/** A conference's line colour: its own brand colour, or its alternate where two would be confused (see confColors.ts). */
export const confColor = (slug: string, dark: boolean) => conferenceColors(dark)[slug] ?? '#4a5568'

export type ChartPoint = { id: string; x: number; y: number; size: number }
export type ChartLayout = { W: number; H: number; points: ChartPoint[]; plot: { x0: number; x1: number; y0: number; y1: number }
  series: { c: Conference; color: string; pts: { id: string; x: number; y: number }[] }[]; yTicks: number[]; maxN: number; narrow: boolean; size: number; Y: (v: number) => number }

export function useElementWidth<T extends HTMLElement>() {
  const ref = useRef<T>(null)
  const [w, setW] = useState(0)
  useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    setW(Math.round(el.getBoundingClientRect().width))
    const ro = new ResizeObserver(([e]) => setW(Math.round(e.contentRect.width)))
    ro.observe(el)
    return () => ro.disconnect()
  }, [])
  return [ref, w] as const
}

export function layoutChart(W: number, chosen: Conference[], rows: TeamRow[], dark: boolean): ChartLayout {
  const power = new Map(rows.filter(r => r.power != null).map(r => [r.team_id, r.power!]))
  const narrow = W < 560
  const H = narrow ? 360 : Math.round(Math.min(560, Math.max(430, W * 0.46)))
  const pad = { l: narrow ? 34 : 46, r: narrow ? 8 : 14, t: 14, b: narrow ? 40 : 50 }
  const colors = conferenceColors(dark)
  const teams = chosen.map(c => ({ c, color: colors[c.slug] ?? '#4a5568', ids: c.team_ids.filter(id => power.has(id)).sort((a, b) => power.get(b)! - power.get(a)!) }))
  const vals = teams.flatMap(s => s.ids.map(id => power.get(id)!))
  const lo = Math.floor(Math.min(...vals, 0) / 5) * 5 - 5, hi = Math.ceil(Math.max(...vals, 0) / 5) * 5 + 5
  const maxN = Math.max(...teams.map(s => s.ids.length), 1)
  const size = narrow ? 18 : teams.length > 6 ? 22 : 26
  const x0 = pad.l, x1 = W - pad.r, y0 = pad.t, y1 = H - pad.b
  const X = (rank: number) => x0 + size / 2 + 6 + (rank - 1) / Math.max(1, maxN - 1) * (x1 - x0 - size - 12)
  const Y = (v: number) => y1 - (v - lo) / (hi - lo) * (y1 - y0)
  const step = narrow ? 10 : 5
  const yTicks: number[] = []; for (let v = Math.ceil(lo / step) * step; v <= hi; v += step) yTicks.push(v)
  const series = teams.map(s => ({ c: s.c, color: s.color, pts: s.ids.map((id, i) => ({ id, x: X(i + 1), y: Y(power.get(id)!) })) }))
  return { W, H, points: series.flatMap(s => s.pts.map(p => ({ ...p, size }))), plot: { x0, x1, y0, y1 }, series, yTicks, maxN, narrow, size, Y }
}

/** Compact toggle labels so all eleven fit on one bar below ~1100px. */
const SHORT: Record<string, string> = { 'American Athletic': 'AAC', 'Conference USA': 'C-USA', 'Mid-American': 'MAC', 'Mountain West': 'MWC', 'FBS Independents': 'Ind.' }
export const confShort = (c: Conference) => c.is_conference ? SHORT[c.name] ?? c.name : 'Ind.'

const signed = (v: number) => v > 0 ? `+${v}` : v < 0 ? `−${-v}` : '0'

/** `hits`: team ids matching the chart's team finder (null = no search). Everything else dims; hits pop with a ring. */
export function ConferenceSvg({ L, dir, hits }: { L: ChartLayout; dir: Map<string, TeamMeta>; hits: Set<string> | null }) {
  const { W, H, plot, series, yTicks, maxN, narrow, size, Y } = L
  const hitsKey = hits ? [...hits].join(',') : ''
  const every = narrow ? (maxN > 14 ? 4 : 2) : maxN > 20 ? 2 : 1
  const label = `Line chart of CFPi+ power rating by rank within each selected conference: ${series.map(s => s.c.is_conference ? s.c.name : 'Independents').join(', ')}.`
  return <svg width={W} height={H} role="img" aria-label={label} className="cf-cc-svg">
    {yTicks.map(t => <g key={t}>
      <line x1={plot.x0} x2={plot.x1} y1={Y(t)} y2={Y(t)} className={t === 0 ? 'cf-hist-zero' : 'cf-hist-grid'} />
      <text x={plot.x0 - 8} y={Y(t)} dy="0.32em" textAnchor="end" className="cf-hist-tick">{signed(t)}</text>
    </g>)}
    {Array.from({ length: maxN }, (_, i) => i + 1).filter(r => r === 1 || r % every === 0).map(r => {
      const x = series.find(s => s.pts[r - 1])?.pts[r - 1]?.x ?? plot.x0 + (r - 1) / Math.max(1, maxN - 1) * (plot.x1 - plot.x0)
      return <text key={r} x={x} y={plot.y1 + 20} textAnchor="middle" className="cf-hist-tick">{r}</text>
    })}
    <text x={(plot.x0 + plot.x1) / 2} y={H - 8} textAnchor="middle" className="cf-cc-axis">Rank within conference</text>
    <text transform={`translate(12 ${(plot.y0 + plot.y1) / 2}) rotate(-90)`} textAnchor="middle" className="cf-cc-axis">CFPi+ power rating</text>
    {series.filter(s => s.c.is_conference && s.pts.length > 1).map(s =>
      <path key={s.c.slug} pathLength={1} className="cf-hist-line" style={{ stroke: s.color, strokeWidth: 2.5, opacity: hits ? 0.25 : 1 }}
        d={s.pts.map((p, i) => `${i ? 'L' : 'M'}${p.x.toFixed(1)},${p.y.toFixed(1)}`).join('')} />)}
    {series.flatMap(s => s.pts).sort((a, b) => Number(hits?.has(a.id) ?? false) - Number(hits?.has(b.id) ?? false)).map(p => {
      const t = dir.get(p.id), frac = (p.x - plot.x0) / Math.max(1, plot.x1 - plot.x0), hit = !!hits?.has(p.id)
      const few = hits !== null && hits.size <= 4
      return <g key={p.id}>
        {hit && <>
          <circle key={`ping-${hitsKey}`} className="cf-cc-ping" cx={p.x} cy={p.y} r={size * 0.95} />
          <circle className="cf-cc-halo" cx={p.x} cy={p.y} r={size * 0.95} />
        </>}
        <image className={`cf-hist-dot${hits ? (hit ? ' is-hit' : ' is-dim') : ''}`} href={`${import.meta.env.BASE_URL}logos/sm/${p.id}.png`} width={size} height={size} x={p.x - size / 2} y={p.y - size / 2}
          preserveAspectRatio="xMidYMid meet" aria-label={t?.team} style={{ animationDelay: `${200 + Math.round(frac * 900)}ms` }} />
        {hit && few && t && <text className="cf-cc-hitlabel" x={p.x + (p.x > W - 150 ? -size : size)} y={p.y - size} textAnchor={p.x > W - 150 ? 'end' : 'start'}>{t.team}</text>}
      </g>
    })}
  </svg>
}
