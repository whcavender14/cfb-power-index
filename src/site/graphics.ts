// The shareable graphics (the playoff bracket download is ./bracketPng.ts). Each takes data the page already loaded and returns when the PNG is saved.
import type { ChangesDoc, Game, Meta, PlayoffDoc, TeamMeta, TeamRow } from './data'
import { createCanvas, savePng } from '../exportImage'
import { bar, COLORS as K, frame, INNER, LEFT, logo, logosFor, move, pct, render, signed, stamp, table, teamCell, text, type Col } from './share'

type Dir = Map<string, TeamMeta>
const file = (meta: Meta, name: string) => `cfpi-${name}-${meta.season}-wk${String(meta.ratings_week ?? 0).padStart(2, '0')}.png`
const nm = (dir: Dir, id: string, fallback = '') => dir.get(id)?.team ?? fallback
const rec = (r: TeamRow) => r.wins == null ? '—' : `${r.wins}–${r.losses}`
const H = (rows: number, rowH = 44, extra = 0) => 222 + 28 + rows * rowH + 120 + extra

// ---- Square "poster" graphics for the Rankings page (ESPN-style: black band, blue rule, grid of team cards) ----
const EFONT = '"Helvetica Neue", Helvetica, "Arial Narrow", Arial, sans-serif'
const EINK = '#0b1b33', EMUTE = '#6b6b6b', EFAINT = '#9a9a9a', ELINE = '#dcdcdc', EBG = '#ececef'
function etext(ctx: CanvasRenderingContext2D, s: string, x: number, y: number, o: { size?: number; weight?: number; color?: string; align?: CanvasTextAlign; italic?: boolean; track?: string; max?: number } = {}) {
  ctx.font = `${o.italic ? 'italic ' : ''}${o.weight ?? 700} ${o.size ?? 14}px ${EFONT}`
  ctx.fillStyle = o.color ?? EINK; ctx.textAlign = o.align ?? 'left'
  if ('letterSpacing' in ctx) (ctx as CanvasRenderingContext2D & { letterSpacing: string }).letterSpacing = o.track ?? '0px'
  let out = s
  if (o.max) while (out.length > 1 && ctx.measureText(out).width > o.max) out = out.slice(0, -2).trimEnd() + '…'
  ctx.fillText(out, x, y)
  if ('letterSpacing' in ctx) (ctx as CanvasRenderingContext2D & { letterSpacing: string }).letterSpacing = '0px'
}
const erect = (ctx: CanvasRenderingContext2D, x: number, y: number, w: number, hh: number, r: number | number[]) => { ctx.beginPath(); ctx.roundRect(x, y, w, hh, r) }
/** The light-lettered CFPi+ logo (public/brand/logo-on-dark.png) for the black header bands; same-origin, so the canvas stays clean. */
async function loadBrand(): Promise<HTMLImageElement | null> {
  const img = new Image()
  return new Promise(resolve => { img.onload = () => resolve(img.naturalWidth > 0 ? img : null); img.onerror = () => resolve(null); img.src = `${import.meta.env.BASE_URL}brand/logo-on-dark.png` })
}
/** Draws the logo with the given height at (x, y); falls back to the wordmark if the image is missing. */
function brandLogo(ctx: CanvasRenderingContext2D, img: HTMLImageElement | null, x: number, y: number, h: number) {
  if (!img) return etext(ctx, 'CFPi+', x, y + h * 0.7, { size: h * 0.5, weight: 800, color: '#ffffff', italic: true })
  ctx.imageSmoothingQuality = 'high'
  ctx.drawImage(img, x, y, img.naturalWidth * h / img.naturalHeight, h)
}
/** Black header band with the CFPi+ mark, a big italic title and the ratings stamp; returns the y where content starts. */
function poster(ctx: CanvasRenderingContext2D, W: number, title: string, meta: Meta, brand: HTMLImageElement | null) {
  ctx.fillStyle = EBG; ctx.fillRect(0, 0, W, W)
  ctx.fillStyle = EINK; ctx.fillRect(0, 0, W, 124)
  ctx.fillStyle = K.accent; ctx.fillRect(0, 124, W, 6)
  brandLogo(ctx, brand, 28, 12, 100)
  etext(ctx, title, W - 32, 78, { size: 52, weight: 800, color: '#ffffff', italic: true, track: '-1px', align: 'right' })
  etext(ctx, stamp(meta).toUpperCase(), W - 32, 106, { size: 12, weight: 600, color: '#bdbdbd', align: 'right', track: '1px' })
  return 130
}
function posterFooter(ctx: CanvasRenderingContext2D, W: number, text: string) {
  etext(ctx, text, 32, W - 20, { size: 11, weight: 700, color: EMUTE, track: '0.8px' })
}

