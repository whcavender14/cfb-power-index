// Fails the build (exit 1) if the CFPi+ page datasets in public/data/v2 are missing or inconsistent.
// Runs first in `pnpm build` and in `pnpm test` (tests/site-data.test.mjs). Contract: docs/website/DATA_CONTRACT_V2.md.
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('../public/data/v2/', import.meta.url))

export function validateSiteData(dir = root) {
  const errors = []
  const fail = msg => errors.push(msg)
  const read = name => {
    const path = `${dir}${name}`
    if (!existsSync(path)) { fail(`missing ${name}`); return null }
    try { return JSON.parse(readFileSync(path, 'utf8')) } catch (e) { fail(`${name}: invalid JSON (${e.message})`); return null }
  }
  const isNum = v => typeof v === 'number' && Number.isFinite(v)
  const nullableNum = (v, where) => { if (v !== null && !isNum(v)) fail(`${where}: expected number or null, got ${JSON.stringify(v)}`) }
  const prob = (v, where) => { nullableNum(v, where); if (isNum(v) && (v < 0 || v > 1)) fail(`${where}: probability ${v} outside [0,1]`) }
  const iso = (v, where, nullable = true) => { if (v === null && nullable) return; if (typeof v !== 'string' || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(v)) fail(`${where}: expected UTC timestamp, got ${JSON.stringify(v)}`) }

  const index = read('index.json'), teams = read('teams.json'), games = read('games.json'), playoff = read('playoff.json')
  const history = read('history.json'), changes = read('changes.json'), conferences = read('conferences.json')
  if (!index || !teams || !games || !playoff || !history || !changes || !conferences) return errors

  for (const [name, doc] of [['index', index], ['teams', teams], ['games', games], ['playoff', playoff], ['history', history], ['changes', changes], ['conferences', conferences]]) {
    const m = doc.meta
    if (!m || m.schema_version !== 2) { fail(`${name}.json: meta.schema_version must be 2`); continue }
    if (!Number.isInteger(m.season)) fail(`${name}.json: meta.season`)
    if (m.ratings_week !== null && !Number.isInteger(m.ratings_week)) fail(`${name}.json: meta.ratings_week`)
    iso(m.ratings_updated_at, `${name}.json meta.ratings_updated_at`); iso(m.sim_updated_at, `${name}.json meta.sim_updated_at`); iso(m.exported_at, `${name}.json meta.exported_at`, false)
    if (!['available', 'unavailable'].includes(m.sim_status)) fail(`${name}.json: meta.sim_status`)
    if (m.exported_at !== index.meta.exported_at) fail(`${name}.json was exported separately from index.json (mixed update)`)
  }
  const meta = index.meta

  // Team directory
  const dirIds = new Set(), slugs = new Set()
  for (const t of teams.teams ?? []) {
    if (typeof t.team_id !== 'string' || dirIds.has(t.team_id)) fail(`teams.json: bad or duplicate team_id ${t.team_id}`)
    if (typeof t.slug !== 'string' || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(t.slug) || slugs.has(t.slug)) fail(`teams.json: bad or duplicate slug ${t.slug}`)
    if (typeof t.team !== 'string' || !t.team) fail(`teams.json: team ${t.team_id} has no name`)
    if (t.logo !== null && !String(t.logo).startsWith('https://')) fail(`teams.json: non-https logo for ${t.team_id}`)
    dirIds.add(t.team_id); slugs.add(t.slug)
    if (!existsSync(`${dir}team/${t.slug}.json`)) fail(`missing team/${t.slug}.json`)
  }
  if (dirIds.size < 100) fail(`teams.json: only ${dirIds.size} teams`)
  for (const f of existsSync(`${dir}team/`) ? readdirSync(`${dir}team/`) : []) if (f.endsWith('.json') && !slugs.has(f.slice(0, -5))) fail(`team/${f}: no team in teams.json has this slug (stale file)`)

  // Rankings
  const rows = index.teams ?? []
  if (rows.length !== dirIds.size) fail(`index.json has ${rows.length} teams, teams.json has ${dirIds.size}`)
  const ranks = []
  for (const r of rows) {
    const w = `index.json ${r.team_id}`
    if (!dirIds.has(r.team_id)) fail(`${w}: not in teams.json`)
    for (const k of ['power', 'off', 'def', 'rating_change', 'proj_wins', 'preseason_power']) nullableNum(r[k], `${w}.${k}`)
    for (const k of ['p_playoff', 'p_conf', 'p_champ']) prob(r[k], `${w}.${k}`)
    if (r.rank !== null) { if (!Number.isInteger(r.rank)) fail(`${w}.rank`); ranks.push(r.rank) }
    if (r.rank_change !== null && r.rank_change !== r.rank_prev - r.rank) fail(`${w}: rank_change inconsistent`)
    if ((r.power === null) !== (r.rank === null)) fail(`${w}: rank without power or power without rank`)
    if (isNum(r.power) && isNum(r.off) && isNum(r.def) && Math.abs(r.power - (r.off - r.def)) > 0.01) fail(`${w}: power != off - def`)
  }
  ranks.sort((a, b) => a - b)
  if (ranks.some((r, i) => r !== i + 1)) fail('index.json: ranks are not 1..N without gaps')
  const byRank = rows.filter(r => r.rank !== null).sort((a, b) => a.rank - b.rank)
  for (let i = 1; i < byRank.length; i++) if (byRank[i].power > byRank[i - 1].power + 1e-9) fail(`index.json: rank ${byRank[i].rank} has higher power than rank ${byRank[i - 1].rank}`)
  if (meta.movement_compared_to_week === null && rows.some(r => r.rank_change !== null)) fail('index.json: movement present without a comparison week')

  // Simulations
  if (meta.sim_status === 'available') {
    if (!Number.isInteger(meta.sim_count) || meta.sim_count < 100) fail('meta.sim_count')
    const pt = playoff.teams ?? []
    const sum = k => pt.reduce((s, t) => s + t[k], 0)
    if (Math.abs(sum('p_playoff') - 12) > 1e-3) fail(`playoff.json: playoff probabilities sum to ${sum('p_playoff')}, expected 12`)
    if (Math.abs(sum('p_champ') - 1) > 1e-3) fail(`playoff.json: title probabilities sum to ${sum('p_champ')}, expected 1`)
    if (Math.abs(sum('p_bye') - 4) > 1e-3) fail(`playoff.json: bye probabilities sum to ${sum('p_bye')}, expected 4`)
    for (const t of pt) {
      const w = `playoff.json ${t.team_id}`
      for (const k of ['p_playoff', 'p_auto', 'p_at_large', 'p_bye', 'p_host', 'p_qf', 'p_sf', 'p_final', 'p_champ', 'p_conf']) prob(t[k], `${w}.${k}`)
      if (Math.abs(t.p_auto + t.p_at_large - t.p_playoff) > 2e-4) fail(`${w}: auto + at-large != playoff`)
      if (!(t.p_playoff + 1e-9 >= t.p_qf && t.p_qf + 1e-9 >= t.p_sf && t.p_sf + 1e-9 >= t.p_final && t.p_final + 1e-9 >= t.p_champ)) fail(`${w}: round probabilities not monotone`)
      if (!Array.isArray(t.seed_dist) || t.seed_dist.length !== 12) fail(`${w}: seed_dist`)
      else if (Math.abs(t.seed_dist.reduce((a, b) => a + b, 0) - t.p_playoff) > 2e-3) fail(`${w}: seed_dist does not sum to p_playoff`)
      const r = rows.find(x => x.team_id === t.team_id)
      if (r && r.p_playoff !== null && Math.abs(r.p_playoff - t.p_playoff) > 1e-6) fail(`${w}: disagrees with index.json`)
    }
    const f = playoff.representative_field
    if (!f || f.seeds?.length !== 12) fail('playoff.json: representative_field must have 12 seeds')
    else {
      if (f.seeds.map(s => s.seed).join() !== '1,2,3,4,5,6,7,8,9,10,11,12') fail('playoff.json: field seeds are not 1..12')
      if (new Set(f.seeds.map(s => s.team_id)).size !== 12) fail('playoff.json: duplicate team in field')
    }
  }

  // Games
  const ids = new Set()
  for (const g of games.games ?? []) {
    const w = `games.json ${g.game_id}`
    if (ids.has(g.game_id)) fail(`${w}: duplicate`); ids.add(g.game_id)
    iso(g.kickoff, `${w}.kickoff`, false)
    if (!['final', 'scheduled'].includes(g.status)) fail(`${w}.status`)
    if (g.status === 'final' && (!isNum(g.home_points) || !isNum(g.away_points))) fail(`${w}: final without score`)
    if (g.status === 'final' && (g.spread_home !== null || g.win_prob_home !== null)) fail(`${w}: completed game carries a projection`)
    if (g.status === 'scheduled' && (g.home_points !== null || g.away_points !== null)) fail(`${w}: scheduled game has a score`)
    prob(g.win_prob_home, `${w}.win_prob_home`); prob(g.sim_home_win, `${w}.sim_home_win`)
    if (g.quality !== null && !(Number.isInteger(g.quality) && g.quality >= 0 && g.quality <= 100)) fail(`${w}.quality`)
    if (g.home_fbs && !dirIds.has(g.home_id)) fail(`${w}: FBS home team not in directory`)
    if (g.away_fbs && !dirIds.has(g.away_id)) fail(`${w}: FBS away team not in directory`)
  }
  if (meta.sim_status === 'available' && ids.size === 0) fail('games.json is empty')

  // Rating history: points ordered, sources known, current point equals index.json, ranks consistent per point.
  const pts = history.points ?? []
  const SOURCES = ['preseason', 'reconstructed', 'published']
  pts.forEach((p, i) => {
    if (!SOURCES.includes(p.source)) fail(`history.json point ${i}: unknown source ${p.source}`)
    if (p.source === 'preseason' ? p.week !== null : !Number.isInteger(p.week)) fail(`history.json point ${i}: week`)
    if (i > 1 && !(p.week > pts[i - 1].week)) fail('history.json: weeks not strictly increasing')
  })
  const last = pts.length - 1
  if (meta.ratings_week !== null && (last < 0 || pts[last].week !== meta.ratings_week || pts[last].source !== 'published')) fail('history.json: last point is not the published current week')
  for (const r of rows) {
    const h = history.teams?.[r.team_id]
    if (!h) { fail(`history.json: no series for ${r.team_id}`); continue }
    for (const k of ['power', 'rank', 'off', 'def']) if (!Array.isArray(h[k]) || h[k].length !== pts.length) fail(`history.json ${r.team_id}.${k}: length`)
    if (last >= 0 && (h.power[last] !== r.power || h.rank[last] !== r.rank)) fail(`history.json ${r.team_id}: current point differs from index.json`)
    const pi = pts.findIndex(p => p.week === meta.movement_compared_to_week)
    if (meta.movement_compared_to_week !== null && pi >= 0 && r.rank_prev !== h.rank[pi]) fail(`history.json ${r.team_id}: movement does not use the history's previous week`)
  }
  for (let i = 0; i < pts.length; i++) {
    const rk = rows.map(r => history.teams?.[r.team_id]?.rank?.[i]).filter(v => v !== null && v !== undefined).sort((a, b) => a - b)
    if (rk.some((v, j) => v !== j + 1)) fail(`history.json point ${i}: ranks are not 1..N`)
  }
  if (meta.movement_compared_to_week !== null && meta.movement_source !== pts.find(p => p.week === meta.movement_compared_to_week)?.source) fail('index.json: movement_source disagrees with history.json')

  // Record distributions (team files): counts sum to the simulation count, mean wins = projected wins.
  if (meta.sim_status === 'available') for (const r of rows) {
    const slug = teams.teams.find(t => t.team_id === r.team_id)?.slug
    const tf = slug && read(`team/${slug}.json`)
    if (!tf) continue
    const rd = tf.record_dist ?? []
    const n = rd.reduce((a, x) => a + x.count, 0)
    if (n !== meta.sim_count) fail(`team/${slug}.json: record counts sum to ${n}, expected ${meta.sim_count}`)
    const mean = rd.reduce((a, x) => a + x.wins * x.count, 0) / n
    if (Math.abs(mean - r.proj_wins) > 1e-4) fail(`team/${slug}.json: mean wins ${mean} != projected wins ${r.proj_wins}`)
    // Statistical leaders: stamped with the ratings week, fixed categories, sorted; counts non-negative.
    const L = tf.leaders
    if (L) {
      if (L.through_week !== meta.ratings_week) fail(`team/${slug}.json: leaders cover week ${L.through_week}, ratings week ${meta.ratings_week}`)
      const RULES = { passing: ['passing_yds', 1], rushing: ['rushing_yds', 2], receiving: ['receiving_yds', 3], sacks: ['defensive_sacks', 3], interceptions: ['interceptions_int', 1] }
      for (const [cat, [key, max]] of Object.entries(RULES)) {
        const list = L[cat] ?? []
        if (!Array.isArray(list) || list.length > max) fail(`team/${slug}.json: leaders.${cat}`)
        list.forEach((p, i) => {
          if (typeof p.player !== 'string' || !p.player) fail(`team/${slug}.json: leaders.${cat} player name`)
          for (const [k, v] of Object.entries(p)) if (!['athlete_id', 'player', 'position'].includes(k) && !(Number.isFinite(v) && (v >= 0 || k.endsWith('_yds')))) fail(`team/${slug}.json: leaders.${cat}.${k}`)  // yardage can be negative (e.g. an interception returned for a loss)
          if (!(p[key] > 0)) fail(`team/${slug}.json: leaders.${cat} lists a player with no ${key}`)
          if (i && p[key] > list[i - 1][key]) fail(`team/${slug}.json: leaders.${cat} not sorted`)
        })
      }
    }
    const wd = tf.wins_dist ?? []
    if (Math.abs(wd.reduce((a, b) => a + b, 0) - 1) > 2e-3) fail(`team/${slug}.json: wins_dist does not sum to 1`)
  }

  // Conferences: every FBS team in exactly one group, expected playoff teams = sum of member probabilities.
  const seen = new Map()
  for (const c of conferences.conferences ?? []) {
    if (!Array.isArray(c.team_ids)) { fail(`conferences.json ${c.name}: team_ids must be an array`); continue }
    for (const id of c.team_ids) { if (seen.has(id)) fail(`conferences.json: ${id} in two groups`); seen.set(id, c.name) }
    const dirConf = new Set((c.team_ids ?? []).map(id => teams.teams.find(t => t.team_id === id)?.conference))
    if (dirConf.size !== 1 || !dirConf.has(c.name)) fail(`conferences.json ${c.name}: membership disagrees with teams.json`)
    if (meta.sim_status === 'available') {
      const s = (c.team_ids ?? []).reduce((a, id) => a + (rows.find(r => r.team_id === id)?.p_playoff ?? 0), 0)
      if (Math.abs(s - c.exp_playoff) > 1e-3) fail(`conferences.json ${c.name}: exp_playoff ${c.exp_playoff} != member sum ${s}`)
    }
  }
  if (seen.size !== dirIds.size) fail(`conferences.json covers ${seen.size} of ${dirIds.size} teams`)

  // Scenario file: decodes to the stated layout and, with no picks, reproduces the published odds.
  if (meta.sim_status === 'available') {
    const sc = read('scenario.json')
    if (sc) {
      if (sc.meta?.exported_at !== meta.exported_at) fail('scenario.json was exported separately from index.json (mixed update)')
      const bytes = Buffer.from(sc.data ?? '', 'base64')
      const n = sc.n, G = sc.game_ids?.length ?? 0, T = sc.team_ids?.length ?? 0, nb = Math.ceil(n / 8)
      if (n !== meta.sim_count) fail('scenario.json: n differs from sim_count')
      if (bytes.length !== G * nb + 3 * T * n) fail(`scenario.json: ${bytes.length} bytes, layout needs ${G * nb + 3 * T * n}`)
      else {
        const scheduled = new Set((games.games ?? []).filter(g => g.status === 'scheduled').map(g => g.game_id))
        if (G !== scheduled.size || sc.game_ids.some(id => !scheduled.has(id))) fail('scenario.json: games differ from the scheduled games in games.json')
        const base = G * nb
        for (const pt of playoff.teams ?? []) {
          const t = sc.team_ids.indexOf(pt.team_id)
          if (t < 0) { fail(`scenario.json: team ${pt.team_id} missing`); continue }
          let po = 0, w = 0, ch = 0, cf = 0
          for (let s = 0; s < n; s++) { if (bytes[base + t * n + s]) po++; w += bytes[base + T * n + t * n + s]; const f = bytes[base + 2 * T * n + t * n + s]; if (f & 8) cf++; if ((f & 7) === 5) ch++ }
          if (Math.abs(po / n - pt.p_playoff) > 1e-4 || Math.abs(w / n - pt.proj_wins) > 1e-4 || Math.abs(cf / n - pt.p_conf) > 1e-4 || Math.abs(ch / n - pt.p_champ) > 1e-4) fail(`scenario.json: team ${pt.team_id} does not reproduce playoff.json`)
        }
        for (const g of games.games ?? []) if (g.status === 'scheduled' && g.sim_home_win != null) {
          const i = sc.game_ids.indexOf(g.game_id); let c = 0
          for (let s = 0; s < n; s++) if (bytes[i * nb + (s >> 3)] & (1 << (s & 7))) c++
          if (Math.abs(c / n - g.sim_home_win) > 1e-4) fail(`scenario.json: game ${g.game_id} home wins ${c / n} != sim_home_win ${g.sim_home_win}`)
        }
      }
    }
  }

  // Resume ranking: ranks 1..N in the approved order (SOR desc, losses asc, schedule played desc, team id asc).
  const resume = read('resume.json')
  if (resume) {
    if (resume.meta?.exported_at !== meta.exported_at) fail('resume.json was exported separately from index.json (mixed update)')
    const rr = (resume.teams ?? []).filter(t => t.resume_rank !== null).sort((a, b) => a.resume_rank - b.resume_rank)
    if (rr.some((t, i) => t.resume_rank !== i + 1)) fail('resume.json: resume ranks are not 1..N')
    for (let i = 1; i < rr.length; i++) {
      const a = rr[i - 1], b = rr[i]
      const key = t => [-t.sor, t.losses, -t.sos_played, Number(t.team_id)]
      const ka = key(a), kb = key(b); const c = ka.findIndex((v, j) => v !== kb[j])
      if (c >= 0 && ka[c] > kb[c]) fail(`resume.json: ${a.team_id} ranked ahead of ${b.team_id} against the tie-break order`)
    }
    for (const t of resume.teams ?? []) {
      const r = rows.find(x => x.team_id === t.team_id)
      if (r && (r.resume_rank !== t.resume_rank || r.rank !== t.predictive_rank)) fail(`resume.json ${t.team_id}: ranks disagree with index.json`)
    }
  }

  // What changed: only when a previous week exists, and it must be the movement week.
  if (changes.compared_to_week !== meta.movement_compared_to_week) fail('changes.json: compared week differs from index movement week')
  for (const c of changes.teams ?? []) {
    if (!dirIds.has(c.team_id)) fail(`changes.json: unknown team ${c.team_id}`)
    for (const g of c.games ?? []) if (typeof g.text !== 'string' || !g.text) fail(`changes.json ${c.team_id}: game without text`)
  }
  return errors
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const errors = validateSiteData()
  if (errors.length) {
    console.error(`Site data validation failed (${errors.length} problem${errors.length === 1 ? '' : 's'}):`)
    for (const e of errors.slice(0, 50)) console.error(`  - ${e}`)
    process.exit(1)
  }
  console.log('Site data valid.')
}
