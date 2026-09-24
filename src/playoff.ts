// Pure, DOM-free playoff logic behind the Season Simulations image exports.
//
// The published simulations carry per-team odds only: no per-simulation seeds or
// brackets. The "most likely" field therefore replays cfbseedR's 2026 selection
// (cfbseedR::cfb_playoff_seeds, autobid = "2026") on aggregate inputs:
//   - ranking: playoff probability stands in for the per-simulation resume rank
//     (ties: title odds, then power rating, then name);
//   - conference champions: each conference's likeliest champion;
//   - automatic bids: every P4 champion, the top-ranked G6 team, and Notre Dame
//     when ranked inside the field; at-large teams fill the rest by rank;
//   - seeding: the 12 teams in ranking order (straight seeding, byes for 1–4).
// Games then go to the favourite under the simulation's own margin model:
// normal margins with the published residual SD, home advantage for the
// higher seed in the first round (campus sites) and neutral sites afterwards,
// mirroring cfbseedR's playoff simulator.

type Sim = { team_id: string; team: string; conference: string | null; logo_url: string | null; playoff_probability: number | null; conference_title_probability: number | null; national_title_probability: number | null }
type Rated = { team_id: string; power_rating: number | null }

export type PlayoffTeam = {
  team_id: string; team: string; conference: string | null; logo_url: string | null
  power: number; playoff: number; confTitle: number; title: number
}
export type Seeded = PlayoffTeam & { seed: number; autoBid: 'champion' | 'g6' | 'notre-dame' | null }
export type Game = { round: number; top: Seeded; bottom: Seeded; home: Seeded | null; winner: Seeded; loser: Seeded; winProbability: number }
export type Bracket = { field: Seeded[]; byes: Seeded[]; rounds: Game[][]; champion: Seeded }
export type MarginModel = { hfa: number; sigma: number }

export const P4 = ['SEC', 'Big Ten', 'ACC', 'Big 12']
export const G6 = ['American Athletic', 'Conference USA', 'Mid-American', 'Mountain West', 'Pac-12', 'Sun Belt']
/** Fallbacks match config/production.R if a snapshot omits its assumptions. */
export const DEFAULT_MODEL: MarginModel = { hfa: 3.0685, sigma: 15.7875 }
export const ROUND_NAMES = ['First round', 'Quarterfinals', 'Semifinals', 'National championship']

/** Joins simulation odds to power ratings; teams without a rating or odds are dropped. */
export function joinTeams(sims: Sim[], ratings: Rated[]): PlayoffTeam[] {
  const power = new Map(ratings.map(r => [r.team_id, r.power_rating]))
  const out: PlayoffTeam[] = []
  for (const s of sims) {
    const p = power.get(s.team_id)
    if (p == null || !Number.isFinite(p) || s.playoff_probability == null) continue
    out.push({ team_id: s.team_id, team: s.team, conference: s.conference, logo_url: s.logo_url, power: p,
      playoff: s.playoff_probability, confTitle: s.conference_title_probability ?? 0, title: s.national_title_probability ?? 0 })
  }
  return out
}

/** The proxy for the committee ranking: best playoff odds first. */
export function rankTeams(teams: PlayoffTeam[]): PlayoffTeam[] {
  return [...teams].sort((a, b) => b.playoff - a.playoff || b.title - a.title || b.power - a.power || a.team.localeCompare(b.team))
}

/** Each conference's likeliest champion (ties go to the better-ranked team). */
export function likelyChampions(ranked: PlayoffTeam[]): Map<string, PlayoffTeam> {
  const champs = new Map<string, PlayoffTeam>()
  for (const t of ranked) {
    if (!t.conference || t.confTitle <= 0) continue
    const best = champs.get(t.conference)
    if (!best || t.confTitle > best.confTitle) champs.set(t.conference, t)
  }
  return champs
}

export function selectField(teams: PlayoffTeam[], { seeds = 12, ineligible = [] as string[] } = {}): Seeded[] {
  const ranked = rankTeams(teams.filter(t => !ineligible.includes(t.team)))
  if (ranked.length < seeds) throw new Error(`Only ${ranked.length} eligible teams for a ${seeds}-team field`)
  const champs = likelyChampions(ranked)
  const auto = new Map<string, Seeded['autoBid']>()
  for (const conf of P4) { const c = champs.get(conf); if (c) auto.set(c.team_id, 'champion') }
  const g6 = ranked.find(t => t.conference != null && G6.includes(t.conference))
  if (g6 && !auto.has(g6.team_id)) auto.set(g6.team_id, 'g6')
  const nd = ranked.findIndex(t => t.team === 'Notre Dame')
  if (nd >= 0 && nd < seeds) auto.set(ranked[nd].team_id, 'notre-dame')
  const autoTeams = ranked.filter(t => auto.has(t.team_id)).slice(0, seeds)
  const atLarge = ranked.filter(t => !autoTeams.includes(t)).slice(0, seeds - autoTeams.length)
  const inField = new Set([...autoTeams, ...atLarge].map(t => t.team_id))
  return ranked.filter(t => inField.has(t.team_id)).map((t, i) => ({ ...t, seed: i + 1, autoBid: auto.get(t.team_id) ?? null }))
}

