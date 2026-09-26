// Shareable PNG graphics, drawn client-side from data the page has already loaded.
// Every value is taken as-is from the v2 datasets (the browser does not recompute ratings or odds).
import { createCanvas, fit, loadLogos, rounded, savePng } from '../exportImage'
import { initials } from '../ui'
import type { Meta, TeamMeta } from './data'
import { pctText } from './components'

const W = 1200, PAD = 48
const FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Display", "Inter", system-ui, "Segoe UI", Roboto, sans-serif'
const K = { bg: '#f5f5f7', card: '#ffffff', ink: '#1d1d1f', ink2: '#3a3a3c', muted: '#6e6e73', line: '#e5e5ea', fill: '#f2f2f7', accent: '#0066cc', up: '#1d7a3a', down: '#c0362c' }
export const SERIES = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4']

type Ctx = CanvasRenderingContext2D
export type Logos = Map<string, HTMLImageElement>

const minus = (s: string) => s.replace('-', '−')
export const signed = (v: number | null | undefined, d = 1) => v == null ? '—' : `${v > 0 ? '+' : ''}${minus((Math.round(v * 10 ** d) / 10 ** d).toFixed(d))}`
export const pct = (p: number | null | undefined) => pctText(p) ?? '—'

export function stamp(meta: Meta) {
  const wk = meta.ratings_week == null ? '' : meta.ratings_week === 0 ? 'Preseason' : `Ratings through Week ${meta.ratings_week}`
  const date = meta.ratings_updated_at ? new Date(meta.ratings_updated_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : ''
  return [wk, date && `Updated ${date}`].filter(Boolean).join(' · ')
}

export async function logosFor(ids: string[], dir: Map<string, TeamMeta>): Promise<Logos> {
  return loadLogos(ids.map(id => ({ team_id: id, logo_url: dir.get(id)?.logo ?? null })))
}

export function logo(ctx: Ctx, logos: Logos, id: string, name: string, cx: number, cy: number, box: number) {
  const img = logos.get(id)
  if (img) {
    const s = Math.min(box / img.naturalWidth, box / img.naturalHeight)
    ctx.drawImage(img, cx - (img.naturalWidth * s) / 2, cy - (img.naturalHeight * s) / 2, img.naturalWidth * s, img.naturalHeight * s)
    return
  }
  ctx.beginPath(); ctx.arc(cx, cy, box * 0.46, 0, Math.PI * 2); ctx.fillStyle = K.fill; ctx.fill()
  text(ctx, initials(name), cx, cy + box * 0.14, { size: box * 0.36, weight: 600, color: K.muted, align: 'center' })
}

export function text(ctx: Ctx, s: string, x: number, y: number, o: { size?: number; weight?: number; color?: string; align?: CanvasTextAlign; max?: number; track?: string } = {}) {
  ctx.font = `${o.weight ?? 400} ${o.size ?? 15}px ${FONT}`
  ctx.fillStyle = o.color ?? K.ink
  ctx.textAlign = o.align ?? 'left'
  if ('letterSpacing' in ctx) (ctx as Ctx & { letterSpacing: string }).letterSpacing = o.track ?? '0px'
  ctx.fillText(o.max ? fit(ctx, s, o.max) : s, x, y)
  if ('letterSpacing' in ctx) (ctx as Ctx & { letterSpacing: string }).letterSpacing = '0px'
}

/** A white card on the light page, with title, subtitle, stamp and the CFPi+ mark. Returns the content top. */
export function frame(ctx: Ctx, H: number, title: string, subtitle: string, meta: Meta) {
  ctx.fillStyle = K.bg; ctx.fillRect(0, 0, W, H)
  rounded(ctx, 24, 24, W - 48, H - 48, 20); ctx.fillStyle = K.card; ctx.fill()
  text(ctx, 'CFPi', PAD + 8, 84, { size: 22, weight: 700, track: '-0.4px' })
  ctx.font = `700 22px ${FONT}`; const w = ctx.measureText('CFPi').width
  text(ctx, '+', PAD + 8 + w + 1, 84, { size: 22, weight: 700, color: K.accent })
  text(ctx, stamp(meta), W - PAD - 8, 84, { size: 14, color: K.muted, align: 'right' })
  text(ctx, title, PAD + 8, 142, { size: 40, weight: 700, track: '-1px' })
  text(ctx, subtitle, PAD + 8, 176, { size: 17, color: K.muted, max: W - PAD * 2 - 16 })
  ctx.fillStyle = K.line; ctx.fillRect(PAD + 8, 200, W - PAD * 2 - 16, 1)
  text(ctx, 'CFPi+ · Cavender Football Power Index', PAD + 8, H - 52, { size: 13, color: K.muted })
  return 222
}

export type Col<R> = { label: string; w: number; align?: 'left' | 'right' | 'center'; draw: (ctx: Ctx, r: R, x: number, y: number, w: number) => void }

/** Table graphic: header row + fixed-height rows. Column widths are in px and must sum to the inner width. */
export function table<R>(ctx: Ctx, top: number, cols: Col<R>[], rows: R[], rowH = 44) {
  let x = PAD + 8
  for (const c of cols) {
    const ax = c.align === 'right' ? x + c.w - 8 : c.align === 'center' ? x + c.w / 2 : x
    text(ctx, c.label.toUpperCase(), ax, top + 14, { size: 11.5, weight: 600, color: K.muted, align: c.align ?? 'left', track: '0.6px' })
    x += c.w
  }
  rows.forEach((r, i) => {
    const y = top + 28 + i * rowH
    if (i % 2 === 0) { rounded(ctx, PAD, y, W - PAD * 2, rowH, 8); ctx.fillStyle = K.fill; ctx.fill() }
    let cx = PAD + 8
    for (const c of cols) { c.draw(ctx, r, cx, y + rowH / 2, c.w); cx += c.w }
  })
  return top + 28 + rows.length * rowH
}

export const cell = {
  num: (s: string, o: { weight?: number; color?: string } = {}) => (ctx: Ctx, x: number, y: number, w: number) => text(ctx, s, x + w - 8, y + 5.5, { size: 16, weight: o.weight ?? 500, color: o.color, align: 'right' }),
}
export function teamCell(ctx: Ctx, logos: Logos, id: string, name: string, sub: string | null, x: number, y: number, w: number) {
  logo(ctx, logos, id, name, x + 16, y, 28)
  text(ctx, name, x + 40, sub ? y - 1 : y + 5.5, { size: 16, weight: 600, max: w - 48 })
  if (sub) text(ctx, sub, x + 40, y + 16, { size: 12.5, color: K.muted, max: w - 48 })
}
export function move(ctx: Ctx, change: number | null, x: number, y: number, w: number) {
  if (change == null) return text(ctx, '—', x + w - 8, y + 5.5, { color: K.muted, align: 'right' })
  if (change === 0) return text(ctx, '0', x + w - 8, y + 5.5, { color: K.muted, align: 'right' })
  text(ctx, `${change > 0 ? '▲' : '▼'} ${Math.abs(change)}`, x + w - 8, y + 5.5, { size: 15, weight: 600, color: change > 0 ? K.up : K.down, align: 'right' })
}
export function bar(ctx: Ctx, p: number, x: number, y: number, w: number, color = K.accent) {
  rounded(ctx, x, y - 3, w, 6, 3); ctx.fillStyle = K.line; ctx.fill()
  if (p > 0) { rounded(ctx, x, y - 3, Math.max(w * p, 3), 6, 3); ctx.fillStyle = color; ctx.fill() }
}

export async function render(filename: string, H: number, draw: (ctx: Ctx) => void | Promise<void>) {
  const { canvas, ctx } = createCanvas(W, H)
  try { await document.fonts.ready } catch { /* system font */ }
  await draw(ctx)
  await savePng(canvas, filename)
}
export const WIDTH = W, INNER = W - PAD * 2 - 16, LEFT = PAD + 8, COLORS = K
