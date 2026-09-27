// Team page: depth chart (TWO·DEEP formation, or the usage-based fallback) and "All players by usage". Split from
// the team page so it loads on its own (it has its own data file, usage/<slug>.json).
import { useEffect, useRef, useState } from 'react'
import { Info, TeamLogo, useData } from './components'
import type { DepthRow, TeamMeta, UsageDef, UsageDoc } from './data'

const POS_NAMES: Record<string, string> = { QB: 'Quarterbacks', RB: 'Running backs', WR: 'Wide receivers', TE: 'Tight ends', DL: 'Defensive line', LB: 'Linebackers', DB: 'Defensive backs' }
const shortDate = (iso: string | null) => iso ? new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) : null

const heightText = (h: number | null | undefined) => h ? `${Math.floor(h / 12)}′${h % 12}″` : null
const shortName = (n: string) => { const parts = n.trim().split(/\s+/); return parts.length > 1 ? `${parts[0][0]}. ${parts.slice(1).join(' ')}` : n }

/** One slot in the formation: position label, headshot (initials if the photo fails), name, jersey · height, stat. */
type SlotPlayer = { name: string; jersey?: number | null; height?: number | null; headshot?: string | null }
function Slot({ pos, p, stat, next, col, row, lift }: { pos: string; p?: SlotPlayer | null; stat?: string; next?: string; col?: number; row?: number; lift?: boolean }) {
  const [broken, setBroken] = useState(false)
  const initials = p ? p.name.split(/\s+/).map(w => w[0]).slice(0, 2).join('') : 'OL'
  const bits = p ? [p.jersey != null ? `#${p.jersey}` : null, heightText(p.height)].filter(Boolean).join(' · ') : 'No snap data'
  return <div className={`cf-dc-slot${p ? '' : ' is-empty'}${lift ? ' is-lift' : ''}`} style={col ? { gridColumn: col, gridRow: row } : undefined}>
    <span className="cf-dc-pos">{pos}</span>
    <span className="cf-dc-face">{p?.headshot && !broken ? <img src={p.headshot} alt="" loading="lazy" decoding="async" onError={() => setBroken(true)} /> : <span aria-hidden="true">{initials}</span>}</span>
    <span className="cf-dc-name" title={p?.name}>{p ? shortName(p.name) : '—'}</span>
    <span className="cf-dc-bits cf-num">{bits}</span>
    {stat && <span className="cf-dc-stat cf-num">{stat}</span>}
    {next && <span className="cf-dc-next" title={`Backup: ${next}`}>then {shortName(next)}</span>}
  </div>
}

const NICKEL = /^(NB|NCB|NICK|NICKEL|STAR|HUSKY|MONEY|SPUR|SLOT|DIME)/
/** Formation from TWO·DEEP rows: each team's own slot names; starters placed like a broadcast lineup graphic. */
function TwoDeepChart({ rows, team }: { rows: DepthRow[]; team: TeamMeta }) {
  const slot = (r: DepthRow) => <Slot key={`${r.group}-${r.slot}`} pos={r.slot} p={r.players[0]} stat={r.players[0]?.snaps != null ? `${r.players[0].snaps}% snaps` : undefined} next={r.players[1]?.name} />
  const g = (...names: string[]) => rows.filter(r => names.includes(r.group.split('-')[0].toUpperCase()))
  const ol = ['LT', 'LG', 'C', 'RG', 'RT'].map(k => g('OL').find(r => r.slot === k)).filter(Boolean) as DepthRow[]
  const olRest = g('OL').filter(r => !ol.includes(r))
  const wr = g('WR'), qb = g('QB')
  const tes = g('TE'), te = [...tes.filter(r => /^(Y|TE)$/.test(r.slot)), ...tes.filter(r => !/^(Y|TE)$/.test(r.slot))]   // in-line TE first
  const rbs = g('RB'), backs = [...rbs.slice(0, 1), ...g('FB', 'SB')]   // later RB rows are second-string slots, not formation spots
  const cbs = g('CB'), outside = cbs.filter(r => !NICKEL.test(r.slot)).slice(0, 2), inside = cbs.filter(r => !outside.includes(r))
  const edges = g('EDGE'), dl = g('DL')
  const front = [edges[0], ...dl, ...edges.slice(1, -1), edges.length > 1 ? edges[edges.length - 1] : undefined].filter(Boolean) as DepthRow[]
  const half = Math.ceil(backs.length / 2)
  const hasD = cbs.length + dl.length + edges.length + g('LB').length + g('S').length > 0
  const hasO = qb.length + ol.length + wr.length + backs.length > 0
  const box = useRef<HTMLDivElement>(null)
  useEffect(() => { const el = box.current; if (el && el.scrollWidth > el.clientWidth) el.scrollLeft = (el.scrollWidth - el.clientWidth) / 2 }, [rows])   // phones: open centred
  return <><p className="cf-small cf-muted cf-dc-hint">Swipe to see the whole formation.</p><div className="cf-dc-scroll" ref={box}><div className="cf-dc is-flex" role="img" aria-label={`${team.team} depth chart`}>
    {hasD && <>
      <div className="cf-dc-row">{g('S').map(slot)}</div>
      <div className="cf-dc-row">{inside.map(slot)}{g('LB').map(slot)}</div>
      <div className="cf-dc-row is-wide">{outside[0] && slot(outside[0])}<span className="cf-dc-mid">{front.map(slot)}</span>{outside[1] && slot(outside[1])}</div>
    </>}
    <div className="cf-dc-line"><span><TeamLogo id={team.team_id} name={team.team} size={18} /> Defense</span><i /><span>Offense <TeamLogo id={team.team_id} name={team.team} size={18} /></span></div>
    {hasO && <>
      <div className="cf-dc-row is-wide">{wr[0] && slot(wr[0])}<span className="cf-dc-mid">{wr.slice(2).map(slot)}{[...ol, ...olRest].map(slot)}{te[0] && slot(te[0])}</span>{wr[1] && slot(wr[1])}</div>
      <div className="cf-dc-row">{te.slice(1).map(slot)}{backs.slice(0, half).map(slot)}{qb.slice(0, 1).map(slot)}{backs.slice(half).map(slot)}</div>
    </>}
  </div></div></>
}

