import type { ExportResult } from './exportImage'
import { BODY, C, DISPLAY, MONO, createCanvas, drawFooterBrand, drawLogo, drawMasthead, fit, loadFonts, loadLogos, rounded, savePng, spacing } from './exportImage'
import { DEFAULT_MODEL, HUNT_THRESHOLD, TIERS, buildBracket, huntTeams, likelyChampions, rankTeams, relax, selectField, type Game, type MarginModel, type PlayoffTeam, type Seeded } from './playoff'

// Season Simulations share graphics: the Playoff Hunt scatter and the most-likely
// bracket. Both use the light palette and masthead of the rankings export.
type Common = { teams: PlayoffTeam[]; season: number; week: number | null; updatedAt: string | null; asOf: string | null; simulations: number | null }
type Logos = Map<string, HTMLImageElement>

const MINUS = '−'
const weekTag = (week: number | null, season: number) => `${week == null ? 'LATEST' : `WEEK ${week}`} · ${season}`
const weekFile = (week: number | null) => week == null ? 'latest' : `week-${String(week).padStart(2, '0')}`
const pctText = (p: number) => p >= 0.995 && p < 1 ? '>99%' : p > 0 && p < 0.005 ? '<1%' : `${Math.round(p * 100)}%`
const pct1 = (p: number) => p > 0 && p < 0.001 ? '<0.1%' : `${(p * 100).toFixed(1)}%`
const signedPts = (v: number) => { const r = Math.round(v * 10) / 10; return `${r > 0 ? '+' : ''}${(Object.is(r, -0) ? 0 : r).toFixed(1).replace('-', MINUS)}` }
const sims = (n: number | null) => n == null ? 'the simulated seasons' : `${n.toLocaleString('en-US')} simulated seasons`
const asOfText = (asOf: string | null) => asOf ? new Date(asOf).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' }) : null
const CONF_SHORT: Record<string, string> = { 'American Athletic': 'American', 'Conference USA': 'C-USA', 'Mid-American': 'MAC', 'FBS Independents': 'Independent' }
const confShort = (c: string | null) => c ? CONF_SHORT[c] ?? c : '—'

function label(ctx: CanvasRenderingContext2D, text: string, x: number, y: number, { size = 11, weight = 600, color = C.muted, track = '1.6px', align = 'left' as CanvasTextAlign } = {}) {
  spacing(ctx, track)
  ctx.font = `${weight} ${size}px ${MONO}`
  ctx.fillStyle = color
  ctx.textAlign = align
  ctx.fillText(text, x, y)
  spacing(ctx, '0px')
  ctx.textAlign = 'left'
}
function card(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r = 6, fill: string = C.card) {
  ctx.save()
  ctx.shadowColor = 'rgba(28, 47, 85, 0.10)'
  ctx.shadowBlur = 14
  ctx.shadowOffsetY = 4
  rounded(ctx, x, y, w, h, r)
  ctx.fillStyle = fill
  ctx.fill()
  ctx.restore()
  rounded(ctx, x + 0.5, y + 0.5, w - 1, h - 1, r)
  ctx.strokeStyle = C.line
  ctx.lineWidth = 1
  ctx.stroke()
}
/** Navy header bar with a gold rule, as on the rankings export's columns. */
function panelHead(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, text: string, right?: string) {
  ctx.save()
  rounded(ctx, x, y, w, 36, [6, 6, 0, 0])
  ctx.clip()
  ctx.fillStyle = C.navyDeep
  ctx.fillRect(x, y, w, 36)
  ctx.fillStyle = C.gold
  ctx.fillRect(x, y + 34, w, 2)
  ctx.restore()
  label(ctx, text, x + 16, y + 22.5, { size: 11, color: C.cream, track: '1.8px' })
  if (right) label(ctx, right, x + w - 16, y + 22.5, { size: 10.5, weight: 500, color: '#c5cfe0', track: '1.4px', align: 'right' })
}
function lede(ctx: CanvasRenderingContext2D, text: string, x: number, y: number) {
  ctx.font = `400 16px ${BODY}`
  ctx.fillStyle = C.ink2
  ctx.textAlign = 'left'
  ctx.fillText(text, x, y)
}
function notes(ctx: CanvasRenderingContext2D, lines: string[], x: number, y: number, max: number) {
  ctx.font = `italic 400 13px ${BODY}`
  ctx.fillStyle = C.muted
  ctx.textAlign = 'left'
  lines.forEach((line, i) => ctx.fillText(fit(ctx, line, max), x, y + i * 21))
}

