import type { Rating, Team } from './data'
import { downloadBlob } from './download'
import { initials } from './ui'

// Renders the full ranking as a shareable four-column graphic (3200px wide at 2x).
//
// Logos: the CollegeFootballData CDN sends no CORS headers, so its images can be shown
// in <img> but neither fetch() nor an untainted canvas may read them. The build mirrors
// them to /logos/<team_id>.png (scripts/sync_logos.mjs); those same-origin files are read
// as data URLs and decoded before drawing. The CDN is tried last in case it ever enables
// CORS; a team whose logo cannot be read gets a monogram so the export never fails.
type Options = { teams: Rating[]; season: number; week: number | null; updatedAt: string | null }
export type ExportResult = { logos: number; total: number }

export const C = {
  bg: '#f7f4ec', card: '#fffdf8', stripe: '#faf6ee', ink: '#1a1c20', ink2: '#474b53', muted: '#6a6e76',
  line: '#e6dfd1', faint: '#9c9a93', navy: '#1c2f55', navyLine: '#c5cfe0', navyDeep: '#14223f', navySoft: '#e8ecf4', cream: '#f7f4ec',
  gold: '#b8893a', goldInk: '#8b6520', goldSoft: '#f3e9d4', pos: '#2f6f4e', neg: '#a4433b',
}
export const DISPLAY = '"Inter Tight", Inter, system-ui, sans-serif'
export const BODY = 'Inter, system-ui, sans-serif'
export const MONO = '"JetBrains Mono", ui-monospace, Menlo, monospace'
const FONTS = [`800 50px ${DISPLAY}`, `700 16px ${DISPLAY}`, `500 14.5px ${BODY}`, `italic 400 13px ${BODY}`, `500 12px ${MONO}`, `600 14.5px ${MONO}`]

async function readAsDataUrl(url: string): Promise<string | null> {
  try {
    const response = await fetch(url, { mode: 'cors', signal: AbortSignal.timeout(10000) })
    // Vite and some static hosts answer missing files with index.html; require an image.
    if (!response.ok) return null
    const blob = await response.blob()
    if (!blob.type.startsWith('image/')) return null
    return await new Promise<string>((resolve, reject) => {
      const reader = new FileReader()
      reader.onload = () => resolve(reader.result as string)
      reader.onerror = () => reject(reader.error)
      reader.readAsDataURL(blob)
    })
  } catch {
    return null
  }
}

export async function loadLogos(teams: Pick<Team, 'team_id' | 'logo_url'>[]): Promise<Map<string, HTMLImageElement>> {
  const logos = new Map<string, HTMLImageElement>()
  await Promise.all(teams.map(async team => {
    for (const url of [`${import.meta.env.BASE_URL}logos/${encodeURIComponent(team.team_id)}.png`, team.logo_url]) {
      if (!url) continue
      const data = await readAsDataUrl(url)
      if (!data) continue
      const image = new Image()
      // The load event, not decode(): decode() can stay pending in a hidden page, which would block the export.
      const ok = await new Promise<boolean>(resolve => {
        image.onload = () => resolve(image.naturalWidth > 0)
        image.onerror = () => resolve(false)
        setTimeout(() => resolve(image.complete && image.naturalWidth > 0), 5000)
        image.src = data
      })
      if (ok) { logos.set(team.team_id, image); return }
    }
  }))
  return logos
}