/** Top 25 as a square 5 x 5 grid of team cards: rank, logo, name, CFPi+ rating, record and weekly rank move. */
export async function top25Png(meta: Meta, rows: TeamRow[], dir: Dir) {
  const top = rows.filter(r => r.rank != null && r.rank <= 25).sort((a, b) => a.rank! - b.rank!)
  const logos = await logosFor(top.map(r => r.team_id), dir)
  const { canvas, ctx } = createCanvas(1200, 1200)
  try { await document.fonts.ready } catch { /* system font */ }
  const y0 = poster(ctx, 1200, 'TOP 25', meta, await loadBrand()) + 22
  const X0 = 32, GAP = 12, CW = (1200 - X0 * 2 - GAP * 4) / 5, CH = (1200 - y0 - 46 - GAP * 4) / 5
  // One type size for everything on a card (14px; 10px for the small column captions), centered on the same axes
  const T = 14, CAP = 10
  const sgn = (v: number | null | undefined) => v == null ? '—' : signed(v)
  top.forEach((r, i) => {
    const x = X0 + (i % 5) * (CW + GAP), y = y0 + Math.floor(i / 5) * (CH + GAP), cx = x + CW / 2
    erect(ctx, x, y, CW, CH, 8); ctx.fillStyle = '#ffffff'; ctx.fill(); ctx.strokeStyle = ELINE; ctx.lineWidth = 1; ctx.stroke()
    // Top row: rank badge (No. 1 in blue) | weekly rank move | record
    erect(ctx, x + 10, y + 10, 34, 24, 5); ctx.fillStyle = r.rank === 1 ? K.accent : EINK; ctx.fill()
    etext(ctx, String(r.rank), x + 27, y + 27, { size: T, weight: 800, color: '#ffffff', italic: true, align: 'center' })
    const mv = r.rank_change
    if (mv != null) etext(ctx, mv === 0 ? '—' : `${mv > 0 ? '▲' : '▼'} ${Math.abs(mv)}`, cx, y + 27, { size: T, weight: 800, color: mv === 0 ? EFAINT : mv > 0 ? K.up : K.down, align: 'center' })
    etext(ctx, rec(r), x + CW - 12, y + 27, { size: T, weight: 700, color: EMUTE, align: 'right' })
    logo(ctx, logos, r.team_id, nm(dir, r.team_id), cx, y + 68, 62)
    etext(ctx, nm(dir, r.team_id).toUpperCase(), cx, y + 118, { size: T, weight: 800, align: 'center', track: '0.3px', max: CW - 20 })
    etext(ctx, sgn(r.power), cx, y + 137, { size: T, weight: 800, color: K.accent, align: 'center' })
    ctx.fillStyle = ELINE; ctx.fillRect(x + 14, y + 147, CW - 28, 1)
    // Offense and defense: rating, with its national rank
    for (const [cxx, label, v, rk] of [[x + CW * 0.27, 'OFFENSE', r.off, r.off_rank], [x + CW * 0.73, 'DEFENSE', r.def, r.def_rank]] as const) {
      etext(ctx, label, cxx, y + 162, { size: CAP, weight: 700, color: EFAINT, align: 'center', track: '0.8px' })
      // rating in ink, its national rank in gray; the pair is centered on the column
      const val = sgn(v), rank = `#${rk ?? '—'}`
      ctx.font = `700 ${T}px ${EFONT}`; const vw = ctx.measureText(val).width, rw = ctx.measureText(rank).width, gap = 8
      const left = cxx - (vw + gap + rw) / 2
      etext(ctx, val, left, y + 180, { size: T, weight: 700 })
      etext(ctx, rank, left + vw + gap, y + 180, { size: T, weight: 700, color: EFAINT })
    }
  })
  posterFooter(ctx, 1200, `CFPi+ · CAVENDER FOOTBALL POWER INDEX · #N = NATIONAL RANK · DEFENSE: LOWER IS BETTER${meta.movement_compared_to_week != null ? ` · ▲▼ VS WEEK ${meta.movement_compared_to_week}` : ''}`)
  await savePng(canvas, file(meta, 'top25'))
}

