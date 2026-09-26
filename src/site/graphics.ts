// The shareable graphics (the playoff bracket download is ./bracketPng.ts). Each takes data the page already loaded and returns when the PNG is saved.
import type { ChangesDoc, Game, Meta, PlayoffDoc, TeamMeta, TeamRow } from './data'
import { bar, COLORS as K, frame, INNER, LEFT, logo, logosFor, move, pct, render, signed, table, teamCell, text, type Col } from './share'

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