export function fit(ctx: CanvasRenderingContext2D, text: string, max: number) {
  if (ctx.measureText(text).width <= max) return text
  let out = text
  while (out.length > 1 && ctx.measureText(`${out}…`).width > max) out = out.slice(0, -1)
  return `${out.trimEnd()}…`
}
function fmt(value: number, sign: boolean) {
  const rounded = Math.round(value * 10) / 10
  const clean = Object.is(rounded, -0) ? 0 : rounded
  return `${sign && clean > 0 ? '+' : ''}${clean.toFixed(1).replace('-', '−')}`
}
export function spacing(ctx: CanvasRenderingContext2D, value: string) {
  if ('letterSpacing' in ctx) (ctx as CanvasRenderingContext2D & { letterSpacing: string }).letterSpacing = value
}
export function rounded(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number | number[]) {
  ctx.beginPath()
  if (typeof ctx.roundRect === 'function') ctx.roundRect(x, y, w, h, r)
  else ctx.rect(x, y, w, h)
}
/** A bordered label chip; returns its width so chips can be laid out right-to-left. */
export function tag(ctx: CanvasRenderingContext2D, text: string, right: number, y: number, fill: string, stroke: string, ink: string) {
  spacing(ctx, '1.5px')
  ctx.font = `600 12px ${MONO}`
  const w = ctx.measureText(text).width + 24
  rounded(ctx, right - w, y, w, 28, 4)
  ctx.fillStyle = fill
  ctx.fill()
  ctx.strokeStyle = stroke
  ctx.lineWidth = 1
  ctx.stroke()
  ctx.fillStyle = ink
  ctx.textAlign = 'left'
  ctx.fillText(text, right - w + 12, y + 18.5)
  spacing(ctx, '0px')
  return w
}