/** Every FBS team as a square 12 x 12 grid of compact tiles: rank, logo and CFPi+ rating, in rank order. */
export async function allTeamsPng(meta: Meta, rows: TeamRow[], dir: Dir) {
  const all = rows.filter(r => r.rank != null).sort((a, b) => a.rank! - b.rank!)
  const logos = await logosFor(all.map(r => r.team_id), dir)
  const { canvas, ctx } = createCanvas(1200, 1200)
  try { await document.fonts.ready } catch { /* system font */ }
  const y0 = poster(ctx, 1200, 'ALL 138 TEAMS', meta, await loadBrand()) + 20
  const N = 12, X0 = 32, GAP = 6, CW = (1200 - X0 * 2 - GAP * (N - 1)) / N, CH = (1200 - y0 - 44 - GAP * (N - 1)) / N
  const FS = 10.5   // one size for every number on a tile
  all.forEach((r, i) => {
    const x = X0 + (i % N) * (CW + GAP), y = y0 + Math.floor(i / N) * (CH + GAP), cx = x + CW / 2
    erect(ctx, x, y, CW, CH, 6); ctx.fillStyle = '#ffffff'; ctx.fill(); ctx.strokeStyle = r.rank! <= 25 ? K.accent : ELINE; ctx.lineWidth = r.rank! <= 25 ? 2 : 1; ctx.stroke()
    etext(ctx, String(r.rank), x + 6, y + 13, { size: FS, weight: 700, color: r.rank! <= 25 ? K.accent : EMUTE, italic: true })
    logo(ctx, logos, r.team_id, nm(dir, r.team_id), cx, y + 26, 28)
    etext(ctx, signed(r.power), cx, y + 50, { size: FS, weight: 800, color: K.accent, align: 'center' })
    ctx.fillStyle = ELINE; ctx.fillRect(x + 6, y + CH - 21, CW - 12, 1); ctx.fillRect(cx - 0.5, y + CH - 17, 1, 13)
    etext(ctx, r.off == null ? '—' : signed(r.off), x + CW * 0.25, y + CH - 7, { size: FS, weight: 700, align: 'center' })
    etext(ctx, r.def == null ? '—' : signed(r.def), x + CW * 0.75, y + CH - 7, { size: FS, weight: 700, align: 'center' })
  })
  posterFooter(ctx, 1200, 'CFPi+ · RANK IN THE CORNER · BLUE = CFPi+ RATING · BELOW: OFFENSE (LEFT), DEFENSE (RIGHT; LOWER IS BETTER) · BLUE OUTLINE = TOP 25')
  await savePng(canvas, file(meta, 'all-teams'))
}

/** The weekly slate: every game of one week as a compact scoreboard card with logos only (no team names).
 *  Each team row shows the Vegas line on the favorite (bold) and the model's implied line on the team the model favors;
 *  the team the model picks against the spread (the side it likes more than the Vegas line) is highlighted in the
 *  site's blue. Each card ends with the game's watchability (matchup quality, 0-100) as a labelled meter. Lines are
 *  home-perspective in the data (negative = home favored) and are shown as the favorite's "-N", the underdog's "+N". */