// ══════════════════════════ Playoff Hunt ══════════════════════════════════
export async function exportPlayoffHuntPng({ teams, season, week, updatedAt, asOf, simulations }: Common): Promise<ExportResult> {
  await loadFonts()
  const shown = huntTeams(teams)
  if (!shown.length) throw new Error('No team clears the playoff-odds threshold')
  const titleLeaders = rankTeams(teams).filter(t => t.title > 0).sort((a, b) => b.title - a.title || b.playoff - a.playoff).slice(0, 8)
  const champs = [...likelyChampions(rankTeams(teams))].filter(([conf]) => conf !== 'FBS Independents')
    .map(([conf, t]) => ({ conf, t })).sort((a, b) => b.t.playoff - a.t.playoff)
  const logos = await loadLogos([...new Map([...shown, ...titleLeaders, ...champs.map(c => c.t)].map(t => [t.team_id, t])).values()])

  const W = 1600, pad = 56
  const plot = { x0: pad + 78, y0: 236, x1: 1112, y1: 1136 }
  const side = { x: 1156, w: W - pad - 1156 }
  const H = plot.y1 + 224
  const { canvas, ctx } = createCanvas(W, H)
  drawMasthead(ctx, W, pad, { kicker: 'COLLEGE FOOTBALL · SEASON SIMULATIONS', title: 'The Playoff Hunt', chips: [weekTag(week, season), simulations ? `${simulations.toLocaleString('en-US')} SIMS` : 'SIMULATIONS'], updatedAt })
  lede(ctx, `Every contender’s playoff odds against its power rating, from ${sims(simulations)}.`, pad, 192)

  // Scales. Odds use equal-weight bands so the crowded low end stays legible;
  // ticks sit exactly on the band edges, where the scale bends.
  const powers = shown.map(t => t.power)
  const xMin = Math.min(-5, Math.floor(Math.min(...powers) / 5) * 5), xMax = Math.ceil(Math.max(...powers) / 5) * 5
  const inset = 26
  const X = (v: number) => plot.x0 + inset + (v - xMin) / (xMax - xMin) * (plot.x1 - plot.x0 - inset * 2)
  const share = [0.3, 0.3, 0.18, 0.22] // long shots, bubble, hunt, driver (bottom → top)
  const bands = [...TIERS].reverse()
  const Y = (p: number) => {
    let base = plot.y1
    for (let i = 0; i < bands.length; i++) {
      const b = bands[i], h = share[i] * (plot.y1 - plot.y0)
      if (p <= b.max || i === bands.length - 1) return base - Math.min(1, (p - b.min) / (b.max - b.min)) * h
      base -= h
    }
    return plot.y0
  }

  // Tier bands
  const fills: Record<string, string> = { driver: '#efe1c3', hunt: '#f6ecd8', bubble: '#eaeef5', long: '#f1ede4' }
  const inks: Record<string, string> = { driver: C.goldInk, hunt: C.goldInk, bubble: C.navy, long: C.ink2 }
  ctx.save()
  rounded(ctx, plot.x0, plot.y0, plot.x1 - plot.x0, plot.y1 - plot.y0, 6)
  ctx.clip()
  for (const b of TIERS) {
    const top = Y(b.max), bottom = Y(b.min)
    ctx.fillStyle = fills[b.key]
    ctx.fillRect(plot.x0, top, plot.x1 - plot.x0, bottom - top)
    if (b.min > 0) { ctx.fillStyle = 'rgba(28, 47, 85, 0.16)'; ctx.fillRect(plot.x0, bottom - 0.5, plot.x1 - plot.x0, 1) }
  }
  // Vertical grid every 5 points
  for (let v = xMin; v <= xMax; v += 5) { ctx.fillStyle = 'rgba(28, 47, 85, 0.07)'; ctx.fillRect(X(v) - 0.5, plot.y0, 1, plot.y1 - plot.y0) }
  // FBS average
  ctx.strokeStyle = C.navy
  ctx.globalAlpha = 0.55
  ctx.lineWidth = 1.25
  ctx.setLineDash([5, 5])
  ctx.beginPath(); ctx.moveTo(X(0), plot.y0); ctx.lineTo(X(0), plot.y1); ctx.stroke()
  ctx.setLineDash([])
  ctx.globalAlpha = 1
  // Band labels, backed with the band colour so the average line passes behind them
  for (const b of TIERS) {
    const top = Y(b.max)
    spacing(ctx, '3px')
    ctx.font = `800 21px ${DISPLAY}`
    ctx.fillStyle = fills[b.key]
    ctx.fillRect(plot.x0 + 12, top + 12, ctx.measureText(b.label.toUpperCase()).width + 16, 54)
    ctx.fillStyle = inks[b.key]
    ctx.fillText(b.label.toUpperCase(), plot.x0 + 20, top + 36)
    label(ctx, b.min === 0 ? `UNDER ${Math.round(b.max * 100)}%` : b.max === 1 ? `${Math.round(b.min * 100)}%+` : `${Math.round(b.min * 100)}–${Math.round(b.max * 100)}%`, plot.x0 + 21, top + 57, { size: 11.5, weight: 500, color: C.muted, track: '2px' })
  }
  ctx.restore()
  rounded(ctx, plot.x0 + 0.5, plot.y0 + 0.5, plot.x1 - plot.x0 - 1, plot.y1 - plot.y0 - 1, 6)
  ctx.strokeStyle = C.line
  ctx.lineWidth = 1
  ctx.stroke()
  ctx.fillStyle = C.navy
  ctx.fillRect(plot.x0, plot.y1 - 1, plot.x1 - plot.x0, 2)

  // FBS average chip
  spacing(ctx, '1.6px')
  ctx.font = `600 10.5px ${MONO}`
  const avgW = ctx.measureText('FBS AVERAGE').width + 16
  rounded(ctx, X(0) - avgW / 2, plot.y1 - 34, avgW, 22, 3)
  ctx.fillStyle = C.card
  ctx.fill()
  ctx.strokeStyle = C.navyLine
  ctx.stroke()
  ctx.fillStyle = C.navy
  ctx.textAlign = 'center'
  ctx.fillText('FBS AVERAGE', X(0), plot.y1 - 19)
  spacing(ctx, '0px')

  // Axes
  ctx.font = `700 16px ${MONO}`
  ctx.fillStyle = C.ink
  ctx.textAlign = 'right'
  for (const p of [0, ...TIERS.map(t => t.min).filter(Boolean), 1]) ctx.fillText(`${Math.round(p * 100)}%`, plot.x0 - 14, Y(p) + 6)
  ctx.textAlign = 'center'
  ctx.font = `600 15px ${MONO}`
  for (let v = xMin; v <= xMax; v += 5) ctx.fillText(v === 0 ? '0' : signedPts(v).replace('.0', ''), X(v), plot.y1 + 28)
  label(ctx, 'POWER RATING · POINTS VS. AN AVERAGE FBS TEAM', (plot.x0 + plot.x1) / 2, plot.y1 + 60, { size: 12, color: C.ink2, track: '3px', align: 'center' })
  ctx.save()
  ctx.translate(pad + 8, (plot.y0 + plot.y1) / 2)
  ctx.rotate(-Math.PI / 2)
  label(ctx, 'PLAYOFF ODDS', 0, 0, { size: 12, color: C.ink2, track: '3px', align: 'center' })
  ctx.restore()

  // Logos, nudged apart where they collide; displaced logos keep a leader to the exact value.
  const box = 36
  const exact = shown.map(t => ({ x: X(t.power), y: Y(t.playoff) }))
  const placed = relax(exact, box * 0.5, { x0: plot.x0 + 2, y0: plot.y0 + 2, x1: plot.x1 - 2, y1: plot.y1 - 2 })
  shown.forEach((_, i) => {
    const e = exact[i], p = placed[i]
    if (Math.hypot(p.x - e.x, p.y - e.y) < 5) return
    ctx.strokeStyle = 'rgba(28, 47, 85, 0.45)'
    ctx.lineWidth = 1
    ctx.beginPath(); ctx.moveTo(e.x, e.y); ctx.lineTo(p.x, p.y); ctx.stroke()
    ctx.beginPath(); ctx.arc(e.x, e.y, 2.5, 0, Math.PI * 2); ctx.fillStyle = C.navy; ctx.fill()
  })
  // Draw weakest odds first so the leaders sit on top.
  shown.map((t, i) => ({ t, p: placed[i] })).reverse().forEach(({ t, p }) => {
    ctx.save()
    ctx.shadowColor = 'rgba(20, 34, 63, 0.28)'
    ctx.shadowBlur = 5
    ctx.shadowOffsetY = 1.5
    drawLogo(ctx, logos.get(t.team_id), t.team, p.x, p.y, box)
    ctx.restore()
  })

  // Side panel 1: national title odds
  let y = plot.y0
  const rowH = 36
  const titleH = 36 + titleLeaders.length * rowH + 8
  card(ctx, side.x, y, side.w, titleH)
  panelHead(ctx, side.x, y, side.w, 'NATIONAL TITLE ODDS')
  const maxTitle = Math.max(...titleLeaders.map(t => t.title), 0.01)
  titleLeaders.forEach((t, j) => {
    const ry = y + 36 + 4 + j * rowH, mid = ry + rowH / 2
    if (j) { ctx.fillStyle = C.line; ctx.fillRect(side.x + 14, ry, side.w - 28, 1) }
    label(ctx, String(j + 1).padStart(2, '0'), side.x + 16, mid + 4.5, { size: 12, weight: j < 3 ? 600 : 500, color: j < 3 ? C.goldInk : C.muted, track: '0px' })
    drawLogo(ctx, logos.get(t.team_id), t.team, side.x + 56, mid, 22)
    ctx.font = `500 14.5px ${BODY}`
    ctx.fillStyle = C.ink
    ctx.textAlign = 'left'
    ctx.fillText(fit(ctx, t.team, 118), side.x + 76, mid + 5)
    const bx = side.x + 202, bw = side.w - 202 - 70
    rounded(ctx, bx, mid - 4, bw, 8, 4); ctx.fillStyle = C.goldSoft; ctx.fill()
    rounded(ctx, bx, mid - 4, Math.max(4, bw * t.title / maxTitle), 8, 4); ctx.fillStyle = C.gold; ctx.fill()
    ctx.font = `600 13.5px ${MONO}`
    ctx.fillStyle = C.ink
    ctx.textAlign = 'right'
    ctx.fillText(pct1(t.title), side.x + side.w - 16, mid + 5)
    ctx.textAlign = 'left'
  })

  // Side panel 2: likeliest conference champions (the automatic-bid race)
  y += titleH + 24
  const confH = 36 + champs.length * rowH + 8
  card(ctx, side.x, y, side.w, confH)
  panelHead(ctx, side.x, y, side.w, 'CONFERENCE FAVORITES', 'TITLE ODDS')
  champs.forEach(({ conf, t }, j) => {
    const ry = y + 36 + 4 + j * rowH, mid = ry + rowH / 2
    if (j) { ctx.fillStyle = C.line; ctx.fillRect(side.x + 14, ry, side.w - 28, 1) }
    label(ctx, confShort(conf).toUpperCase(), side.x + 16, mid + 4, { size: 10.5, weight: 600, color: C.navy, track: '1.2px' })
    drawLogo(ctx, logos.get(t.team_id), t.team, side.x + 140, mid, 22)
    ctx.font = `500 14.5px ${BODY}`
    ctx.fillStyle = C.ink
    ctx.textAlign = 'left'
    ctx.fillText(fit(ctx, t.team, side.w - 160 - 70), side.x + 160, mid + 5)
    ctx.font = `600 13.5px ${MONO}`
    ctx.textAlign = 'right'
    ctx.fillText(pctText(t.confTitle), side.x + side.w - 16, mid + 5)
    ctx.textAlign = 'left'
  })

  // Side panel 3: count of teams on the board
  y += confH + 24
  if (plot.y1 - y >= 84) {
    card(ctx, side.x, y, side.w, plot.y1 - y, 6, C.card)
    ctx.fillStyle = C.gold
    ctx.fillRect(side.x + 18, y + 22, 28, 2)
    ctx.font = `800 44px ${DISPLAY}`
    ctx.fillStyle = C.navy
    spacing(ctx, '-1px')
    ctx.fillText(String(shown.length), side.x + 18, y + 72)
    const numW = ctx.measureText(String(shown.length)).width
    spacing(ctx, '0px')
    ctx.font = `500 14px ${BODY}`
    ctx.fillStyle = C.ink2
    ctx.fillText('teams with at least a', side.x + 30 + numW, y + 52)
    ctx.fillText(`${Math.round(HUNT_THRESHOLD * 100)}% shot at a playoff seed`, side.x + 30 + numW, y + 71)
  }

  // Footer
  const fy = plot.y1 + 96
  ctx.fillStyle = C.line
  ctx.fillRect(pad, fy, W - pad * 2, 1)
  const run = asOfText(asOf)
  notes(ctx, [
    'Power rating: opponent-adjusted margin against an average FBS team on a neutral field. Playoff odds: share of simulated seasons ending with a CFP seed.',
    `Only teams with at least a ${Math.round(HUNT_THRESHOLD * 100)}% chance are shown. Overlapping logos are nudged apart; a dot marks the exact value. The odds axis is scaled by band.`,
    `Title and conference odds from the same ${sims(simulations)}${run ? `, games through ${run}` : ''}. Model-based expectations, not guarantees.`,
  ], pad, fy + 32, W - pad * 2 - 220)
  drawFooterBrand(ctx, W - pad, fy + 74)

  await savePng(canvas, `cfb-power-index-playoff-hunt-${season}-${weekFile(week)}.png`)
  const all = new Set([...shown, ...titleLeaders, ...champs.map(c => c.t)].map(t => t.team_id))
  return { logos: [...all].filter(id => logos.has(id)).length, total: all.size }
}