// ── Shared canvas helpers (also used by exportPlayoff.ts) ──────────────────
/** Waits for every face used on the canvas, then for any still-pending font work. */
export async function loadFonts() {
  try { await Promise.all(FONTS.map(font => document.fonts.load(font))) } catch { /* system fallback */ }
  await document.fonts.ready
}
/** A 2x canvas in logical pixels, pre-filled with the page background. */
export function createCanvas(W: number, H: number) {
  const scale = 2
  const canvas = document.createElement('canvas')
  canvas.width = W * scale
  canvas.height = H * scale
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('Canvas unavailable')
  ctx.scale(scale, scale)
  ctx.imageSmoothingEnabled = true
  ctx.imageSmoothingQuality = 'high'
  ctx.textBaseline = 'alphabetic'
  ctx.fillStyle = C.bg
  ctx.fillRect(0, 0, W, H)
  return { canvas, ctx }
}
export async function savePng(canvas: HTMLCanvasElement, filename: string) {
  const blob = await new Promise<Blob | null>(resolve => canvas.toBlob(resolve, 'image/png'))
  if (!blob) throw new Error('Image export failed')
  downloadBlob(blob, filename)
}
/** A logo fitted inside a square box centred on (cx, cy), or a monogram disc. */
export function drawLogo(ctx: CanvasRenderingContext2D, logo: HTMLImageElement | undefined, name: string, cx: number, cy: number, box: number) {
  if (logo) {
    const s = Math.min(box / logo.naturalWidth, box / logo.naturalHeight)
    const w = logo.naturalWidth * s, h = logo.naturalHeight * s
    ctx.drawImage(logo, cx - w / 2, cy - h / 2, w, h)
    return
  }
  const r = box * 0.46
  ctx.beginPath()
  ctx.arc(cx, cy, r, 0, Math.PI * 2)
  ctx.fillStyle = C.navySoft
  ctx.fill()
  ctx.font = `600 ${Math.round(r * 0.78 * 10) / 10}px ${MONO}`
  ctx.fillStyle = C.navy
  ctx.textAlign = 'center'
  ctx.fillText(initials(name), cx, cy + r * 0.28)
}
/** Brand mark, kicker, wordmark-sized title, right-aligned chips and the navy/gold rule. */
export function drawMasthead(ctx: CanvasRenderingContext2D, W: number, pad: number, { kicker, title, chips, updatedAt }: { kicker: string; title: string; chips: [string, string]; updatedAt: string | null }) {
  rounded(ctx, pad, 52, 58, 58, 8)
  ctx.fillStyle = C.navy
  ctx.fill()
  ctx.fillStyle = C.gold
  ctx.fillRect(pad + 14, 96, 30, 3)
  ctx.fillStyle = C.cream
  ctx.font = `800 22px ${DISPLAY}`
  ctx.textAlign = 'center'
  ctx.fillText('PI', pad + 29, 89)
  ctx.textAlign = 'left'
  spacing(ctx, '2.5px')
  ctx.font = `600 12.5px ${MONO}`
  ctx.fillStyle = C.goldInk
  ctx.fillText(kicker, pad + 78, 68)
  spacing(ctx, '-1.2px')
  ctx.font = `800 50px ${DISPLAY}`
  ctx.fillStyle = C.ink
  ctx.fillText(title, pad + 76, 112)
  spacing(ctx, '0px')
  let right = W - pad
  right -= tag(ctx, chips[0], right, 58, C.navy, C.navy, C.cream) + 10
  tag(ctx, chips[1], right, 58, C.goldSoft, '#dcc491', C.goldInk)
  const updated = updatedAt ? new Date(updatedAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' }).toUpperCase() : 'UNAVAILABLE'
  spacing(ctx, '1.5px')
  ctx.font = `500 12px ${MONO}`
  ctx.fillStyle = C.muted
  ctx.textAlign = 'right'
  ctx.fillText(`UPDATED ${updated}`, W - pad, 112)
  ctx.textAlign = 'left'
  spacing(ctx, '0px')
  ctx.fillStyle = C.navy
  ctx.fillRect(pad, 144, W - pad * 2, 2)
  ctx.fillStyle = C.gold
  ctx.fillRect(pad, 150, 96, 2)

}
/** Right-aligned "CFPi+" signature with its gold underline. */
export function drawFooterBrand(ctx: CanvasRenderingContext2D, right: number, baseline: number) {
  ctx.textAlign = 'right'
  ctx.font = `700 16px ${DISPLAY}`
  ctx.fillStyle = C.navy
  ctx.fillText('CFPi+', right, baseline)
  ctx.fillStyle = C.gold
  ctx.fillRect(right - 24, baseline + 8, 24, 2)
  ctx.textAlign = 'left'
}

export async function exportRankingsPng({ teams, season, week, updatedAt }: Options): Promise<ExportResult> {
  await loadFonts()
  const logos = await loadLogos(teams)

  const weekly = teams.some(t => t.weekly_change !== null)
  const W = 1600, pad = 56, gap = 20, cols = 4, top = 196, headH = 36, rowH = 34
  const perCol = Math.ceil(teams.length / cols)
  const colW = (W - pad * 2 - gap * (cols - 1)) / cols
  const tableBottom = top + headH + perCol * rowH
  const H = tableBottom + 102
  const { canvas, ctx } = createCanvas(W, H)

  drawMasthead(ctx, W, pad, { kicker: 'COLLEGE FOOTBALL · POWER RATINGS', title: 'CFPi+ Power Ratings', chips: [`${week == null ? 'LATEST' : `WEEK ${week}`} · ${season}`, `ALL ${teams.length} FBS`], updatedAt })

  // Ranking columns
  for (let c = 0; c < cols; c++) {
    const x0 = pad + c * (colW + gap)
    const slice = teams.slice(c * perCol, (c + 1) * perCol)
    if (!slice.length) continue
    const colH = headH + slice.length * rowH
    ctx.save()
    ctx.shadowColor = 'rgba(28, 47, 85, 0.10)'
    ctx.shadowBlur = 14
    ctx.shadowOffsetY = 4
    rounded(ctx, x0, top, colW, colH, 6)
    ctx.fillStyle = C.card
    ctx.fill()
    ctx.restore()
    ctx.save()
    rounded(ctx, x0, top, colW, colH, 6)
    ctx.clip()
    ctx.fillStyle = C.navyDeep
    ctx.fillRect(x0, top, colW, headH)
    ctx.fillStyle = C.gold
    ctx.fillRect(x0, top + headH - 2, colW, 2)
    ctx.fillStyle = C.cream
    spacing(ctx, '1.6px')
    ctx.font = `600 10.5px ${MONO}`
    ctx.fillText('RK', x0 + 14, top + 22)
    ctx.fillText('TEAM', x0 + 80, top + 22)
    ctx.textAlign = 'right'
    ctx.fillText(weekly ? 'Δ WK' : 'Δ PRE', x0 + colW - 84, top + 22)
    ctx.fillText('PWR', x0 + colW - 14, top + 22)
    ctx.textAlign = 'left'
    spacing(ctx, '0px')

    slice.forEach((team, j) => {
      const rank = c * perCol + j + 1
      const y = top + headH + j * rowH
      const mid = y + rowH / 2
      if (j % 2 === 1) { ctx.fillStyle = C.stripe; ctx.fillRect(x0, y, colW, rowH) }
      if (j < slice.length - 1) { ctx.fillStyle = C.line; ctx.fillRect(x0 + 12, y + rowH - 1, colW - 24, 1) }
      const base = y + 22
      if (rank <= 3) {
        rounded(ctx, x0 + 9, mid - 10, 26, 20, 3)
        ctx.fillStyle = C.goldSoft
        ctx.fill()
      }
      ctx.font = `${rank <= 3 ? 600 : 500} 12.5px ${MONO}`
      ctx.fillStyle = rank <= 3 ? C.goldInk : C.muted
      ctx.textAlign = 'center'
      ctx.fillText(String(rank).padStart(2, '0'), x0 + 22, base)

      const logo = logos.get(team.team_id)
      const box = 24, lx = x0 + 60
      if (logo) {
        const s = Math.min(box / logo.naturalWidth, box / logo.naturalHeight)
        const w = logo.naturalWidth * s, h = logo.naturalHeight * s
        ctx.drawImage(logo, lx - w / 2, mid - h / 2, w, h)
      } else {
        ctx.beginPath()
        ctx.arc(lx, mid, 11, 0, Math.PI * 2)
        ctx.fillStyle = C.navySoft
        ctx.fill()
        ctx.font = `600 8.5px ${MONO}`
        ctx.fillStyle = C.navy
        ctx.fillText(initials(team.team), lx, mid + 3)
      }
      ctx.textAlign = 'left'
      ctx.font = `500 14.5px ${BODY}`
      ctx.fillStyle = C.ink
      ctx.fillText(fit(ctx, team.team, colW - 80 - 140), x0 + 80, base)

      const delta = weekly ? team.weekly_change : team.preseason_change
      const flat = delta === null || Math.abs(delta) < 0.05
      ctx.textAlign = 'right'
      ctx.font = `500 12px ${MONO}`
      ctx.fillStyle = flat ? C.muted : delta! > 0 ? C.pos : C.neg
      const deltaText = delta === null ? '—' : fmt(delta, true)
      ctx.fillText(deltaText, x0 + colW - 84, base)
      if (!flat) {
        const tx = x0 + colW - 84 - ctx.measureText(deltaText).width - 9
        ctx.beginPath()
        if (delta! > 0) { ctx.moveTo(tx - 4, mid + 3); ctx.lineTo(tx + 4, mid + 3); ctx.lineTo(tx, mid - 3) }
        else { ctx.moveTo(tx - 4, mid - 3); ctx.lineTo(tx + 4, mid - 3); ctx.lineTo(tx, mid + 3) }
        ctx.fill()
      }
      ctx.font = `600 14.5px ${MONO}`
      ctx.fillStyle = C.ink
      ctx.fillText(team.power_rating === null ? '—' : fmt(team.power_rating, false), x0 + colW - 14, base)
      ctx.textAlign = 'left'
    })
    ctx.restore()
    rounded(ctx, x0 + 0.5, top + 0.5, colW - 1, colH - 1, 6)
    ctx.strokeStyle = C.line
    ctx.lineWidth = 1
    ctx.stroke()
  }

  // Footer
  ctx.fillStyle = C.line
  ctx.fillRect(pad, tableBottom + 34, W - pad * 2, 1)
  ctx.font = `italic 400 13px ${BODY}`
  ctx.fillStyle = C.muted
  ctx.fillText(`PWR: opponent-adjusted team strength in points relative to an average FBS team (offense − defense). Δ: change in power rating since ${weekly ? 'the previous week' : 'the preseason baseline'}.`, pad, tableBottom + 68)
  drawFooterBrand(ctx, W - pad, tableBottom + 68)
  await savePng(canvas, `cfb-power-index-${season}-${week == null ? 'latest' : `week-${String(week).padStart(2, '0')}`}.png`)
  return { logos: logos.size, total: teams.length }
}