export async function gamesPng(meta: Meta, games: Game[], dir: Dir, week: number, vegas: (g: Game) => number | null, ranks: Map<string, number>) {
  const slate = games.filter(g => g.week === week).sort((a, b) => Date.parse(a.kickoff) - Date.parse(b.kickoff))
  const logos = await logosFor(slate.flatMap(g => [g.home_id, g.away_id]), dir)
  const et = { timeZone: 'America/New_York' } as const
  const day = (g: Game) => new Date(g.kickoff).toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', ...et })
  const days: [string, Game[]][] = []
  for (const g of slate) { const d = day(g); const last = days[days.length - 1]; if (last?.[0] === d) last[1].push(g); else days.push([d, [g]]) }
  const GOLD = '#d4a017', ACC = K.accent, INK = '#0b1b33', MUTE = '#6b6b6b', FAINT = '#9a9a9a', LINE = '#dcdcdc', BG = '#ececef'
  const FONT = '"Helvetica Neue", Helvetica, "Arial Narrow", Arial, sans-serif'
  const W = 1500, X0 = 28, WIDE = W - X0 * 2, COLS = 7, GAP = 12, CW = (WIDE - GAP * (COLS - 1)) / COLS
  const STRIP = 26, ROW = 40, FOOT = 26, CH = STRIP + ROW * 2 + FOOT, DAYH = 40, HEAD = 96, LEG = 40
  const h = HEAD + LEG + days.reduce((n, [, gs]) => n + DAYH + Math.ceil(gs.length / COLS) * (CH + GAP) + 6, 0) + 44
  const time = (g: Game) => g.time_tbd ? 'TBD' : new Date(g.kickoff).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', ...et }).toUpperCase()
  const t = (ctx: CanvasRenderingContext2D, s: string, x: number, y: number, o: { size?: number; weight?: number; color?: string; align?: CanvasTextAlign; italic?: boolean; track?: string } = {}) => {
    ctx.font = `${o.italic ? 'italic ' : ''}${o.weight ?? 700} ${o.size ?? 14}px ${FONT}`
    ctx.fillStyle = o.color ?? INK; ctx.textAlign = o.align ?? 'left'
    if ('letterSpacing' in ctx) (ctx as CanvasRenderingContext2D & { letterSpacing: string }).letterSpacing = o.track ?? '0px'
    ctx.fillText(s, x, y)
    if ('letterSpacing' in ctx) (ctx as CanvasRenderingContext2D & { letterSpacing: string }).letterSpacing = '0px'
  }
  const rr = (ctx: CanvasRenderingContext2D, x: number, y: number, w: number, hh: number, r: number | number[]) => { ctx.beginPath(); ctx.roundRect(x, y, w, hh, r) }
  const { canvas, ctx } = createCanvas(W, h)
  try { await document.fonts.ready } catch { /* system font */ }
  ctx.fillStyle = BG; ctx.fillRect(0, 0, W, h)
  // Header band: black with a blue rule
  ctx.fillStyle = INK; ctx.fillRect(0, 0, W, HEAD - 5)
  ctx.fillStyle = ACC; ctx.fillRect(0, HEAD - 5, W, 5)
  brandLogo(ctx, await loadBrand(), X0, 8, 76)
  t(ctx, `WEEK ${week} SLATE`, W - X0, 58, { size: 44, weight: 800, color: '#ffffff', italic: true, track: '-1px', align: 'right' })
  t(ctx, stamp(meta).toUpperCase(), W - X0, 82, { size: 12, weight: 600, color: '#bdbdbd', align: 'right', track: '1px' })
  // Legend
  const ly = HEAD + 26
  let lx = X0
  rr(ctx, lx, ly - 13, 22, 17, 3); ctx.fillStyle = 'rgba(29, 111, 192, 0.14)'; ctx.fill(); ctx.fillStyle = ACC; ctx.fillRect(lx, ly - 13, 4, 17)
  t(ctx, 'MODEL’S SPREAD PICK', lx + 30, ly, { size: 11.5, color: INK, track: '0.6px' }); lx += 220
  t(ctx, '−7', lx, ly, { size: 15, weight: 800 }); t(ctx, 'VEGAS LINE', lx + 26, ly, { size: 11.5, track: '0.6px' }); lx += 130
  t(ctx, '−9.3', lx, ly, { size: 14, weight: 700, color: MUTE }); t(ctx, 'MODEL’S IMPLIED LINE', lx + 40, ly, { size: 11.5, track: '0.6px' }); lx += 200
  rr(ctx, lx, ly - 8, 46, 6, 3); ctx.fillStyle = '#d8d8dd'; ctx.fill(); rr(ctx, lx, ly - 8, 33, 6, 3); ctx.fillStyle = ACC; ctx.fill()
  t(ctx, 'WATCHABILITY: HOW GOOD THE GAME SHOULD BE, 0–100', lx + 58, ly, { size: 11.5, track: '0.6px' })
  ctx.font = `700 11.5px ${FONT}`
  lx += 58 + ctx.measureText('WATCHABILITY: HOW GOOD THE GAME SHOULD BE, 0–100').width + 60
  rr(ctx, lx, ly - 13, 22, 17, 3); ctx.strokeStyle = GOLD; ctx.lineWidth = 2.5; ctx.stroke()
  t(ctx, 'BOTH TEAMS TOP 30 IN CFPi+', lx + 30, ly, { size: 11.5, track: '0.6px' })
  let y = HEAD + LEG
  for (const [label, gs] of days) {
    ctx.fillStyle = INK; ctx.fillRect(X0, y, WIDE, DAYH - 6)
    ctx.fillStyle = ACC; ctx.fillRect(X0, y, 7, DAYH - 6)
    t(ctx, label.toUpperCase(), X0 + 22, y + 22, { size: 16, weight: 800, color: '#ffffff', italic: true, track: '0.6px' })
    t(ctx, `${gs.length} ${gs.length === 1 ? 'GAME' : 'GAMES'}`, X0 + WIDE - 14, y + 22, { size: 11.5, weight: 700, color: '#bdbdbd', align: 'right', track: '1px' })
    y += DAYH
    gs.forEach((g, i) => {
      const x = X0 + (i % COLS) * (CW + GAP), cy = y + Math.floor(i / COLS) * (CH + GAP)
      rr(ctx, x, cy, CW, CH, 6); ctx.fillStyle = '#ffffff'; ctx.fill(); ctx.strokeStyle = LINE; ctx.lineWidth = 1; ctx.stroke()
      const k = vegas(g), m = g.spread_home
      const marquee = (ranks.get(g.away_id) ?? 999) <= 15 && (ranks.get(g.home_id) ?? 999) <= 15
      const edge = k != null && m != null ? m + k : null   // home perspective: > 0 = the model likes the home side more than the line
      // Strip: kickoff (or the final score) and the column captions
      ctx.fillStyle = '#f6f6f8'; rr(ctx, x + 1, cy + 1, CW - 2, STRIP - 1, [5, 5, 0, 0]); ctx.fill()
      t(ctx, g.status === 'final' ? `FINAL ${g.away_points}–${g.home_points}` : `${time(g)}${g.neutral ? ' · N' : ''}`, x + 12, cy + 18, { size: 10.5, weight: 700, color: MUTE, track: '0.3px' })
      t(ctx, 'VEGAS', x + CW / 2, cy + 18, { size: 9.5, weight: 700, color: FAINT, align: 'center', track: '0.8px' })
      t(ctx, 'MODEL', x + CW * 5 / 6, cy + 18, { size: 9.5, weight: 700, color: FAINT, align: 'center', track: '0.8px' })
      const rows = [{ id: g.away_id, name: g.away_team, home: false }, { id: g.home_id, name: g.home_team, home: true }]
      rows.forEach((sd, r) => {
        const ry = cy + STRIP + r * ROW
        const pick = edge != null && Math.abs(edge) >= 0.05 && (edge > 0) === sd.home
        if (pick) { ctx.fillStyle = 'rgba(29, 111, 192, 0.10)'; ctx.fillRect(x + 1, ry, CW - 2, ROW); ctx.fillStyle = ACC; ctx.fillRect(x + 1, ry, 5, ROW) }
        if (r === 0) { ctx.fillStyle = LINE; ctx.fillRect(x + 1, ry + ROW - 1, CW - 2, 1) }
        if (logos.has(sd.id)) logo(ctx, logos, sd.id, nm(dir, sd.id, sd.name), x + CW / 6, ry + ROW / 2, 36)
        else {   // no logo available: the team's name, up to two lines
          const words = nm(dir, sd.id, sd.name).split(/\s+/), lines: string[] = ['']
          ctx.font = `700 11.5px ${FONT}`
          for (const w of words) { const next = lines[lines.length - 1] ? `${lines[lines.length - 1]} ${w}` : w; if (ctx.measureText(next).width <= 56 || !lines[lines.length - 1]) lines[lines.length - 1] = next; else if (lines.length < 2) lines.push(w); else lines[1] = `${lines[1]} ${w}` }
          lines.slice(0, 2).forEach((ln, li, all) => { let out = ln; while (out.length > 1 && ctx.measureText(out).width > 56) out = out.slice(0, -2) + '…'; t(ctx, out, x + CW / 6, ry + ROW / 2 + 4 + (li - (all.length - 1) / 2) * 13, { size: 11.5, weight: 700, align: 'center' }) })
        }
        const vFav = k != null && k !== 0 && (k < 0) === sd.home, mFav = m != null && Math.abs(m) >= 0.05 && (m > 0) === sd.home
        if (vFav) t(ctx, `−${Math.abs(k!)}`, x + CW / 2, ry + 26, { size: 16, weight: 700, align: 'center' })
        else if (k === 0) t(ctx, 'PK', x + CW / 2, ry + 26, { size: 16, weight: 700, align: 'center' })
        else if (k != null) t(ctx, `+${Math.abs(k)}`, x + CW / 2, ry + 26, { size: 16, weight: 700, color: pick ? ACC : FAINT, align: 'center' })
        if (mFav) t(ctx, `−${Math.abs(m!).toFixed(1)}`, x + CW * 5 / 6, ry + 26, { size: 16, weight: 700, color: pick ? ACC : MUTE, align: 'center' })
        else if (m != null && Math.abs(m) < 0.05) t(ctx, 'EVEN', x + CW * 5 / 6, ry + 26, { size: 16, weight: 700, color: MUTE, align: 'center' })
      })
      // Gold outline: both teams are top-15 CFPi+ (same rule as the home-page ticker)
      if (marquee) { rr(ctx, x + 1.5, cy + 1.5, CW - 3, CH - 3, 6); ctx.strokeStyle = GOLD; ctx.lineWidth = 3; ctx.stroke() }
      // Footer: watchability as a labelled meter
      const fy = cy + STRIP + ROW * 2
      ctx.fillStyle = LINE; ctx.fillRect(x + 1, fy, CW - 2, 1)
      if (g.quality != null) {
        t(ctx, 'WATCHABILITY', x + 10, fy + 17, { size: 8.5, weight: 700, color: FAINT, track: '0.4px' })
        rr(ctx, x + 84, fy + 10, CW - 84 - 50, 6, 3); ctx.fillStyle = '#e3e3e8'; ctx.fill()
        rr(ctx, x + 84, fy + 10, Math.max(4, (CW - 84 - 50) * g.quality / 100), 6, 3); ctx.fillStyle = ACC; ctx.fill()
        t(ctx, `${g.quality}`, x + CW - 24, fy + 18, { size: 14, weight: 800, align: 'right' })
        t(ctx, '/100', x + CW - 22, fy + 18, { size: 8.5, weight: 600, color: FAINT })
      } else t(ctx, 'WATCHABILITY —', x + 12, fy + 17, { size: 9.5, weight: 700, color: FAINT, track: '0.8px' })
    })
    y += Math.ceil(gs.length / COLS) * (CH + GAP) + 6
  }
  t(ctx, 'CFPi+ · CAVENDER FOOTBALL POWER INDEX · LINES FOR REFERENCE ONLY, NOT BETTING ADVICE', X0, h - 18, { size: 10.5, weight: 700, color: MUTE, track: '0.8px' })
  await savePng(canvas, file(meta, `week${week}-slate`))
}