/** Formation graphic from usage (offense) and tackles (defense). Heuristic, not an official depth chart. */
function DepthChart({ doc, team }: { doc: UsageDoc; team: TeamMeta }) {
  const o = doc.offense, d = doc.defense
  const pct = (v: number) => `${Math.round(v * 100)}% of plays`
  const tk = (p?: UsageDef) => p ? `${p.tackles} tkl${p.sacks ? ` · ${p.sacks} sk` : ''}` : undefined
  const wr = o?.WR ?? [], dl = d?.DL ?? [], db = d?.DB ?? [], lb = d?.LB ?? []
  const edge = dl.filter(p => p.roster_pos === 'EDGE'), inside = dl.filter(p => p.roster_pos !== 'EDGE')
  const ends = [...edge, ...inside.slice(2)].slice(0, 2), tackles = [...inside, ...edge.slice(2)].filter(p => !ends.includes(p)).slice(0, 2)
  return <div className="cf-dc-scroll"><div className="cf-dc" role="img" aria-label={`${team.team} depth chart by usage`}>
    {d && <div className="cf-dc-grid">
      <Slot pos="DB" p={db[0]} stat={tk(db[0])} col={3} row={1} /><Slot pos="DB" p={db[1]} stat={tk(db[1])} col={7} row={1} />
      <Slot pos="DB" p={db[4]} stat={tk(db[4])} col={2} row={2} /><Slot pos="LB" p={lb[0]} stat={tk(lb[0])} col={4} row={2} /><Slot pos="LB" p={lb[1]} stat={tk(lb[1])} col={6} row={2} />
      <Slot pos="DB" p={db[2]} stat={tk(db[2])} col={1} row={3} /><Slot pos="DE" p={ends[0]} stat={tk(ends[0])} col={3} row={3} />
      <Slot pos="DT" p={tackles[0]} stat={tk(tackles[0])} col={4} row={3} /><Slot pos="DT" p={tackles[1]} stat={tk(tackles[1])} col={6} row={3} />
      <Slot pos="DE" p={ends[1]} stat={tk(ends[1])} col={7} row={3} /><Slot pos="DB" p={db[3]} stat={tk(db[3])} col={9} row={3} />
    </div>}
    <div className="cf-dc-line"><span><TeamLogo id={team.team_id} name={team.team} size={18} /> Defense</span><i /><span>Offense <TeamLogo id={team.team_id} name={team.team} size={18} /></span></div>
    {o && <div className="cf-dc-grid">
      <Slot pos="WR" p={wr[0]} stat={wr[0] && pct(wr[0].usg_overall)} col={1} row={1} /><Slot pos="WR" p={wr[2]} stat={wr[2] && pct(wr[2].usg_overall)} col={2} row={1} lift />
      {['LT', 'LG', 'C', 'RG', 'RT'].map((pos, i) => <Slot key={pos} pos={pos} p={null} col={3 + i} row={1} />)}
      <Slot pos="TE" p={o.TE[0]} stat={o.TE[0] && pct(o.TE[0].usg_overall)} col={8} row={1} /><Slot pos="WR" p={wr[1]} stat={wr[1] && pct(wr[1].usg_overall)} col={9} row={1} lift />
      <Slot pos="RB" p={o.RB[0]} stat={o.RB[0] && pct(o.RB[0].usg_overall)} col={4} row={2} /><Slot pos="QB" p={o.QB[0]} stat={o.QB[0] && pct(o.QB[0].usg_overall)} col={5} row={2} />
    </div>}
  </div></div>
}

