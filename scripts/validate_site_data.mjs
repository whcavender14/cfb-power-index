// Fails the build (exit 1) if the CFPi+ page datasets in public/data/v2 are missing or inconsistent.
// Runs first in `pnpm build` and in `pnpm test` (tests/site-data.test.mjs). Contract: docs/website/DATA_CONTRACT_V2.md.
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { fileURLToPath, pathToFileURL } from 'node:url'

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
  // Home-page playoff swing: base equals the published playoff probability; win/lose average back to it.
  for (const [gid, sw] of Object.entries(index.top_swing ?? {})) {
    const g = (index.top_games ?? []).find(x => x.game_id === gid)
    if (!g) { fail(`index.json top_swing: ${gid} is not a featured game`); continue }
    for (const [side, id] of [['home', g.home_id], ['away', g.away_id]]) {
      const x = sw[side]; if (!x) continue
      const p = rows.find(r => r.team_id === id)?.p_playoff
      const n = x.n_win + x.n_lose
      if (n !== meta.sim_count) fail(`index.json top_swing ${gid} ${side}: ${n} seasons != sim_count`)
      if (p != null && Math.abs(x.base - p) > 1e-3) fail(`index.json top_swing ${gid} ${side}: base ${x.base} != p_playoff ${p}`)
      if (Math.abs((x.win * x.n_win + x.lose * x.n_lose) / n - x.base) > 2e-3) fail(`index.json top_swing ${gid} ${side}: win/lose do not average to base`)
    }
  }
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
    // Conference win odds: p_ge[k] = P(at least k conference wins) must start at 1, never rise, and sum to the expected wins.
    for (const t of c.standings ?? []) {
      const p = t.p_ge
      if (!c.team_ids.includes(t.team_id)) fail(`conferences.json ${c.name}: standings team ${t.team_id} is not a member`)
      if (!Array.isArray(p) || p.length !== t.conf_games + 1 || p[0] !== 1) { fail(`conferences.json ${c.name} ${t.team_id}: p_ge must have conf_games + 1 entries starting at 1`); continue }
      if (p.some((v, k) => v < 0 || v > 1 || (k > 0 && v > p[k - 1]))) fail(`conferences.json ${c.name} ${t.team_id}: p_ge must be non-increasing probabilities`)
      if (p.slice(0, t.conf_wins + 1).some(v => v !== 1)) fail(`conferences.json ${c.name} ${t.team_id}: wins already secured must have probability 1`)
      if (p.slice(t.conf_games - t.conf_losses + 1).some(v => v !== 0)) fail(`conferences.json ${c.name} ${t.team_id}: unreachable win totals must have probability 0`)
      const ev = p.slice(1).reduce((a, v) => a + v, 0)
      if (Math.abs(ev - t.avg_wins) > 1e-3) fail(`conferences.json ${c.name} ${t.team_id}: p_ge sums to ${ev.toFixed(4)}, not avg_wins ${t.avg_wins}`)
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
      const packed = sc.format === 2, per = packed ? 1 : 3
      if (bytes.length !== G * nb + per * T * n) fail(`scenario.json: ${bytes.length} bytes, layout needs ${G * nb + per * T * n}`)
      else {
        const scheduled = new Set((games.games ?? []).filter(g => g.status === 'scheduled').map(g => g.game_id))
        if (G !== scheduled.size || sc.game_ids.some(id => !scheduled.has(id))) fail('scenario.json: games differ from the scheduled games in games.json')
        const base = G * nb
        const sched = sc.team_ids.map(() => [])   // format 2: each team's remaining games as [index, 1 if home]
        if (packed) { sc.game_home.forEach((t, g) => { if (t >= 0) sched[t].push([g, 1]) }); sc.game_away.forEach((t, g) => { if (t >= 0) sched[t].push([g, 0]) }) }
        for (const pt of playoff.teams ?? []) {
          const t = sc.team_ids.indexOf(pt.team_id)
          if (t < 0) { fail(`scenario.json: team ${pt.team_id} missing`); continue }
          let po = 0, w = 0, ch = 0, cf = 0
          for (let s = 0; s < n; s++) {
            if (packed) {
              const p = bytes[base + t * n + s]; if (p & 15) po++; if (p & 16) cf++; if ((p >> 5) === 5) ch++
              w += sc.known_wins[t]
              for (const [g, home] of sched[t]) if (((bytes[g * nb + (s >> 3)] >> (s & 7)) & 1) === home) w++
            }
            else { if (bytes[base + t * n + s]) po++; w += bytes[base + T * n + t * n + s]; const f = bytes[base + 2 * T * n + t * n + s]; if (f & 8) cf++; if ((f & 7) === 5) ch++ }
          }
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

  // /players/ leaderboards (players/leaders/<category>.json; R/publish/player_leaders.R): same export, ratings week,
  // well-formed rows, qualifier flags that follow from the published counts, and a profile file for every player.
  const LEADER_CATS = ['passing', 'rushing', 'receiving', 'defense', 'kicking', 'punting']
  const SIGNED = new Set(['passing_yds', 'rushing_yds', 'receiving_yds', 'interceptions_yds', 'ppa_avg', 'ppa_total', 'rating'])   // the NCAA passer rating formula goes negative
  for (const cat of LEADER_CATS) {
    const name = `players/leaders/${cat}.json`, L = read(name)
    if (!L) continue
    if (L.meta?.schema_version !== 2 || L.meta?.exported_at !== meta.exported_at) fail(`${name}: meta must come from the same export as index.json`)
    if (L.category !== cat || !Array.isArray(L.rows)) { fail(`${name}: category or rows`); continue }
    if (L.through_week === null) { if (typeof L.unavailable !== 'string' || L.rows.length) fail(`${name}: an unavailable board must say why and list no players`); continue }
    if (L.through_week !== meta.ratings_week) fail(`${name}: covers week ${L.through_week}, ratings week ${meta.ratings_week}`)
    const cols = L.columns ?? [], at = k => cols.indexOf(k)
    if (cols.slice(0, 7).join() !== 'athlete_id,player,team_id,position,class,q,rs' || at(L.rank_stat) < 0) { fail(`${name}: columns`); continue }
    const ids = new Set(), qs = L.qualifier
    L.rows.forEach((r, i) => {
      const where = `${name} row ${i}`
      if (!Array.isArray(r) || r.length !== cols.length) { fail(`${where}: expected ${cols.length} values`); return }
      const [id, player, team, , cls, q] = r
      if (typeof id !== 'string' || !/^\d+$/.test(id) || ids.has(id)) fail(`${where}: bad or duplicate athlete_id ${id}`)
      ids.add(id)
      if (typeof player !== 'string' || !player) fail(`${where}: player name`)
      if (!dirIds.has(team)) fail(`${where}: team ${team} is not an FBS team`)
      if (cls !== null && !(Number.isInteger(cls) && cls >= 1 && cls <= 6)) fail(`${where}: class ${cls}`)
      if (![0, 1].includes(r[6]) || (r[6] && !(cls >= 1 && cls <= 4))) fail(`${where}: rs flag (0 or 1)`)
      cols.slice(7).forEach((k, j) => { const v = r[j + 7]; if (v === null) return; if (!isNum(v) || (v < 0 && !SIGNED.has(k))) fail(`${where}: ${k} = ${JSON.stringify(v)}`) })
      if (qs) {
        const games = L.team_games?.[team] ?? 0
        if (q !== (games > 0 && r[at(qs.stat)] >= qs.per_team_game * games)) fail(`${where}: qualified flag disagrees with ${qs.stat} and ${games} team games`)
      } else if (q !== null) fail(`${where}: no qualifier for ${cat}, so q must be null`)
      if (i && r[at(L.rank_stat)] > L.rows[i - 1][at(L.rank_stat)]) fail(`${name}: not sorted by ${L.rank_stat}`)
      if (!existsSync(`${dir}player/${id}.json`)) fail(`${where}: no player/${id}.json for the player modal`)
    })
    if (L.ppa && !L.ppa.available && at('ppa_avg') >= 0 && L.rows.some(r => r[at('ppa_avg')] !== null || r[at('ppa_total')] !== null)) fail(`${name}: PPA published although the pull does not line up (${L.ppa.reason})`)
  }

  // Recruiting (recruiting/*.json; R/publish/recruiting.R): CFBD rows as published, and every count, rank and share
  // that R derived from them agrees with the rows.
  const dash = existsSync(`${dir}recruiting/dashboard.json`) ? read('recruiting/dashboard.json') : null
  if (dash) {
    const cards = read('recruiting/cards.json')
    for (const [n, d] of [['dashboard', dash], ['cards', cards]]) if (d && (d.meta?.schema_version !== 2 || d.meta?.exported_at !== meta.exported_at)) fail(`recruiting/${n}.json: meta must come from the same export as index.json`)
    if (dash.open_class !== meta.season + 1) fail(`recruiting/dashboard.json: open class ${dash.open_class}, expected ${meta.season + 1}`)
    const classes = {}
    const HS = 'id,profile_id,ranking,name,position,stars,rating,school,state,height,weight,team_id,committed_other'
    const CL = 'team_id,rank,points,commits,five,four,three,avg_rating'
    for (const y of dash.classes ?? []) {
      const hs = read(`recruiting/hs_${y}.json`), cl = read(`recruiting/teams_${y}.json`)
      if (!hs || !cl) continue
      for (const [n, d] of [[`hs_${y}`, hs], [`teams_${y}`, cl]]) if (d.meta?.exported_at !== meta.exported_at || d.year !== y) fail(`recruiting/${n}.json: export stamp or year`)
      if (hs.columns?.join() !== HS || cl.columns?.join() !== CL) { fail(`recruiting/*_${y}.json: columns`); continue }
      if (hs.open !== (y > meta.season)) fail(`recruiting/hs_${y}.json: open flag`)
      const ids = new Set(), byTeam = new Map()
      let lastRank = 0, unranked = false
      hs.rows.forEach((r, i) => {
        const [id, prof, rank, name, , st, rt, , , , , team] = r, where = `recruiting/hs_${y}.json row ${i}`
        if (typeof id !== 'string' || ids.has(id) || typeof name !== 'string') fail(`${where}: id or name`)
        ids.add(id)
        if (st !== null && !(Number.isInteger(st) && st >= 1 && st <= 5)) fail(`${where}: stars ${st}`)
        if (rt !== null && !(isNum(rt) && rt > 0 && rt <= 1)) fail(`${where}: rating ${rt}`)
        if (rank === null) unranked = true
        else if (!Number.isInteger(rank) || rank < lastRank || unranked) fail(`${where}: not in national-rank order`)
        else lastRank = rank
        if (prof !== null && !existsSync(`${dir}player/${prof}.json`)) fail(`${where}: no player/${prof}.json`)
        if (team !== null) { if (!dirIds.has(team)) fail(`${where}: team ${team} is not FBS`); const t = byTeam.get(team) ?? [0, 0, 0, 0]; t[0]++; if (st === 5) t[1]++; if (st === 4) t[2]++; if (st === 3) t[3]++; byTeam.set(team, t) }
      })
      const seen = new Set(), ranks = []
      for (const r of cl.rows) {
        const [team, rank, , commits, five, four, three] = r
        if (!dirIds.has(team) || seen.has(team)) fail(`recruiting/teams_${y}.json: bad or duplicate team ${team}`)
        seen.add(team)
        const t = byTeam.get(team) ?? [0, 0, 0, 0]
        if (commits !== t[0] || five !== t[1] || four !== t[2] || three !== t[3]) fail(`recruiting/teams_${y}.json ${team}: counts ${[commits, five, four, three]} differ from hs_${y}.json ${t}`)
        if (rank !== null) ranks.push(rank)
      }
      if (ranks.some((v, i) => i && v < ranks[i - 1])) fail(`recruiting/teams_${y}.json: ranked classes out of order`)
      if (cl.ranked !== ranks.length > 0) fail(`recruiting/teams_${y}.json: ranked flag`)
      if (y > meta.season && cl.ranked) fail(`recruiting/teams_${y}.json: the open class cannot be ranked yet`)
      classes[y] = new Map(cl.rows.map(r => [r[0], r]))
    }
    for (const c of cards?.teams ?? []) {
      const where = `recruiting/cards.json ${c.team_id}`
      if (!dirIds.has(c.team_id)) fail(`${where}: not FBS`)
      const rk = c.classes.map(k => { if (k.rank !== (classes[k.year]?.get(c.team_id)?.[1] ?? null)) fail(`${where}: ${k.year} rank differs from teams_${k.year}.json`); return k.rank })
      const avg = rk.length === 4 && rk.every(v => v !== null) ? rk.reduce((a, b) => a + b, 0) / 4 : null
      // published to one decimal by R, which rounds halves to even
      if (avg === null ? c.avg_rank_4yr !== null : !(Math.abs(c.avg_rank_4yr - avg) <= 0.05 + 1e-9)) fail(`${where}: 4-year average ${c.avg_rank_4yr}, expected ${avg}`)
      const b = c.blue_chip
      if (b.blue > b.rated || (b.rated ? Math.abs(b.share - b.blue / b.rated) > 1e-4 : b.share !== null)) fail(`${where}: blue-chip share`)
      const o = classes[c.open_class.year]?.get(c.team_id)
      if ((o?.[3] ?? 0) !== c.open_class.commits) fail(`${where}: open-class commits differ from teams_${c.open_class.year}.json`)
    }
    // Transfer portal: rows as published, match counts, and the derived Star Churn table recomputed from the rows.
    const PC = 'name,position,origin_id,origin_other,dest_id,dest_other,date,stars,rating,eligibility,match,athlete_id,profile'
    const TC = 'team_id,rank,in,out,churn,in_stars,out_stars,star2_in,star2_out,star_churn'
    const MATCH = ['destination', 'origin', 'ambiguous', 'conflict', 'unmatched']
    const portalTeams = {}
    for (const y of dash.portal_years ?? []) {
      const P = read(`recruiting/portal_${y}.json`), where = `recruiting/portal_${y}.json`
      if (!P) continue
      if (P.meta?.exported_at !== meta.exported_at || P.year !== y) fail(`${where}: export stamp or year`)
      if (P.columns?.join() !== PC || P.team_columns?.join() !== TC) { fail(`${where}: columns`); continue }
      const mc = Object.fromEntries(MATCH.map(k => [k, 0])), agg = new Map()
      const add = (t, k, v) => { const a = agg.get(t) ?? { in: 0, out: 0, in_stars: 0, out_stars: 0, in_sq: 0, out_sq: 0 }; a[k] += v; agg.set(t, a) }
      P.rows.forEach((r, i) => {
        const [name, , o, , d, , , st, rt, elig, match, aid, prof] = r
        if (typeof name !== 'string' || !name) fail(`${where} row ${i}: name`)
        if ((o !== null && !dirIds.has(o)) || (d !== null && !dirIds.has(d)) || (o === null && d === null)) fail(`${where} row ${i}: needs an FBS program on one side`)
        if (st !== null && !(Number.isInteger(st) && st >= 1 && st <= 5)) fail(`${where} row ${i}: stars ${st}`)
        if (rt !== null && !(isNum(rt) && rt > 0 && rt <= 1)) fail(`${where} row ${i}: rating ${rt}`)
        if (!MATCH.includes(match)) { fail(`${where} row ${i}: match ${match}`); return }
        mc[match]++
        if ((match === 'destination' || match === 'origin') !== (typeof aid === 'string' && /^\d+$/.test(aid))) fail(`${where} row ${i}: athlete_id must be set exactly for matched rows`)
        if (prof && !existsSync(`${dir}player/${aid}.json`)) fail(`${where} row ${i}: no player/${aid}.json`)
        if (elig === 'Withdrawn') return
        for (const [t, side] of [[d, 'in'], [o, 'out']]) if (t !== null) { add(t, side, 1); if (st !== null) { add(t, `${side}_stars`, 1); add(t, `${side}_sq`, st * st) } }
      })
      if (MATCH.some(k => P.match?.[k] !== mc[k]) || P.fbs_rows !== P.rows.length || P.rows_total < P.fbs_rows) fail(`${where}: match counts or row totals`)
      const tm = new Map()
      P.teams.forEach((r, i) => {
        const [t, rank, ...v] = r, a = agg.get(t)
        if (rank !== i + 1) fail(`${where}: team ranks must be 1..N in order`)
        if (!a) { fail(`${where}: team ${t} has no transfers`); return }
        const s2i = a.in_stars ? a.in_sq / a.in_stars : null, s2o = a.out_stars ? a.out_sq / a.out_stars : null
        const want = [a.in, a.out, a.in - a.out, a.in_stars, a.out_stars, s2i, s2o, s2i !== null && s2o !== null ? s2i - s2o : null]
        if (want.some((w, k) => (w === null) !== (v[k] === null) || (w !== null && Math.abs(w - v[k]) > 0.02))) fail(`${where} ${t}: team totals differ from the rows`)
        if (i) { const q = P.teams[i - 1], sc = x => x === null ? -Infinity : x   // Star Churn (nulls last), then Churn, then team id
          const ka = [-sc(q[9]), -q[4], Number(q[0])], kb = [-sc(r[9]), -r[4], Number(r[0])], c = ka.findIndex((z, j) => z !== kb[j])
          if (c >= 0 && ka[c] > kb[c]) fail(`${where}: not ordered by Star Churn, then Churn, then team id`) }
        tm.set(t, r)
      })
      if (tm.size !== agg.size) fail(`${where}: ${agg.size} teams have transfers, ${tm.size} listed`)
      portalTeams[y] = tm
    }
    const lastPortal = Math.max(...(dash.portal_years ?? []))
    for (const c of cards?.teams ?? []) if (c.portal) { const r = portalTeams[c.portal.year]?.get(c.team_id); if (c.portal.year !== lastPortal || !r || r[1] !== c.portal.rank || r[2] !== c.portal.in || r[3] !== c.portal.out) fail(`recruiting/cards.json ${c.team_id}: portal tile differs from portal_${c.portal.year}.json`) }
    const open = classes[dash.open_class]
    if (open) dash.open_top.forEach((t, i) => { const r = [...open.values()][i]; if (!r || r[0] !== t.team_id || r[3] !== t.commits) fail(`recruiting/dashboard.json: open_top ${i} is not row ${i} of teams_${dash.open_class}.json`) })
  }

  // CFPi+ Player Ratings beta (players/ratings; scripts/export_player_ratings.R): well-formed, flags that follow the
  // published rules, TE kept out of the lists, every list row identical to the team file, counts that add up.
  const topR = existsSync(`${dir}players/ratings/top.json`) ? read('players/ratings/top.json') : null
  if (topR) {
    const RC = 'athlete_id,name,team_id,position,group,class,ovr,band,provisional,estimated,profile,rs'
    const GROUPS = ['QB', 'RB', 'WR', 'TE', 'OL', 'DL', 'LB', 'DB', 'K', 'P']
    const rowOk = (r, where) => {
      const [id, name, team, , group, cls, ovr, band, prov, est, prof] = r
      if (typeof id !== 'string' || !/^\d+$/.test(id) || typeof name !== 'string' || !dirIds.has(team)) fail(`${where}: id, name or team`)
      if (!GROUPS.includes(group) || (cls !== null && !(Number.isInteger(cls) && cls >= 1 && cls <= 6))) fail(`${where}: group or class`)
      if (!Number.isInteger(ovr) || ovr < 30 || ovr > 99 || !Number.isInteger(band) || band < 0) fail(`${where}: ovr ${ovr} ± ${band}`)
      if (typeof prov !== 'boolean' || est !== ['OL', 'K', 'P'].includes(group) || (group === 'OL' && !prov)) fail(`${where}: Provisional / Estimated flags`)
      if (prof !== existsSync(`${dir}player/${id}.json`)) fail(`${where}: profile flag`)
      if (typeof r[11] !== 'boolean' || (r[11] && !(cls >= 1 && cls <= 4))) fail(`${where}: rs flag`)
    }
    if (topR.meta?.exported_at !== meta.exported_at || topR.columns?.join() !== RC || topR.method?.version !== 'v1') fail('players/ratings/top.json: stamp, columns or version')
    const teamRows = new Map(); let rated = 0, prov = 0, est = 0
    for (const f of readdirSync(`${dir}players/ratings/team/`)) {
      const T = read(`players/ratings/team/${f}`), where = `players/ratings/team/${f}`
      if (!T) continue
      if (T.meta?.exported_at !== meta.exported_at || T.team_id !== f.slice(0, -5) || T.columns?.join() !== RC) fail(`${where}: stamp, team or columns`)
      T.rows.forEach((r, i) => { rowOk(r, `${where} row ${i}`); if (r[2] !== T.team_id || teamRows.has(r[0])) fail(`${where} row ${i}: wrong team or listed twice`); teamRows.set(r[0], r); rated++; prov += r[8]; est += r[9] })
    }
    const c = topR.method.counts
    if (c.rated !== rated || c.provisional !== prov || c.estimated !== est) fail(`players/ratings/top.json: counts ${JSON.stringify(c)} differ from the team files (${rated}, ${prov}, ${est})`)
    topR.rows.forEach((r, i) => {
      rowOk(r, `players/ratings/top.json row ${i}`)
      if (r[4] === 'TE') fail(`players/ratings/top.json row ${i}: tight ends are left out of the lists`)
      if (i && r[6] > topR.rows[i - 1][6]) fail('players/ratings/top.json: not ordered by rating')
      if (JSON.stringify(teamRows.get(r[0])) !== JSON.stringify(r)) fail(`players/ratings/top.json row ${i}: differs from the team file`)
    })
  }

  // Player search index and profiles: one index row per profile file, each file named by its athlete id.
  const players = existsSync(`${dir}players.json`) ? read('players.json') : null
  if (players) {
    const files = new Set(readdirSync(`${dir}player/`).filter(f => f.endsWith('.json')).map(f => f.slice(0, -5)))
    const rowsIdx = players.players ?? []
    if (rowsIdx.length !== files.size || rowsIdx.some(p => !files.has(String(p[0])))) fail(`players.json: ${rowsIdx.length} rows for ${files.size} player files`)
    for (const id of files) {
      const p = read(`player/${id}.json`)
      if (p && (p.player?.athlete_id !== id || p.meta?.schema_version !== 2)) fail(`player/${id}.json: athlete_id or schema_version`)
    }
  }
  return errors
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {   // (a plain file:// string never matches a path with spaces)
  const errors = validateSiteData()
  if (errors.length) {
    console.error(`Site data validation failed (${errors.length} problem${errors.length === 1 ? '' : 's'}):`)
    for (const e of errors.slice(0, 50)) console.error(`  - ${e}`)
    process.exit(1)
  }
  console.log('Site data valid.')
}
