import { Info, useData } from './components'
import { Link } from './router'
import { ATTRIBUTION, STAR_CHURN_INFO, rating, type CardsDoc } from './recruiting'

// Team-page Recruiting card (recruiting/cards.json; R/publish/recruiting.R). CollegeFootballData / 247Sports Composite
// values, plus counts and averages of those rows made in R. Loaded with the team page's lazy sections.
export default function RecruitingCard({ id }: { id: string }) {
  const doc = useData<CardsDoc>('recruiting/cards.json')
  const c = doc.data?.teams.find(t => t.team_id === id)
  if (!doc.data || !c) return null
  const latest = c.classes[c.classes.length - 1]
  const years = doc.data.last4
  const o = c.open_class
  return <section className="cf-panel cf-span-all" aria-labelledby="t-recruiting">
    <div className="cf-panel-head"><h2 id="t-recruiting" className="cf-h2">Recruiting</h2><Link to={`/recruiting/high-school/?team=${id}&tab=commits&year=${o.year}`} className="cf-more">{o.year} commits</Link></div>
    <div className="cf-res-tiles">
      <div><b className="cf-num">{latest?.rank ?? '—'}</b><span>{latest?.year} class rank <Info text="CollegeFootballData team class ranking (247Sports Composite), among all programs." label="About class rank" /></span><small className="cf-muted">{c.classes.slice(0, -1).map(k => `${k.year}: ${k.rank ?? '—'}`).join(' · ')}</small></div>
      <div><b className="cf-num">{c.avg_rank_4yr?.toFixed(1) ?? '—'}</b><span>4-year average rank <Info text={`Mean of the team's CollegeFootballData class ranks for ${years[0]}–${years[years.length - 1]}. Blank if a class is unranked.`} label="About the 4-year average" /></span></div>
      <div><b className="cf-num">{c.blue_chip.share == null ? '—' : `${Math.round(100 * c.blue_chip.share)}%`}</b><span>Blue-chip share <Info text={`4- and 5-star recruits among the team's rated high-school commits in the ${years[0]}–${years[years.length - 1]} classes (${c.blue_chip.blue} of ${c.blue_chip.rated}). Counts commitments in the recruiting data, not the current roster; transfers are not included.`} label="About blue-chip share" /></span></div>
      <div><b className="cf-num">{o.commits}</b><span>{o.year} commits so far</span><small className="cf-muted">{o.five ? `${o.five} five-star · ` : ''}{o.four} four-star{o.avg_rating != null ? ` · avg ${rating(o.avg_rating)}` : ''}</small></div>
      {c.portal && <div><b className="cf-num">{c.portal.in}<span className="cf-muted" style={{ fontSize: '1.25rem' }}> / {c.portal.out}</span></b><span>{c.portal.year} portal in / out <Info text={`Transfers in and out (withdrawn entries excluded). ${STAR_CHURN_INFO}`} label="About the portal tile" /></span><small className="cf-muted">{c.portal.star_churn == null ? 'No Star Churn (stars missing on one side)' : `Star Churn ${c.portal.star_churn > 0 ? '+' : ''}${c.portal.star_churn.toFixed(1).replace('-', '−')}`} · No. {c.portal.rank} of {c.portal.teams} (CFPi+ derived)</small></div>}
      {c.talent && <div><b className="cf-num">{c.talent.rank}</b><span>Roster talent rank <Info text="247Sports Team Talent Composite (via CollegeFootballData): the recruiting ratings of the current roster, among all programs." label="About roster talent" /></span><small className="cf-muted">{c.talent.value.toFixed(1)}</small></div>}
    </div>
    <p className="cf-small cf-muted">{ATTRIBUTION} Portal: CollegeFootballData. Not a CFPi+ model input. <Link to="/recruiting/">Recruiting</Link> · <Link to={`/recruiting/high-school/?team=${id}&tab=commits`}>Commitments</Link> · <Link to={`/recruiting/transfers/?tab=in&team=${id}`}>Transfers</Link></p>
  </section>
}