// ══════════════════════════ Projected bracket ═════════════════════════════
type BracketOptions = Common & { model?: MarginModel; ineligible?: string[] }

const ROW = 40, CARD_W = 226
const AUTO_LABEL = (t: Seeded) => t.autoBid === 'champion' ? `${confShort(t.conference).toUpperCase()} CHAMP` : t.autoBid === 'g6' ? 'TOP G6' : t.autoBid === 'notre-dame' ? 'TOP-12 IND.' : 'AT-LARGE'

type Box = { x: number; y: number; w: number; game: Game; rowH: number }
const rowCenter = (b: Box, top: boolean) => b.y + b.rowH * (top ? 0.5 : 1.5)
const winnerOnTop = (g: Game) => g.winner === g.top

function matchup(ctx: CanvasRenderingContext2D, logos: Logos, b: Box, champion: Seeded, big = false) {
  const { x, y, w, game, rowH } = b
  card(ctx, x, y, w, rowH * 2)
  ctx.fillStyle = C.line
  ctx.fillRect(x + 10, y + rowH, w - 20, 1)
  for (const [team, top] of [[game.top, true], [game.bottom, false]] as const) {
    const won = team === game.winner
    const mid = rowCenter(b, top)
    const rowY = mid - rowH / 2
    const champ = won && team.team_id === champion.team_id && game.round === 3
    if (won) {
      ctx.save()
      rounded(ctx, x, y, w, rowH * 2, 6)
      ctx.clip()
      ctx.fillStyle = champ ? C.goldSoft : 'rgba(232, 236, 244, 0.55)'
      ctx.fillRect(x, rowY, w, rowH)
      ctx.fillStyle = champ ? C.gold : C.navy
      ctx.fillRect(x, rowY, 3, rowH)
      ctx.restore()
    }
    // Seed chip: navy for the top four (byes), cream otherwise
    const bye = team.seed <= 4
    rounded(ctx, x + 11, mid - 11, 26, 22, 4)
    ctx.fillStyle = bye ? C.navy : C.cream
    ctx.fill()
    if (!bye) { ctx.strokeStyle = C.line; ctx.lineWidth = 1; ctx.stroke() }
    ctx.font = `600 12px ${MONO}`
    ctx.fillStyle = bye ? C.cream : C.ink2
    ctx.textAlign = 'center'
    ctx.fillText(String(team.seed), x + 24, mid + 4.5)
    ctx.globalAlpha = won ? 1 : 0.42
    drawLogo(ctx, logos.get(team.team_id), team.team, x + 56, mid, big ? 28 : 24)
    ctx.globalAlpha = 1
    const nameX = x + (big ? 80 : 76)
    ctx.textAlign = 'left'
    ctx.font = `${won ? 600 : 500} ${big ? 17 : 15}px ${BODY}`
    ctx.fillStyle = won ? C.ink : C.muted
    ctx.fillText(fit(ctx, team.team, w - (nameX - x) - 46), nameX, mid + (big ? 6 : 5))
    const p = won ? game.winProbability : 1 - game.winProbability
    ctx.font = `${won ? 600 : 500} ${big ? 14 : 13}px ${MONO}`
    ctx.fillStyle = won ? (champ ? C.goldInk : C.navy) : C.faint
    ctx.textAlign = 'right'
    ctx.fillText(pctText(p), x + w - 12, mid + 4.5)
    ctx.textAlign = 'left'
  }
}