/** Players by usage: who has actually played, by position. Not an official depth chart (CFBD publishes none). */
export default function PlayersByUsage({ slug, team }: { slug: string; team: TeamMeta }) {
  const doc = useData<UsageDoc>(`usage/${slug}.json`)
  if (!doc.data) return null
  const { offense, defense, offense_pulled_at, defense_through_week } = doc.data
  const pct = (v: number) => `${(v * 100).toFixed(1)}%`
  return <section className="cf-panel cf-span-all" aria-labelledby="t-usage">
    <div className="cf-panel-head"><h2 id="t-usage" className="cf-h2">Depth chart {!doc.data.depth?.length && <span className="cf-tag">By usage</span>} <Info text="Not an official depth chart; none is published in the data. Offense: share of the team’s plays on which the player was the passer, rusher or target (CFBD player usage). Defense: total tackles, then tackles for loss, sacks, interceptions and passes defended. Offensive linemen and special teams are not listed: the data has no snap counts." label="About players by usage" /></h2></div>
    {doc.data.depth?.length ? <TwoDeepChart rows={doc.data.depth} team={team} /> : <DepthChart doc={doc.data} team={team} />}
    <details className="cf-details"><summary>All players by usage</summary>
    <div className="cf-usage">
      {offense && <div className="cf-usage-side">
        <h3 className="cf-h3">Offense <span className="cf-eff-note">· share of team plays</span></h3>
        {(['QB', 'RB', 'WR', 'TE'] as const).map(g => offense[g]?.length ? <div key={g} className="cf-usage-group">
          <h4 className="cf-usage-pos">{POS_NAMES[g]}</h4>
          <ol className="cf-usage-list">{offense[g].map(p => <li key={p.athlete_id} className="cf-usage-row">
            <span className="cf-usage-name">{p.name}</span>
            <span className="cf-usage-bar" aria-hidden="true"><i style={{ width: `${Math.min(100, p.usg_overall / 0.6 * 100)}%` }} /></span>
            <span className="cf-num cf-usage-val">{pct(p.usg_overall)}</span>
            <span className="cf-num cf-usage-sub cf-muted">{g === 'QB' ? `pass ${pct(p.usg_pass)}` : g === 'RB' ? `rush ${pct(p.usg_rush)}` : `targets ${pct(p.usg_pass)}`}</span>
          </li>)}</ol>
        </div> : null)}
      </div>}
      {defense && <div className="cf-usage-side">
        <h3 className="cf-h3">Defense <span className="cf-eff-note">· tackles · TFL · sacks · INT · PD</span></h3>
        {(['DL', 'LB', 'DB'] as const).map(g => defense[g]?.length ? <div key={g} className="cf-usage-group">
          <h4 className="cf-usage-pos">{POS_NAMES[g]}</h4>
          <ol className="cf-usage-list">{defense[g].map(p => <li key={p.athlete_id} className="cf-usage-row is-def">
            <span className="cf-usage-name">{p.name}{p.position ? <span className="cf-muted"> · {p.position}</span> : null}</span>
            <span className="cf-num cf-usage-val">{p.tackles}</span>
            <span className="cf-num cf-usage-sub cf-muted">{p.tfl} · {p.sacks} · {p.int} · {p.pd}</span>
          </li>)}</ol>
        </div> : null)}
      </div>}
    </div>
    <p className="cf-small cf-muted">Offense: share of team plays, season to date{offense_pulled_at ? ` (as of ${shortDate(offense_pulled_at)})` : ''}, so it can include games after the ratings week. Defense: {defense_through_week ? `Weeks 1–${defense_through_week}` : 'season to date'}. Source: CollegeFootballData.</p>
    </details>
    {doc.data.depth?.length && doc.data.depth_source
      ? <p className="cf-small cf-muted">Starters and backups from <a href={doc.data.depth_source.url} target="_blank" rel="noreferrer">{doc.data.depth_source.name}</a>{doc.data.depth_source.fetched_at ? `, as of ${shortDate(doc.data.depth_source.fetched_at)}` : ''}, used with permission; slot names are the team’s own. Snap shares are 2026 season to date. Photos and heights via CollegeFootballData roster.</p>
      : <p className="cf-small cf-muted">Not an official depth chart: offense is the most-used player at each spot, defense the leading tacklers (DB spots are not split into corners and safeties, which the data does not distinguish). Offensive line: no snap data{doc.data.ol_on_roster ? ` (${doc.data.ol_on_roster} on the roster)` : ''}. Photos via CollegeFootballData roster.</p>}

  </section>
}

