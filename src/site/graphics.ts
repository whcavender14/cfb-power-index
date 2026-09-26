// The six shareable graphics. Each takes data the page already loaded and returns when the PNG is saved.
import type { ChangesDoc, Game, HistoryDoc, Meta, PlayoffDoc, TeamMeta, TeamRow } from './data'
import { bar, COLORS as K, frame, INNER, LEFT, logo, logosFor, move, pct, render, SERIES, signed, table, teamCell, text, type Col } from './share'

type Dir = Map<string, TeamMeta>
const file = (meta: Meta, name: string) => `cfpi-${name}-${meta.season}-wk${String(meta.ratings_week ?? 0).padStart(2, '0')}.png`
const nm = (dir: Dir, id: string, fallback = '') => dir.get(id)?.team ?? fallback
const rec = (r: TeamRow) => r.wins == null ? '—' : `${r.wins}–${r.losses}`
const H = (rows: number, rowH = 44, extra = 0) => 222 + 28 + rows * rowH + 120 + extra

export async function top25Png(meta: Meta, rows: TeamRow[], dir: Dir) {
  const top = rows.filter(r => r.rank != null && r.rank <= 25).sort((a, b) => a.rank! - b.rank!)
  const logos = await logosFor(top.map(r => r.team_id), dir)
  const cols: Col<TeamRow>[] = [
    { label: 'Rk', w: 70, draw: (c, r, x, y) => text(c, String(r.rank), x + 4, y + 6, { size: 18, weight: 700 }) },
    { label: 'Team', w: 470, draw: (c, r, x, y, w) => teamCell(c, logos, r.team_id, nm(dir, r.team_id), dir.get(r.team_id)?.conference ?? null, x, y, w) },
    { label: 'Record', w: 130, align: 'right', draw: (c, r, x, y, w) => text(c, rec(r), x + w - 8, y + 5.5, { size: 16, align: 'right' }) },
    { label: 'CFPi+', w: 150, align: 'right', draw: (c, r, x, y, w) => text(c, signed(r.power), x + w - 8, y + 5.5, { size: 17, weight: 700, align: 'right' }) },
    { label: 'Rating Δ', w: 138, align: 'right', draw: (c, r, x, y, w) => text(c, signed(r.rating_change), x + w - 8, y + 5.5, { size: 15, color: K.muted, align: 'right' }) },
    { label: 'Move', w: 130, align: 'right', draw: (c, r, x, y, w) => move(c, r.rank_change, x, y, w) },
  ]
  await render(file(meta, 'top25'), H(top.length, 40, 20), ctx => {
    const t = frame(ctx, H(top.length, 40, 20), 'CFPi+ Top 25', 'Power ratings: points better than an average FBS team on a neutral field.', meta)
    const end = table(ctx, t, cols, top, 40)
    if (meta.movement_compared_to_week != null) text(ctx, `Move and rating Δ vs Week ${meta.movement_compared_to_week}${meta.movement_source === 'reconstructed' ? ' (reconstructed)' : ''}.`, LEFT, end + 30, { size: 13, color: K.muted })
  })
}

export async function gamesPng(meta: Meta, games: Game[], dir: Dir, label: string) {
  const shown = games.filter(g => g.status === 'scheduled' && g.spread_home != null).slice(0, 30)
  const more = games.filter(g => g.status === 'scheduled' && g.spread_home != null).length - shown.length
  const logos = await logosFor(shown.flatMap(g => [g.home_id, g.away_id]), dir)
  const fav = (g: Game) => g.spread_home! >= 0 ? { id: g.home_id, name: g.home_team, m: g.spread_home!, p: g.win_prob_home! } : { id: g.away_id, name: g.away_team, m: -g.spread_home!, p: 1 - g.win_prob_home! }
  const cols: Col<Game>[] = [
    { label: 'Matchup', w: 560, draw: (c, g, x, y) => {
      logo(c, logos, g.away_id, g.away_team, x + 14, y, 24); text(c, g.away_team, x + 32, y + 5.5, { size: 15, weight: 600, max: 210 })
      text(c, g.neutral ? 'vs' : 'at', x + 262, y + 5.5, { size: 13, color: K.muted, align: 'center' })
      logo(c, logos, g.home_id, g.home_team, x + 292, y, 24); text(c, g.home_team, x + 310, y + 5.5, { size: 15, weight: 600, max: 240 }) } },
    { label: 'Projection', w: 290, draw: (c, g, x, y) => { const f = fav(g); text(c, f.m < 0.05 ? 'Even' : `${f.name} by ${f.m.toFixed(1)}`, x, y + 5.5, { size: 15, max: 280 }) } },
    { label: 'Win prob.', w: 130, align: 'right', draw: (c, g, x, y, w) => text(c, pct(fav(g).p), x + w - 8, y + 5.5, { size: 15, weight: 600, align: 'right' }) },
    { label: 'Quality', w: 108, align: 'right', draw: (c, g, x, y, w) => text(c, g.quality == null ? '—' : String(g.quality), x + w - 8, y + 5.5, { size: 15, color: K.muted, align: 'right' }) },
  ]
  const h = H(shown.length, 40, 30)
  await render(file(meta, 'games'), h, ctx => {
    const t = frame(ctx, h, `Game projections · ${label}`, 'CFPi+ projected margin and win probability for each game. Not betting advice.', meta)
    const end = table(ctx, t, cols, shown, 40)
    text(ctx, more > 0 ? `${more} more game${more === 1 ? '' : 's'} on the site. Quality 0–100 combines both teams' strength and how close the game projects.` : 'Quality 0–100 combines both teams’ strength and how close the game projects.', LEFT, end + 30, { size: 13, color: K.muted })
  })
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
    { label: 'Avg seed', w: 118, align: 'right', draw: (c, r, x, y, w) => text(c, r.mean_seed == null ? '—' : r.mean_seed.toFixed(1), x + w - 8, y + 5.5, { size: 15, color: K.muted, align: 'right' }) },
  ]
  const h = H(rows.length, 40, 20)
  await render(file(doc.meta, 'cfp-odds'), h, ctx => {
    const t = frame(ctx, h, 'College Football Playoff odds', `Share of ${doc.meta.sim_count?.toLocaleString() ?? ''} simulated seasons. Top 25 by playoff probability.`, doc.meta)
    const end = table(ctx, t, cols, rows, 40)
    text(ctx, '12-team field, 2026 rules: power-conference champions, the top-ranked team from the other conferences, at-large bids. Top four seeds get byes.', LEFT, end + 30, { size: 13, color: K.muted, max: INNER })
  })
}