/** Elbow from the winner row of `from` into one row of `to`. */
function connect(ctx: CanvasRenderingContext2D, from: Box, to: Box, intoTop: boolean, gold: boolean) {
  const leftToRight = from.x < to.x
  const sx = leftToRight ? from.x + from.w : from.x
  const ex = leftToRight ? to.x : to.x + to.w
  const sy = rowCenter(from, winnerOnTop(from.game))
  const ey = rowCenter(to, intoTop)
  const mx = (sx + ex) / 2
  ctx.strokeStyle = gold ? C.gold : C.navy
  ctx.globalAlpha = gold ? 1 : 0.55
  ctx.lineWidth = gold ? 2.5 : 1.5
  ctx.lineJoin = 'round'
  ctx.beginPath()
  ctx.moveTo(sx, sy); ctx.lineTo(mx, sy); ctx.lineTo(mx, ey); ctx.lineTo(ex, ey)
  ctx.stroke()
  ctx.globalAlpha = 1
}

export async function exportBracketPng({ teams, season, week, updatedAt, asOf, simulations, model = DEFAULT_MODEL, ineligible = [] }: BracketOptions): Promise<ExportResult> {
  await loadFonts()
  const bracket = buildBracket(selectField(teams, { ineligible }), model)
  const { field, rounds, champion } = bracket
  const titleOdds = rankTeams(teams).filter(t => t.title > 0).sort((a, b) => b.title - a.title).slice(0, 5)
  const logos = await loadLogos([...new Map([...field, ...titleOdds].map(t => [t.team_id, t])).values()])

  const W = 1960, pad = 48, gap = 28
  const fieldY = 846, chipH = 58, footY = fieldY + 16 + chipH + 40
  const H = footY + 96
  const { canvas, ctx } = createCanvas(W, H)
  drawMasthead(ctx, W, pad, { kicker: 'COLLEGE FOOTBALL · SEASON SIMULATIONS', title: 'Projected Playoff', chips: [weekTag(week, season), 'MOST LIKELY PATH'], updatedAt })
  lede(ctx, `The likeliest 12-team field under 2026 rules, with the model favorite advancing from every game. Percentages are each game’s win probability.`, pad, 192)

  // Columns: FR, QF, SF | final | SF, QF, FR (left half = seeds 1/4 pod, right half = 2/3 pod)
  const colX = (i: number) => pad + i * (CARD_W + gap)
  const rColX = (i: number) => W - pad - CARD_W - i * (CARD_W + gap)
  const heads = ['FIRST ROUND', 'QUARTERFINALS', 'SEMIFINALS']
  const headY = 250
  for (let i = 0; i < 3; i++) for (const x of [colX(i), rColX(i)]) {
    label(ctx, heads[i], x + CARD_W / 2, headY, { size: 12, color: C.navy, track: '2.4px', align: 'center' })
    ctx.fillStyle = C.gold
    ctx.fillRect(x + CARD_W / 2 - 14, headY + 10, 28, 2)
    if (i === 0) label(ctx, 'HIGHER SEED HOSTS', x + CARD_W / 2, headY + 30, { size: 10, weight: 500, color: C.muted, track: '1.6px', align: 'center' })
  }

  const frC = [398, 658] // first-round card centres (per half)
  const box = (x: number, cy: number, game: Game, w = CARD_W, rowH = ROW): Box => ({ x, y: cy - rowH, w, game, rowH })
  const fr = rounds[0], qf = rounds[1], sf = rounds[2], fin = rounds[3][0]
  // Game order within each round follows the bracket: [0,1] left half, [2,3] right half.
  const frBox = fr.map((g, i) => box(i < 2 ? colX(0) : rColX(0), frC[i % 2], g))
  // Quarterfinal: bye team on top; the first-round winner's row lines up with its game.
  const qfBox = qf.map((g, i) => box(i < 2 ? colX(1) : rColX(1), frC[i % 2] - ROW / 2, g))
  const sfC = (frC[0] + frC[1]) / 2 - ROW / 2
  const sfBox = sf.map((g, i) => box(i === 0 ? colX(2) : rColX(2), sfC, g))
  const finW = 300, finRow = 46
  const finBox = box(W / 2 - finW / 2, sfC, fin, finW, finRow)

  // Champion path: every game the champion won.
  const champGames = new Set(rounds.flat().filter(g => g.winner.team_id === champion.team_id))
  const links: [Box, Box, boolean][] = [
    ...frBox.map((b, i) => [b, qfBox[i], false] as [Box, Box, boolean]),
    ...qfBox.map((b, i) => [b, sfBox[i < 2 ? 0 : 1], i % 2 === 0] as [Box, Box, boolean]),
    [sfBox[0], finBox, true], [sfBox[1], finBox, false],
  ]
  for (const gold of [false, true]) for (const [a, b, top] of links) if (champGames.has(a.game) === gold) connect(ctx, a, b, top, gold)
  for (const b of [...frBox, ...qfBox, ...sfBox]) matchup(ctx, logos, b, champion)

  // Centre column: champion panel, title game, title odds
  const cx = W / 2
  label(ctx, 'NATIONAL CHAMPIONSHIP', cx, finBox.y - 16, { size: 12, color: C.navy, track: '2.4px', align: 'center' })
  matchup(ctx, logos, finBox, champion, true)

  const cw = 300, chY = 236, chH = 180
  ctx.save()
  ctx.shadowColor = 'rgba(20, 34, 63, 0.25)'
  ctx.shadowBlur = 22
  ctx.shadowOffsetY = 8
  rounded(ctx, cx - cw / 2, chY, cw, chH, 8)
  ctx.fillStyle = C.navyDeep
  ctx.fill()
  ctx.restore()
  ctx.save()
  rounded(ctx, cx - cw / 2, chY, cw, chH, 8)
  ctx.clip()
  const glow = ctx.createRadialGradient(cx, chY + 20, 10, cx, chY + 20, 220)
  glow.addColorStop(0, 'rgba(184, 137, 58, 0.30)')
  glow.addColorStop(1, 'rgba(184, 137, 58, 0)')
  ctx.fillStyle = glow
  ctx.fillRect(cx - cw / 2, chY, cw, chH)
  ctx.fillStyle = C.gold
  ctx.fillRect(cx - cw / 2, chY + chH - 4, cw, 4)
  ctx.restore()
  label(ctx, 'PROJECTED CHAMPION', cx, chY + 27, { size: 11, color: '#dcc491', track: '2.6px', align: 'center' })
  ctx.beginPath()
  ctx.arc(cx, chY + 72, 32, 0, Math.PI * 2)
  ctx.fillStyle = C.cream
  ctx.fill()
  ctx.strokeStyle = C.gold
  ctx.lineWidth = 2
  ctx.stroke()
  drawLogo(ctx, logos.get(champion.team_id), champion.team, cx, chY + 72, 44)
  ctx.font = `800 28px ${DISPLAY}`
  spacing(ctx, '-0.6px')
  ctx.fillStyle = C.cream
  ctx.textAlign = 'center'
  ctx.fillText(fit(ctx, champion.team, cw - 32), cx, chY + 136)
  spacing(ctx, '0px')
  label(ctx, `NO. ${champion.seed} SEED · ${pct1(champion.title).toUpperCase()} TITLE ODDS`, cx, chY + 160, { size: 11, weight: 500, color: '#c5cfe0', track: '1.6px', align: 'center' })

  // Title odds across all simulations, to keep the "most likely path" honest.
  const toY = finBox.y + finRow * 2 + 34
  const toH = 36 + titleOdds.length * 32 + 8
  card(ctx, cx - cw / 2, toY, cw, toH)
  panelHead(ctx, cx - cw / 2, toY, cw, 'TITLE ODDS', 'ALL SIMS')
  const maxT = Math.max(...titleOdds.map(t => t.title), 0.01)
  titleOdds.forEach((t, j) => {
    const mid = toY + 36 + 4 + j * 32 + 16
    if (j) { ctx.fillStyle = C.line; ctx.fillRect(cx - cw / 2 + 12, mid - 16, cw - 24, 1) }
    drawLogo(ctx, logos.get(t.team_id), t.team, cx - cw / 2 + 26, mid, 20)
    ctx.font = `500 13.5px ${BODY}`
    ctx.fillStyle = C.ink
    ctx.textAlign = 'left'
    ctx.fillText(fit(ctx, t.team, 108), cx - cw / 2 + 44, mid + 4.5)
    const bx = cx - cw / 2 + 158, bw = 72
    rounded(ctx, bx, mid - 3.5, bw, 7, 3.5); ctx.fillStyle = C.goldSoft; ctx.fill()
    rounded(ctx, bx, mid - 3.5, Math.max(3.5, bw * t.title / maxT), 7, 3.5); ctx.fillStyle = C.gold; ctx.fill()
    ctx.font = `600 12.5px ${MONO}`
    ctx.fillStyle = C.ink
    ctx.textAlign = 'right'
    ctx.fillText(pct1(t.title), cx + cw / 2 - 12, mid + 4.5)
    ctx.textAlign = 'left'
  })

  // The field, seeds 1–12
  const fy = fieldY
  label(ctx, 'THE FIELD', pad, fy, { size: 12, color: C.navy, track: '2.4px' })
  label(ctx, 'SEEDS 1–4 EARN BYES  ·  GOLD = AUTOMATIC QUALIFIER', W - pad, fy, { size: 10.5, weight: 500, color: C.muted, track: '1.6px', align: 'right' })
  const chipGap = 8, chipW = (W - pad * 2 - chipGap * 11) / 12, chipY = fy + 16
  field.forEach((t, i) => {
    const x = pad + i * (chipW + chipGap)
    card(ctx, x, chipY, chipW, chipH, 5)
    if (t.autoBid) {
      ctx.save(); rounded(ctx, x, chipY, chipW, chipH, 5); ctx.clip()
      ctx.fillStyle = C.gold; ctx.fillRect(x, chipY, chipW, 3)
      ctx.restore()
    }
    const bye = t.seed <= 4
    rounded(ctx, x + 9, chipY + 12, 22, 19, 3)
    ctx.fillStyle = bye ? C.navy : C.cream
    ctx.fill()
    if (!bye) { ctx.strokeStyle = C.line; ctx.lineWidth = 1; ctx.stroke() }
    ctx.font = `600 11px ${MONO}`
    ctx.fillStyle = bye ? C.cream : C.ink2
    ctx.textAlign = 'center'
    ctx.fillText(String(t.seed), x + 20, chipY + 25.5)
    drawLogo(ctx, logos.get(t.team_id), t.team, x + 46, chipY + 21.5, 20)
    ctx.textAlign = 'left'
    ctx.font = `600 13px ${BODY}`
    ctx.fillStyle = C.ink
    ctx.fillText(fit(ctx, t.team, chipW - 64), x + 60, chipY + 26)
    label(ctx, AUTO_LABEL(t), x + 10, chipY + 47, { size: 9.5, weight: 600, color: t.autoBid ? C.goldInk : C.muted, track: '1.2px' })
  })

  // Footer
  ctx.fillStyle = C.line
  ctx.fillRect(pad, footY, W - pad * 2, 1)
  const run = asOfText(asOf)
  notes(ctx, [
    `Field: each conference’s likeliest champion, then cfbseedR’s 2026 rules (P4 champions, the top G6 team and a top-12 Notre Dame qualify; at-large bids by rank), ranked by playoff odds across ${sims(simulations)}.`,
    `Games: the higher power rating wins, with normal margins (SD ${model.sigma.toFixed(1)} pts) and +${model.hfa.toFixed(1)} pts for first-round hosts. A single most-likely path, not a forecast of certainty${run ? ` · games through ${run}` : ''}.`,
  ], pad, footY + 32, W - pad * 2 - 220)
  drawFooterBrand(ctx, W - pad, footY + 54)

  await savePng(canvas, `cfb-power-index-projected-playoff-${season}-${weekFile(week)}.png`)
  const all = new Set([...field, ...titleOdds].map(t => t.team_id))
  return { logos: [...all].filter(id => logos.has(id)).length, total: all.size }
}
