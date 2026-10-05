import { useState } from 'react'
import { DataGate, Info, PageHead, Select, TeamLogo, useData, useTeams } from '../components'
import { Headshot, PlayerLink } from '../player'
import { Link, useQueryParam } from '../router'
import { FLAG_INFO, LABEL, RATING_INFO, ratingRows, TIER, type RatingRow, type RatingsMethod, type RatingsTeam, type RatingsTop } from '../ratings'

// CFPi+ Player Ratings beta: the Ratings view of /players/ and the methodology page /players/ratings/.
// Modelled, not official (docs/website/PLAYER_RATINGS_PREDECLARATION.md, PLAYER_RATINGS_VALIDATION.md).

const GROUPS = ['QB', 'RB', 'WR', 'TE', 'OL', 'DL', 'LB', 'DB', 'K', 'P']
const CLASS = ['', 'FR', 'SO', 'JR', 'SR', '5th', '6th']
const SHOW = 100

function Table({ rows, teamCol }: { rows: RatingRow[]; teamCol: boolean }) {
  const teams = useTeams()
  const [more, setMore] = useState(false)
  const list = more ? rows : rows.slice(0, SHOW)
  return <>
    <div className="cf-table-wrap"><table className="cf-table">
      <thead><tr><th scope="col" className="cf-th-start">Player</th>
        <th scope="col" className="cf-th-start" style={{ textAlign: 'center' }}>OVR <Info text={RATING_INFO} label="About the rating" /></th></tr></thead>
      <tbody>{list.map(r => { const t = teams.get(r.team_id)
        return <tr key={r.athlete_id}>
          <td><span className="cf-team">{teamCol && <Headshot id={r.athlete_id} teamId={r.team_id} name={t?.team ?? ''} />}<span className="cf-team-text">
            <PlayerLink id={r.profile ? r.athlete_id : null} className="" style={{ textDecoration: 'none' }}>{r.name}</PlayerLink>
            <span className="cf-team-sub" style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>{teamCol && <><TeamLogo id={r.team_id} name={t?.team ?? ''} size={14} /><span aria-hidden="true">·</span></>}{[r.position, r.class ? `${r.rs ? 'RS ' : ''}${CLASS[r.class]}` : null, r.provisional && 'Provisional', r.estimated && 'Estimated'].filter(Boolean).join(' · ')}</span></span></span></td>
          <td className="cf-num" style={{ textAlign: 'center' }}>{r.ovr}<span> ± {r.band}</span></td>
        </tr> })}</tbody>
    </table></div>
    {rows.length > SHOW && <p><button type="button" className="cf-btn" onClick={() => setMore(m => !m)}>{more ? `Show top ${SHOW}` : `Show all ${rows.length}`}</button></p>}
  </>
}

