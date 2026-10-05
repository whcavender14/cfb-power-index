import ShareButton from '../ShareButton'
import { DataGate, Freshness, Info, Num, PageHead, Pct, pctText, Segmented, SortTh, sortRows, TeamLink, TeamLogo, useData, useTeams, type Sort } from '../components'
import { currentBracket, ROUND_LABELS, simBracket, type BracketGame, type BracketTeam, type SimBracket } from '../bracket'
import type { ConferencesDoc, PlayoffDoc, PlayoffTeam, ResumeDoc } from '../data'
import { Link, useQueryParam } from '../router'

const INFO: Record<string, string> = {
  p_playoff: 'Share of simulated seasons in which the team makes the 12-team field.',
  p_auto: 'Share of seasons in which the team gets in on an automatic bid: power-conference champion, the top-ranked team from the other six conferences, or Notre Dame when ranked in the top 12.',
  p_at_large: 'Share of seasons in which the team gets in on an at-large bid.',
  p_bye: 'Share of seasons as a top-4 seed (first-round bye).',
  p_host: 'Share of seasons as seed 5–8, which hosts a first-round game on campus.',
  p_qf: 'Share of seasons reaching the quarterfinals (bye or first-round win).',
  p_sf: 'Share of seasons reaching the semifinals.',
  p_final: 'Share of seasons reaching the national championship game.',
  p_champ: 'Share of seasons winning the national title.',
  mean_seed: 'Average seed in the seasons where the team makes the field.',
}
const COLS: [keyof PlayoffTeam, string][] = [['p_playoff', 'Playoff'], ['p_auto', 'Auto Bid'], ['p_at_large', 'At-Large'], ['p_bye', 'Bye'], ['p_host', 'Host'], ['p_qf', 'QF'], ['p_sf', 'Semis'], ['p_final', 'Final'], ['p_champ', 'Title']]

const CURRENT_INFO = 'The field if the playoff were set today. Teams are ranked by résumé (strength of record, as on the Résumé ranking page) and picked under the same 2026 rules as the projection, with each Power 4 conference’s current leader (best conference record) standing in for its champion. Nothing is simulated: records are today’s, and each game is won by the higher seed.'
const BRACKET_INFO = 'The field is the single simulated season whose seeding is most consistent with all the simulations, so it follows the selection rules exactly. Each team’s record is its result in that simulated season. In each game, the team that reached the next round in more of the simulated seasons (whatever its seed) advances. One plausible path, not a forecast that every result will hold.'

function BTeam({ t, won, champ }: { t: BracketTeam; won: boolean; champ?: boolean }) {
  return <div className={`cf-brk-row${won ? ' is-won' : ''}${champ ? ' is-champ' : ''}`}>
    <span className={`cf-brk-seed${t.seed <= 4 ? ' is-bye' : ''}`} title={t.seed <= 4 ? 'First-round bye' : undefined}>{t.seed}</span>
    <TeamLink id={t.team_id} size={20} sub={t.wins != null ? `${t.wins}–${t.losses}` : undefined} />
  </div>
}
function BGame({ g, champion }: { g: BracketGame; champion: BracketTeam }) {
  const final = g.round === 3
  return <div className={`cf-brk-game${final ? ' is-final' : ''}`}>
    <BTeam t={g.top} won={g.winner === g.top} champ={final && g.winner === g.top && g.top === champion} />
    <BTeam t={g.bottom} won={g.winner === g.bottom} champ={final && g.winner === g.bottom && g.bottom === champion} />
  </div>
}
/** Desktop: the image's layout (first round, quarterfinals, semifinals | final | semifinals, quarterfinals, first round).
 *  Below 1100 px: collapsed by round, so nothing scrolls the page sideways. */
function Bracket({ b, current }: { b: SimBracket; current: boolean }) {
  const [fr, qf, sf, [fin]] = b.rounds
  const col = (label: string, games: BracketGame[], note?: string) => <div className="cf-brk-col">
    <h3 className="cf-brk-head">{label}{note && <small>{note}</small>}</h3>
    <div className="cf-brk-games">{games.map((g, i) => <BGame key={i} g={g} champion={b.champion} />)}</div>
  </div>
  return <>
    <div className="cf-brk" role="group" aria-label={current ? 'Current bracket' : 'Projected bracket'}>
      {col('First round', fr.slice(0, 2), 'Higher seed hosts')}{col('Quarterfinals', qf.slice(0, 2))}{col('Semifinals', sf.slice(0, 1))}
      <div className="cf-brk-col is-center">
        <div className="cf-brk-champ">
          <span className="cf-brk-kicker">Champion</span>
          <TeamLogo id={b.champion.team_id} name={b.champion.team_id} size={44} />
          <strong><TeamLink id={b.champion.team_id} logo={false} /></strong>
          <span className="cf-small">{pctText(b.champion.odds.p_champ)} title odds</span>
        </div>
        <h3 className="cf-brk-head">National championship</h3>
        <BGame g={fin} champion={b.champion} />
      </div>
      {col('Semifinals', sf.slice(1))}{col('Quarterfinals', qf.slice(2))}{col('First round', fr.slice(2), 'Higher seed hosts')}
    </div>
    <div className="cf-brk-rounds">
      {b.rounds.map((games, r) => <section key={r} className="cf-brk-round" aria-label={ROUND_LABELS[r]}>
        <h3 className="cf-brk-head">{ROUND_LABELS[r]}{r === 0 && <small>Seeds 1–4 have byes · higher seed hosts</small>}</h3>
        <div className="cf-brk-games">{games.map((g, i) => <BGame key={i} g={g} champion={b.champion} />)}</div>
      </section>)}
    </div>
  </>
}