export async function playoffOddsPng(doc: PlayoffDoc, dir: Dir) {
  const rows = [...doc.teams].sort((a, b) => b.p_playoff - a.p_playoff).slice(0, 25)
  const logos = await logosFor(rows.map(r => r.team_id), dir)
  type R = (typeof rows)[number]
  const p = (k: keyof R, bold = false): Col<R>['draw'] => (c, r, x, y, w) => text(c, pct(r[k] as number), x + w - 8, y + 5.5, { size: 15, weight: bold ? 700 : 500, align: 'right' })
  const cols: Col<R>[] = [
    { label: 'Team', w: 360, draw: (c, r, x, y, w) => teamCell(c, logos, r.team_id, nm(dir, r.team_id), dir.get(r.team_id)?.conference ?? null, x, y, w) },
    { label: 'Playoff', w: 250, draw: (c, r, x, y) => { bar(c, r.p_playoff, x, y, 150); text(c, pct(r.p_playoff), x + 240, y + 5.5, { size: 15, weight: 700, align: 'right' }) } },
    { label: 'Bye', w: 120, align: 'right', draw: p('p_bye') },
    { label: 'Semis', w: 120, align: 'right', draw: p('p_sf') },
    { label: 'Title', w: 120, align: 'right', draw: p('p_champ') },
    { label: 'Avg Seed', w: 118, align: 'right', draw: (c, r, x, y, w) => text(c, r.mean_seed == null ? '—' : r.mean_seed.toFixed(1), x + w - 8, y + 5.5, { size: 15, color: K.muted, align: 'right' }) },
  ]
  const h = H(rows.length, 40, 20)
  await render(file(doc.meta, 'cfp-odds'), h, ctx => {
    const t = frame(ctx, h, 'College Football Playoff odds', `Share of ${doc.meta.sim_count?.toLocaleString() ?? ''} simulated seasons. Top 25 by playoff probability.`, doc.meta)
    const end = table(ctx, t, cols, rows, 40)
    text(ctx, '12-team field, 2026 rules: power-conference champions, the top-ranked team from the other conferences, at-large bids. Top four seeds get byes.', LEFT, end + 30, { size: 13, color: K.muted, max: INNER })
  })
}