/** The Ratings view of /players/: top players overall and by position (TE left out), or every rated player on one team. */
export function RatingsView() {
  const top = useData<RatingsTop>('players/ratings/top.json')
  const teams = useTeams()
  const [pos, setPos] = useQueryParam('pos')
  const [conf, setConf] = useQueryParam('conf')
  const [team, setTeam] = useQueryParam('team')
  const teamDoc = useData<RatingsTeam>(team ? `players/ratings/team/${team}.json` : null)
  return <DataGate source={top} label="Player ratings">{d => {
    const all = ratingRows(d)
    const confs = [...new Set([...teams.values()].map(t => t.conference).filter(Boolean) as string[])].sort()
    const teamOpts = [...teams.values()].filter(t => !conf || t.conference === conf).sort((a, b) => a.team.localeCompare(b.team))
    const source = team && teamDoc.data ? ratingRows(teamDoc.data) : all
    const rows = source.filter(r => (!pos || r.group === pos) && (team || !conf || teams.get(r.team_id)?.conference === conf))
    return <>
      <div className="cf-toolbar" style={{ alignItems: 'end', gap: '12px 16px', marginBottom: 12 }}>
        <Select label="Conference" value={conf} onChange={v => { setConf(v); setTeam('') }}><option value="">All</option>{confs.map(c => <option key={c} value={c}>{c}</option>)}</Select>
        <Select label="Team" value={team} onChange={setTeam}><option value="">Top players</option>{teamOpts.map(t => <option key={t.team_id} value={t.team_id}>{t.team}</option>)}</Select>
        <Select label="Position" value={pos} onChange={setPos}><option value="">All</option>{GROUPS.filter(g => team || g !== 'TE').map(g => <option key={g} value={g}>{g}</option>)}</Select>
      </div>
      <p className="cf-muted cf-small" style={{ margin: '0 0 12px' }} role="status">{rows.length} players · <strong>{LABEL}. Beta.</strong> {d.method.note} <Link to="/players/ratings/">How the ratings work and how they were validated</Link>.</p>
      {team && teamDoc.loading ? <div className="cf-state" role="status"><span className="cf-spinner" aria-hidden="true" />Loading team ratings…</div>
        : rows.length === 0 ? <div className="cf-state"><p className="cf-state-title">No rated players match</p></div> : <Table rows={rows} teamCol={!team} />}
      <p className="cf-small cf-muted">{team ? 'Every rated player on the team’s roster, tight ends included.' : `The ${rows.length < all.length ? 'filtered ' : ''}highest-rated players (the top 300 overall plus each position’s top 50). ${d.method.left_out.TE}`} {FLAG_INFO.provisional} {FLAG_INFO.estimated}</p>
    </>
  }}</DataGate>
}

const pct = (e: { est: number; lo: number; hi: number }, d = 3) => `${e.est > 0 ? '+' : ''}${e.est.toFixed(d)} (95% interval ${e.lo.toFixed(d)} to ${e.hi.toFixed(d)})`

/** /players/ratings/: methodology, validation and limits. */
export default function RatingsMethodology() {
  const top = useData<RatingsTop>('players/ratings/top.json')
  return <>
    <PageHead title="CFPi+ Player Ratings (Beta)" />
    <DataGate source={top} label="Ratings method">{d => <Method m={d.method} />}</DataGate>
  </>
}