export default function Playoff() {
  const doc = useData<PlayoffDoc>('playoff.json')
  const teams = useTeams()
  const [sortKey, setSortKey] = useQueryParam('sort', 'p_playoff')
  const [dir, setDir] = useQueryParam('dir', '')
  const [scope, setScope] = useQueryParam('show', '')
  const [view, setView] = useQueryParam('bracket', '')
  const current = view === 'current'
  const resume = useData<ResumeDoc>(current ? 'resume.json' : null)
  const confs = useData<ConferencesDoc>(current ? 'conferences.json' : null)
  const natural = (k: string) => k !== 'mean_seed'
  const sort: Sort = { key: sortKey, desc: dir ? dir === 'desc' : natural(sortKey) }
  const onSort = (s: Sort) => { setSortKey(s.key); setDir(s.desc === natural(s.key) ? '' : s.desc ? 'desc' : 'asc') }

  return <>
    <PageHead title="Playoff" />
    <DataGate source={doc} label="Playoff odds">{({ meta, format, teams: rows, representative_field: field }) => {
      if (meta.sim_status !== 'available' || !rows.length) return <div className="cf-state" role="status"><p className="cf-state-title">Simulation results are unavailable for this update</p><p className="cf-muted">Ratings are still current. Playoff odds return with the next successful simulation.</p></div>
      const contenders = rows.filter(r => r.p_playoff > 0)
      const shown = scope === 'all' ? rows : contenders
      const key = (sort.key in INFO ? sort.key : 'p_playoff') as keyof PlayoffTeam
      const sorted = sortRows(shown, r => r[key] as number | null, sort.desc)
      const projected = simBracket(doc.data!)
      const bracket = current ? (resume.data && confs.data ? currentBracket(doc.data!, resume.data, confs.data) : null) : projected
      const loadingCurrent = current && !(resume.data && confs.data) && !resume.error && !confs.error
      const seedTeams = [...contenders].sort((a, b) => b.p_playoff - a.p_playoff).slice(0, 24)
      return <>
        <Freshness meta={meta} sims />

        <section className="cf-section" style={{ marginTop: "var(--s3)" }} aria-labelledby="po-field">
          <div className="cf-panel-head">
            <h2 id="po-field">{current ? 'Current' : 'Projected'} bracket <Info text={current ? CURRENT_INFO : BRACKET_INFO} label="How the bracket is built" /></h2>
            <span className="cf-bracket-controls">
              <Segmented label="Bracket view" value={current ? 'current' : 'projected'} onChange={v => setView(v === 'current' ? 'current' : '')} options={[{ value: 'projected', label: 'Projected' }, { value: 'current', label: 'Current' }]} />
            {bracket ? <ShareButton label={current ? 'Current Bracket' : 'Predicted Bracket'} run={async () => { await (await import('../bracketPng')).bracketPng(doc.data!, bracket, teams, current) }} /> : <ShareButton label={current ? 'Current Bracket' : 'Predicted Bracket'} run={async () => {}} disabled />}
            </span>
          </div>
          {bracket ? <>
            <div className="cf-panel cf-brk-panel"><Bracket b={bracket} current={current} /></div>
            {current
              ? <p className="cf-small cf-muted cf-brk-note"><span className="cf-brk-seed is-bye">1</span> Seeds 1–4 have first-round byes. Ranked by résumé (strength of record) as of Week {meta.ratings_week}; the higher seed advances in every game. Conference leaders stand in for champions until the title games are played.</p>
              : <p className="cf-small cf-muted cf-brk-note"><span className="cf-brk-seed is-bye">1</span> Seeds 1–4 have first-round byes. In each game, the team that reached the next round in more of the {meta.sim_count?.toLocaleString()} simulated seasons advances. This exact seeding occurred in {field!.sims_with_identical_field} of them.</p>}
          </> : <p className="cf-muted">{loadingCurrent ? 'Loading the current field…' : current ? 'The current bracket is unavailable right now.' : 'No projected field is available.'}</p>}
          <details className="cf-rules">
            <summary>{current ? 'Selection rules used for the current bracket' : 'Selection rules used by the simulation'}</summary>
            <ul><li>{format.autobids}.</li><li>{current ? 'Teams are ranked by résumé: strength of record so far this season' : format.ranking}.</li><li>{format.seeding}.</li></ul>
          </details>
        </section>

        <section className="cf-section" aria-labelledby="po-odds">
          <div className="cf-panel-head">
            <h2 id="po-odds">Playoff odds</h2>
            <span className="cf-share-row"><label className="cf-check"><input type="checkbox" checked={scope === 'all'} onChange={e => setScope(e.target.checked ? 'all' : '')} /> Show all {rows.length} teams</label>
              <ShareButton label="Playoff Hunt" run={async () => { await (await import('../huntPng')).huntPng(doc.data!, teams) }} /></span>
          </div>
          <div className="cf-table-wrap cf-desktop">
            <table className="cf-table">
              <caption className="cf-sr">Playoff probabilities, sortable</caption>
              <thead><tr>
                <th scope="col" className="cf-th-start">Team</th>
                {COLS.map(([k, label]) => <SortTh key={k} label={label} sortKey={k} sort={sort} onSort={onSort} info={INFO[k]} align="start" style={{ textAlign: 'center' }} />)}
                <SortTh label="Avg Seed" sortKey="mean_seed" sort={sort} onSort={onSort} info={INFO.mean_seed} align="start" style={{ textAlign: 'center' }} />
              </tr></thead>
              <tbody>{sorted.map(r => <tr key={r.team_id}>
                <td><TeamLink id={r.team_id} sub={teams.get(r.team_id)?.conference} /></td>
                {COLS.map(([k]) => <td key={k} className={k === 'p_playoff' ? 'cf-strong' : undefined} style={{ textAlign: 'center' }}><Pct value={r[k] as number} /></td>)}
                <td style={{ textAlign: 'center' }}><Num value={r.mean_seed} why="Never selected" /></td>
              </tr>)}</tbody>
            </table>
          </div>
          <ol className="cf-cards cf-phone">{sorted.map(r => <li key={r.team_id} className="cf-card">
            <div className="cf-card-top"><TeamLink id={r.team_id} size={28} sub={teams.get(r.team_id)?.conference} /><span className="cf-card-power"><Pct value={r.p_playoff} /></span></div>
            <dl className="cf-card-stats">
              <div><dt>Auto bid</dt><dd><Pct value={r.p_auto} /></dd></div>
              <div><dt>Bye</dt><dd><Pct value={r.p_bye} /></dd></div>
              <div><dt>Semis</dt><dd><Pct value={r.p_sf} /></dd></div>
              <div><dt>Title</dt><dd><Pct value={r.p_champ} /></dd></div>
              <div><dt>Avg Seed</dt><dd><Num value={r.mean_seed} /></dd></div>
            </dl>
          </li>)}</ol>
        </section>

        <section className="cf-section" aria-labelledby="po-seeds">
          <div className="cf-panel-head"><h2 id="po-seeds">Seed probabilities <Info text="Share of simulated seasons in which the team receives each seed. Rows sum to the team’s playoff probability." label="About seed probabilities" /></h2></div>
          <div className="cf-table-wrap cf-desktop">
            <table className="cf-table cf-seedtable">
              <caption className="cf-sr">Probability of each seed, top {seedTeams.length} teams by playoff odds</caption>
              <thead><tr><th scope="col" className="cf-th-start">Team</th>{Array.from({ length: 12 }, (_, i) => <th key={i} scope="col" className="cf-th-end">{i + 1}</th>)}</tr></thead>
              <tbody>{seedTeams.map(r => <tr key={r.team_id}>
                <td><TeamLink id={r.team_id} size={20} /></td>
                {(r.seed_dist ?? []).map((p, i) => <td key={i} className="cf-td-end cf-heat" style={{ ['--heat' as string]: Math.min(1, p / 0.5) }}>
                  {p > 0 ? <span className="cf-num">{pctText(p, 0) === '0%' ? '<1%' : pctText(p, 0)}</span> : <span className="cf-faint" aria-label="none">·</span>}
                </td>)}
              </tr>)}</tbody>
            </table>
          </div>
          <ol className="cf-cards cf-phone">{seedTeams.map(r => { const d = r.seed_dist ?? []; const top = d.indexOf(Math.max(...d)); return <li key={r.team_id} className="cf-card">
            <div className="cf-card-top"><TeamLink id={r.team_id} size={24} /><span className="cf-small">Most likely: <strong>No. {top + 1}</strong> ({pctText(d[top], 0)})</span></div>
            <div className="cf-spark" role="img" aria-label={`Seed probabilities: ${d.map((p, i) => `${i + 1}: ${pctText(p, 0)}`).join(', ')}`}>
              {d.map((p, i) => <span key={i} className="cf-spark-col"><i style={{ height: `${Math.max(2, (p / Math.max(...d)) * 100)}%` }} /><b>{i + 1}</b></span>)}
            </div>
          </li> })}</ol>
        </section>

        <p className="cf-small cf-muted">Also available: the <Link to="/simulations/">season simulation table and shareable graphics</Link>.</p>
      </>
    }}</DataGate>
  </>
}
