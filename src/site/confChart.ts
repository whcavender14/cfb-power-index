// Conference comparison graphic: each conference is a line of its teams' CFPi+ power ratings, ranked within the
// conference (rank 1 on the left), with every team's logo on its point. Shown on the Conferences page and downloadable.
// Inspired by @StatsoWar's conference comparison graphics.
import { createCanvas } from '../exportImage'
import type { Conference, Meta, TeamMeta, TeamRow } from './data'
import { logo, logosFor, stamp, text } from './share'

export const CONF_COLORS = ['#5aa5eb', '#0b1b33', '#d4a017', '#1d7a3a', '#c0362c', '#7a5ab8', '#e07b39', '#2a9d8f', '#8d6e63', '#b0397a', '#4b5563']
const INK = '#0b1b33', MUTE = '#5f6d82', LINE = '#dbe3ee', BG = '#f2f5f9'

async function brandImage(): Promise<HTMLImageElement | null> {
  const img = new Image()
  return new Promise(resolve => { img.onload = () => resolve(img.naturalWidth > 0 ? img : null); img.onerror = () => resolve(null); img.src = `${import.meta.env.BASE_URL}brand/logo-on-light.png` })
}

export type ChartPoint = { id: string; x: number; y: number; size: number }
export async function conferenceChart(meta: Meta, rows: TeamRow[], confs: Conference[], dir: Map<string, TeamMeta>) {
  const power = new Map(rows.filter(r => r.power != null).map(r => [r.team_id, r.power!]))
  const series = confs.map((c, i) => ({ c, color: CONF_COLORS[i % CONF_COLORS.length],
    teams: c.team_ids.filter(id => power.has(id)).sort((a, b) => power.get(b)! - power.get(a)!) }))
  const logos = await logosFor(series.flatMap(s => s.teams), dir)
  const brand = await brandImage()
  const W = 1600, H = 940, L = 92, R = 48, B = 96
  const LFONT = '600 14px -apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, system-ui, sans-serif'
  const scratch = document.createElement('canvas').getContext('2d')!
  scratch.font = LFONT
  let legendRows = 1, run = 40
  for (const s of series) { const w = 30 + scratch.measureText(s.c.is_conference ? s.c.name : 'Independents').width + 22; if (run + w > W - 40) { legendRows++; run = 40 } run += w }
  const T = 176 + (legendRows - 1) * 26
  const { canvas, ctx } = createCanvas(W, H)
  try { await document.fonts.ready } catch { /* system font */ }
  ctx.fillStyle = BG; ctx.fillRect(0, 0, W, H)

  // Header: logo, title, subtitle
  if (brand) { const h = 72; ctx.imageSmoothingQuality = 'high'; ctx.drawImage(brand, 40, 24, brand.naturalWidth * h / brand.naturalHeight, h) }
  text(ctx, 'Conference Power Comparison', W - 40, 62, { size: 40, weight: 700, color: INK, align: 'right', track: '-0.8px' })
  text(ctx, stamp(meta), W - 40, 92, { size: 16, color: MUTE, align: 'right' })

  // Legend (wraps onto extra rows when many conferences are shown)
  ctx.font = LFONT
  const items = series.map(s => { const name = s.c.is_conference ? s.c.name : 'Independents'; return { s, name, w: 30 + ctx.measureText(name).width + 22 } })
  let lx = 40, ly = 140
  for (const it of items) {
    if (lx + it.w > W - 40) { lx = 40; ly += 26 }
    ctx.fillStyle = it.s.color; ctx.beginPath(); if (it.s.c.is_conference) ctx.roundRect(lx, ly - 5, 22, 6, 3); else ctx.arc(lx + 11, ly - 2, 4, 0, Math.PI * 2); ctx.fill()
    text(ctx, it.name, lx + 30, ly + 2, { size: 14, weight: 600, color: INK })
    lx += it.w
  }

  // Scales
  const vals = series.flatMap(s => s.teams.map(id => power.get(id)!))
  const lo = Math.floor(Math.min(...vals, 0) / 5) * 5 - 5, hi = Math.ceil(Math.max(...vals, 0) / 5) * 5 + 5
  const maxN = Math.max(...series.map(s => s.teams.length), 1)
  const x0 = L, x1 = W - R, y0 = T, y1 = H - B
  const X = (rank: number) => x0 + 34 + (rank - 1) / Math.max(1, maxN - 1) * (x1 - x0 - 68)
  const Y = (v: number) => y1 - (v - lo) / (hi - lo) * (y1 - y0)
  ctx.font = '500 14px -apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, system-ui, sans-serif'
  for (let v = lo; v <= hi; v += 5) {
    ctx.strokeStyle = v === 0 ? '#aab6c8' : LINE; ctx.lineWidth = v === 0 ? 1.5 : 1
    ctx.beginPath(); ctx.moveTo(x0, Y(v)); ctx.lineTo(x1, Y(v)); ctx.stroke()
    text(ctx, v > 0 ? `+${v}` : v < 0 ? `−${-v}` : '0', x0 - 12, Y(v) + 5, { size: 14, color: MUTE, align: 'right' })
  }
  for (let r = 1; r <= maxN; r++) text(ctx, String(r), X(r), y1 + 26, { size: 14, color: MUTE, align: 'center' })
  text(ctx, 'RANK WITHIN CONFERENCE', (x0 + x1) / 2, y1 + 56, { size: 12, weight: 600, color: INK, align: 'center', track: '2.4px' })
  ctx.save(); ctx.translate(26, (y0 + y1) / 2); ctx.rotate(-Math.PI / 2)
  text(ctx, 'CFPi+ POWER RATING', 0, 0, { size: 12, weight: 600, color: INK, align: 'center', track: '2.4px' }); ctx.restore()

  // Lines, then logos on top
  for (const s of series.filter(x => x.c.is_conference)) {   // independents are separate programs: logo points only, no line
    ctx.strokeStyle = s.color; ctx.lineWidth = 3.5; ctx.lineJoin = 'round'; ctx.globalAlpha = 0.9
    ctx.beginPath(); s.teams.forEach((id, i) => { const x = X(i + 1), y = Y(power.get(id)!); i ? ctx.lineTo(x, y) : ctx.moveTo(x, y) }); ctx.stroke()
    ctx.globalAlpha = 1
  }
  const size = series.length > 6 ? 26 : series.length > 4 ? 30 : 34
  const points: ChartPoint[] = []
  for (const s of series) s.teams.forEach((id, i) => { const x = X(i + 1), y = Y(power.get(id)!); logo(ctx, logos, id, dir.get(id)?.team ?? id, x, y, size); points.push({ id, x, y, size }) })

  // Footer
  text(ctx, 'Inspired by @StatsoWar', 40, H - 22, { size: 14, weight: 600, color: MUTE })
  text(ctx, 'CFPi+ · Cavender Football Power Index', W - 40, H - 22, { size: 12, color: MUTE, align: 'right', track: '0.4px' })
  return { canvas, W, H, points }
}
export async function conferenceChartCanvas(meta: Meta, rows: TeamRow[], confs: Conference[], dir: Map<string, TeamMeta>) {
  return (await conferenceChart(meta, rows, confs, dir)).canvas
}