function Method({ m }: { m: RatingsMethod }) {
  const h = m.validation.holdout, p = h.production
  return <div className="cf-prose" style={{ maxWidth: 760 }}>
    <h2 className="cf-h2">What it is</h2>
    <p>{m.note} Version {m.version}. {m.counts.rated.toLocaleString()} players are rated; {Math.round(100 * m.counts.provisional / m.counts.rated)}% are Provisional and {Math.round(100 * m.counts.estimated / m.counts.rated)}% Estimated. Each rating comes with a ± band (one standard deviation).</p>
    <table className="cf-table cf-table-compact"><tbody>{[[99, 99], [90, 98], [80, 89], [70, 79], [60, 69], [50, 59], [40, 49], [30, 39]].map(([a, b]) => <tr key={a}><td className="cf-num">{a === b ? a : `${a}–${b}`}</td><td>{TIER(a)}</td></tr>)}</tbody></table>
    <p className="cf-small cf-muted">These descriptions are CFPi+ interpretations, not official classifications.</p>
    <h2 className="cf-h2">Inputs by position</h2>
    <ul>
      <li><strong>QB, RB, WR, TE:</strong> CollegeFootballData PPA per play, success rate (QB, RB), yards per attempt, carry or catch, TD minus INT rate (QB) and usage share (RB, WR, TE). Volume alone earns nothing: every input is a rate.</li>
      <li><strong>DL, LB, DB:</strong> tackles, tackles for loss, sacks, QB hurries, passes defended and interceptions, per 12 team games. CollegeFootballData has no player PPA for defenders and no snap counts, so opportunities are measured by recorded defensive plays.</li>
      <li><strong>OL (Estimated):</strong> no individual blocking, pressure or snap data exists. The rating rests on the recruiting rating, size and class year, plus a small (15%) team adjustment from sacks allowed and yards per carry.</li>
      <li><strong>K, P (Estimated):</strong> field-goal rate and distance; punting average, inside-20 and touchback rates.</li>
    </ul>
    <h2 className="cf-h2">Priors, shrinkage and uncertainty</h2>
    <p>Each input is compared with the other players at the position that season, and last season counts half. The more plays a player has, the more the rating follows the player's production; with few plays it falls back on a prior from the 247Sports recruiting rating (a rostered player with no recruiting record starts below average). The ± band shrinks as evidence grows. <strong>Provisional</strong> means the prior still outweighs production: most backups and newcomers. Many Provisional players with no recruiting record share the same rating (65 ± 25): it says only that the data knows little about them.</p>
    <h2 className="cf-h2">Calibration</h2>
    <p>A fixed curve maps the underlying score to 30–99. It was set once on the 2021 and 2022 rosters to a target spread (about 1% at 95+, 4% at 90+, 20% at 80+, mean near 70) and then frozen; it is not re-fit each year and does not force a share into each band. Positions are compared on the same scale. Published ratings now: mean {m.distribution.mean}, SD {m.distribution.sd}; {m.distribution.at['90']}% at 90+, {m.distribution.at['80']}% at 80+.</p>
    <h2 className="cf-h2">Validation</h2>
    <p>The method, weights and pass marks were written down and frozen before testing. A rating built only from data through one season was tested on the next, on seasons it had never seen (2024 and 2025), against the recruiting rating alone:</p>
    <ul>
      <li>Next-season production (correlation gain over recruiting alone): {pct(p.pooled)}. Positive in all seven position groups tested; QB {p.QB.est.toFixed(2)}, DL {p.DL.est.toFixed(2)}, LB {p.LB.est.toFixed(2)}, DB {p.DB.est.toFixed(2)}, WR {p.WR.est.toFixed(2)}, RB {p.RB.est.toFixed(2)}, TE {p.TE.est.toFixed(2)} (not significant for TE).</li>
      <li>Being drafted the next spring (juniors and seniors; AUC gain): {pct(h.draft.delta)}; rating {h.draft.rating.est.toFixed(2)} vs recruiting {h.draft.stars.est.toFixed(2)}.</li>
      <li>No position group is inflated on average: among players with solid evidence, every group's average is within 1.3 points of the overall average.</li>
    </ul>
    <p className="cf-small cf-muted">The recruiting rating alone barely predicts next-season production among players who play, so it is a low bar. The draft test shows the rating holds information beyond recruiting; it is not a draft forecast. Production tests cover players who played in consecutive seasons.</p>
    <h2 className="cf-h2">Limits</h2>
    <ul>
      <li>This beta uses games through the {m.rated_through} season. {m.roster_season} games are not included yet (that needs its own validation).</li>
      <li>No snap counts, blocking grades, pressures allowed or depth charts in the data. Offensive-line ratings are estimates.</li>
      <li>PPA is CollegeFootballData's own measure and is not opponent-adjusted.</li>
      <li>Tight-end ratings validated weakly; tight ends are left out of the rating lists.</li>
      <li>At the very top the scale leans defensive: defenders hold about four in five ratings of 95 or higher (most 99s are defensive linemen), and receivers and running backs reach that range least often. Defensive per-game rates can sit far above their peers', while offensive per-play rates are tighter. The average-level check above does not catch this.</li>
      <li>Transfers keep their production; their team changes with the {m.roster_season} roster.</li>
    </ul>
    <p className="cf-small cf-muted">Source: CollegeFootballData (season stats, player PPA, usage, success, rosters, team stats, draft picks) and the 247Sports Composite recruiting ratings via CollegeFootballData.</p>
  </div>
}