export async function playoffFieldPng(doc: PlayoffDoc, dir: Dir) {
  const f = doc.representative_field
  if (!f) throw new Error('No projected field')
  const by = new Map(f.seeds.map(s => [s.seed, s]))
  const logos = await logosFor(f.seeds.map(s => s.team_id), dir)
  const h = 222 + 560 + 110
  await render(file(doc.meta, 'playoff-field'), h, ctx => {
    const t = frame(ctx, h, 'Projected playoff field', 'The most likely complete 12-team seeding across the simulated seasons.', doc.meta)
    const seedRow = (seed: number, x: number, y: number, w: number) => {
      const s = by.get(seed)!; const name = nm(dir, s.team_id)
      text(ctx, String(seed), x, y + 6, { size: 16, weight: 700, color: K.muted })
      logo(ctx, logos, s.team_id, name, x + 44, y, 30)
      text(ctx, name, x + 68, y + 6, { size: 17, weight: 600, max: w - 150 })
      text(ctx, s.bid === 'auto' ? 'Auto' : 'At-large', x + w - 12, y + 5, { size: 12.5, weight: 600, color: s.bid === 'auto' ? K.accent : K.muted, align: 'right' })
    }
    const card = (x: number, y: number, w: number, hh: number) => { ctx.beginPath(); ctx.roundRect(x, y, w, hh, 14); ctx.fillStyle = K.fill; ctx.fill() }
    // Byes
    card(LEFT, t, 330, 530)
    text(ctx, 'FIRST-ROUND BYES', LEFT + 20, t + 34, { size: 12, weight: 600, color: K.muted, track: '0.6px' })
    for (let s = 1; s <= 4; s++) seedRow(s, LEFT + 20, t + 76 + (s - 1) * 58, 300)
    // First round: 5v12, 8v9, 6v11, 7v10 with the bye team each winner meets
    const games: [number, number, number][] = [[8, 9, 1], [5, 12, 4], [7, 10, 2], [6, 11, 3]]
    const gx = LEFT + 360, gw = (INNER - 360 - 20) / 2
    games.forEach(([a, b, next], i) => {
      const x = gx + (i % 2) * (gw + 20), y = t + Math.floor(i / 2) * 280
      card(x, y, gw, 250)
      text(ctx, `FIRST ROUND · AT NO. ${a}`, x + 20, y + 34, { size: 12, weight: 600, color: K.muted, track: '0.6px' })
      seedRow(a, x + 20, y + 82, gw - 20)
      seedRow(b, x + 20, y + 140, gw - 20)
      text(ctx, `Winner plays No. ${next} ${nm(dir, by.get(next)!.team_id)}`, x + 20, y + 214, { size: 13.5, color: K.muted, max: gw - 40 })
    })
    text(ctx, `This exact seeding occurred in ${f.sims_with_identical_field} of ${doc.meta.sim_count?.toLocaleString()} simulated seasons; individual odds vary. Higher seed hosts the first round.`, LEFT, t + 590, { size: 13, color: K.muted, max: INNER })
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

export async function comparePng(meta: Meta, doc: HistoryDoc, series: { id: string; name: string; slot: number }[], dir: Dir) {
  const logos = await logosFor(series.map(s => s.id), dir)
  const pts = doc.points
  const h = 222 + 420 + 60 + series.length * 40 + 110
  await render(file(meta, 'compare'), h, ctx => {
    const t = frame(ctx, h, 'Rating history', series.map(s => s.name).join(' · '), meta)
    const x0 = LEFT + 50, x1 = LEFT + INNER - 150, y0 = t + 10, y1 = t + 380
    const vals = series.flatMap(s => doc.teams[s.id]?.power ?? []).filter((v): v is number => v != null)
    const lo = Math.floor(Math.min(0, ...vals) / 5) * 5, hi = Math.ceil(Math.max(0, ...vals) / 5) * 5
    // Same x axis as the page chart: preseason, then every week from Week 1; a week without a rating is a gap.
    const weeks = pts.filter(p => p.week != null).map(p => p.week as number)
    const firstW = weeks.length ? Math.min(1, ...weeks) : 0, lastW = weeks.length ? Math.max(...weeks) : 0
    const slotLabels: string[] = [...(pts.some(p => p.source === 'preseason') ? ['Pre'] : []), ...Array.from({ length: weeks.length ? lastW - firstW + 1 : 0 }, (_, k) => `Week ${firstW + k}`)]
    const slotOf = (i: number) => pts[i].week == null ? 0 : slotLabels.indexOf(`Week ${pts[i].week}`)
    const X = (i: number) => x0 + (slotLabels.length <= 1 ? 0 : (slotOf(i) / (slotLabels.length - 1)) * (x1 - x0))
    const Y = (v: number) => y1 - ((v - lo) / (hi - lo || 1)) * (y1 - y0)
    const step = hi - lo > 30 ? 10 : 5
    for (let v = lo; v <= hi; v += step) {
      ctx.fillStyle = v === 0 ? '#c7c7cc' : K.line; ctx.fillRect(x0, Y(v), x1 - x0, 1)
      text(ctx, v > 0 ? `+${v}` : v < 0 ? `−${-v}` : '0', x0 - 10, Y(v) + 4, { size: 12, color: K.muted, align: 'right' })
    }
    slotLabels.forEach((l, k) => text(ctx, l, x0 + (slotLabels.length <= 1 ? 0 : (k / (slotLabels.length - 1)) * (x1 - x0)), y1 + 26, { size: 12.5, color: K.muted, align: 'center' }))
    const ends: { y: number; s: (typeof series)[number] }[] = []
    for (const s of series) {
      const v = doc.teams[s.id]?.power ?? []; const col = SERIES[s.slot - 1]
      ctx.strokeStyle = col; ctx.lineWidth = 2.5; ctx.lineJoin = 'round'; ctx.beginPath()
      let open = false
      v.forEach((val, i) => { if (val == null || (i > 0 && slotOf(i) - slotOf(i - 1) > 1)) open = false; if (val == null) return; open ? ctx.lineTo(X(i), Y(val)) : ctx.moveTo(X(i), Y(val)); open = true })
      ctx.stroke()
      v.forEach((val, i) => {
        if (val == null) return
        ctx.beginPath(); ctx.arc(X(i), Y(val), 4.5, 0, Math.PI * 2)
        const hollow = pts[i].source !== 'published'
        ctx.fillStyle = hollow ? '#fff' : col; ctx.fill(); ctx.lineWidth = 2; ctx.strokeStyle = col; ctx.stroke()
      })
      const last = [...v].reverse().find(x => x != null)
      if (last != null) ends.push({ y: Y(last), s })
    }
    ends.sort((a, b) => a.y - b.y).forEach((e, i, arr) => { if (i && e.y - arr[i - 1].y < 18) e.y = arr[i - 1].y + 18; text(ctx, e.s.name, x1 + 14, e.y + 5, { size: 13.5, weight: 600, color: K.ink, max: 136 }) })
    // Legend table: current rating and rank, with the week-by-week values.
    let y = y1 + 70
    text(ctx, 'TEAM', LEFT, y, { size: 11.5, weight: 600, color: K.muted, track: '0.6px' })
    pts.forEach((p, i) => text(ctx, p.label.replace('Preseason', 'Pre').toUpperCase(), LEFT + 400 + i * 150, y, { size: 11.5, weight: 600, color: K.muted, align: 'right', track: '0.6px' }))
    for (const s of series) {
      y += 40; const v = doc.teams[s.id]
      ctx.beginPath(); ctx.arc(LEFT + 6, y - 5, 5, 0, Math.PI * 2); ctx.fillStyle = SERIES[s.slot - 1]; ctx.fill()
      logo(ctx, logos, s.id, s.name, LEFT + 32, y - 5, 22)
      text(ctx, s.name, LEFT + 50, y, { size: 15, weight: 600, max: 220 })
      pts.forEach((_, i) => text(ctx, v?.power[i] == null ? '—' : `${signed(v.power[i])}  No. ${v.rank[i]}`, LEFT + 400 + i * 150, y, { size: 14, align: 'right' }))
    }
    if (pts.some(p => p.source === 'reconstructed')) text(ctx, 'Hollow points: reconstructed weeks (the unchanged model re-run at each past cutoff; CFPi+ was not yet the published model).', LEFT, y + 38, { size: 13, color: K.muted, max: INNER })
  })
}