/** Standard normal CDF (Abramowitz & Stegun 7.1.26; |error| < 1.5e-7). */
export function normalCdf(z: number): number {
  if (z === 0) return 0.5
  const x = Math.abs(z) / Math.SQRT2
  const t = 1 / (1 + 0.3275911 * x)
  const erf = 1 - ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-x * x)
  return z >= 0 ? (1 + erf) / 2 : (1 - erf) / 2
}

/** Probability that `a` beats `b`; `aHome` adds home-field advantage to `a`. */
export function winProbability(a: PlayoffTeam, b: PlayoffTeam, model: MarginModel, aHome = false): number {
  return normalCdf((a.power - b.power + (aHome ? model.hfa : 0)) / model.sigma)
}

function play(round: number, top: Seeded, bottom: Seeded, model: MarginModel): Game {
  // cfbseedR hosts first-round games at the higher seed; later rounds are neutral.
  const home = round === 0 ? (top.seed < bottom.seed ? top : bottom) : null
  const p = winProbability(top, bottom, model, home === top)
  const topWins = p > 0.5 || (p === 0.5 && top.seed < bottom.seed)
  return { round, top, bottom, home, winner: topWins ? top : bottom, loser: topWins ? bottom : top, winProbability: topWins ? p : 1 - p }
}

// cfbseedR places seeds in a 16-slot bracket in this order; empty slots are byes.
const SLOT_ORDER = [1, 16, 8, 9, 4, 13, 5, 12, 2, 15, 7, 10, 3, 14, 6, 11]

/**
 * Advances the favourite in every game. Rounds are listed in bracket order, so
 * games 2i and 2i+1 of one round feed game i of the next. The quarterfinal top
 * slot is always the bye team.
 */
export function buildBracket(field: Seeded[], model: MarginModel = DEFAULT_MODEL): Bracket {
  if (field.length !== 12) throw new Error('The bracket needs exactly 12 seeded teams')
  const bySeed = new Map(field.map(t => [t.seed, t]))
  let alive: (Seeded | null)[] = SLOT_ORDER.map(s => bySeed.get(s) ?? null)
  const rounds: Game[][] = []
  for (let round = 0; alive.length > 1; round++) {
    const games: Game[] = []
    const next: (Seeded | null)[] = []
    for (let i = 0; i < alive.length; i += 2) {
      const [a, b] = [alive[i], alive[i + 1]]
      if (a && b) { const g = play(round, a, b, model); games.push(g); next.push(g.winner) }
      else next.push(a ?? b)
    }
    rounds.push(games)
    alive = next
  }
  return { field, byes: field.filter(t => t.seed <= 4), rounds, champion: alive[0]! }
}

// ── Playoff Hunt ────────────────────────────────────────────────────────────
export type Tier = { key: string; label: string; min: number; max: number }
export const TIERS: Tier[] = [
  { key: 'driver', label: 'In the driver’s seat', min: 0.8, max: 1 },
  { key: 'hunt', label: 'In the hunt', min: 0.5, max: 0.8 },
  { key: 'bubble', label: 'On the bubble', min: 0.2, max: 0.5 },
  { key: 'long', label: 'Long shots', min: 0, max: 0.2 },
]
export const tierOf = (p: number) => TIERS.find(t => p >= t.min) ?? TIERS[TIERS.length - 1]
export const HUNT_THRESHOLD = 0.05
export const huntTeams = (teams: PlayoffTeam[], threshold = HUNT_THRESHOLD) => rankTeams(teams.filter(t => t.playoff >= threshold))

export type Point = { x: number; y: number }
/**
 * Nudges overlapping circles (logos) apart while pulling each back toward its
 * data point, then clamps them inside `bounds`. Deterministic, O(n²) per pass.
 */
export function relax(points: Point[], radius: number, bounds: { x0: number; y0: number; x1: number; y1: number }, iterations = 300): Point[] {
  const out = points.map(p => ({ ...p }))
  const min = radius * 2
  for (let it = 0; it < iterations; it++) {
    let moved = false
    for (let i = 0; i < out.length; i++) for (let j = i + 1; j < out.length; j++) {
      let dx = out[j].x - out[i].x, dy = out[j].y - out[i].y
      let d = Math.hypot(dx, dy)
      if (d >= min) continue
      if (d < 1e-6) { dx = 1; dy = (j - i) % 2 ? 0.5 : -0.5; d = Math.hypot(dx, dy) }
      const push = (min - d) / 2 * 0.5
      out[i].x -= dx / d * push; out[i].y -= dy / d * push
      out[j].x += dx / d * push; out[j].y += dy / d * push
      moved = true
    }
    // The pull home fades out so the final passes only separate.
    const pull = 0.03 * Math.max(0, 1 - it / (iterations * 0.7))
    for (let i = 0; i < out.length; i++) {
      out[i].x += (points[i].x - out[i].x) * pull
      out[i].y += (points[i].y - out[i].y) * pull
      out[i].x = Math.min(bounds.x1 - radius, Math.max(bounds.x0 + radius, out[i].x))
      out[i].y = Math.min(bounds.y1 - radius, Math.max(bounds.y0 + radius, out[i].y))
    }
    if (!moved) break
  }
  return out
}