export async function moversPng(meta: Meta, rows: TeamRow[], changes: ChangesDoc, dir: Dir) {
  const rated = rows.filter(r => r.rank_change != null && r.rating_change != null)
  const lists: [string, TeamRow[], 'rank' | 'rating'][] = [
    ['Biggest risers', rated.filter(r => r.rank_change! > 0).sort((a, b) => b.rank_change! - a.rank_change! || a.rank! - b.rank!).slice(0, 6), 'rank'],
    ['Biggest fallers', rated.filter(r => r.rank_change! < 0).sort((a, b) => a.rank_change! - b.rank_change! || a.rank! - b.rank!).slice(0, 6), 'rank'],
    ['Largest rating gains', rated.filter(r => r.rating_change! > 0).sort((a, b) => b.rating_change! - a.rating_change!).slice(0, 6), 'rating'],
    ['Largest rating drops', rated.filter(r => r.rating_change! < 0).sort((a, b) => a.rating_change! - b.rating_change!).slice(0, 6), 'rating'],
  ]
  const logos = await logosFor(lists.flatMap(l => l[1].map(r => r.team_id)), dir)
  const h = 222 + 2 * 360 + 120
  await render(file(meta, 'movers'), h, ctx => {
    const t = frame(ctx, h, 'What changed this week', `Compared with Week ${changes.compared_to_week}${changes.compared_to_source === 'reconstructed' ? ' (reconstructed)' : ''}. Rank movement and rating change are listed separately.`, meta)
    const bw = (INNER - 24) / 2
    lists.forEach(([title, list, kind], i) => {
      const x = LEFT + (i % 2) * (bw + 24), y = t + Math.floor(i / 2) * 360
      ctx.beginPath(); ctx.roundRect(x, y, bw, 336, 14); ctx.fillStyle = K.fill; ctx.fill()
      text(ctx, title.toUpperCase(), x + 20, y + 34, { size: 12, weight: 600, color: K.muted, track: '0.6px' })
      list.forEach((r, k) => {
        const yy = y + 72 + k * 44
        const sub = kind === 'rank' ? `No. ${r.rank_prev} → No. ${r.rank}` : `${signed(r.power)} now`
        logo(ctx, logos, r.team_id, nm(dir, r.team_id), x + 34, yy, 26)
        text(ctx, nm(dir, r.team_id), x + 58, yy - 1, { size: 15.5, weight: 600, max: bw - 200 })
        text(ctx, sub, x + 58, yy + 15, { size: 12.5, color: K.muted })
        if (kind === 'rank') move(ctx, r.rank_change, x, yy, bw - 12)
        else text(ctx, `${signed(r.rating_change)} pts`, x + bw - 20, yy + 5.5, { size: 15, weight: 600, color: r.rating_change! > 0 ? K.up : K.down, align: 'right' })
      })
    })
  })
}

