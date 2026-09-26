import { useEffect, useState } from 'react'
import { fetchDataset, type Dataset, type Rating, type Simulation } from '../../data'
import BettingAnalysis from '../../BettingAnalysis'
import SeasonSimulations from '../../SeasonSimulations'

// The original dashboard views, kept at stable URLs (/simulations/, /betting/; old #simulations and #betting links
// redirect here). They read the version-1 files (public/data/{ratings,simulations,betting}.json) unchanged.
function useLegacy() {
  const [ratings, setRatings] = useState<Dataset<Rating> | null>(null)
  const [simulations, setSimulations] = useState<Dataset<Simulation> | null>(null)
  const [error, setError] = useState(false)
  const [loading, setLoading] = useState(true)
  const [retry, setRetry] = useState(0)
  useEffect(() => {
    setLoading(true); setError(false)
    Promise.allSettled([fetchDataset<Rating>('ratings'), fetchDataset<Simulation>('simulations')]).then(([r, s]) => {
      if (r.status === 'fulfilled') setRatings(r.value)
      if (s.status === 'fulfilled') setSimulations(s.value); else setError(true)
      setLoading(false)
    })
  }, [retry])
  return { ratings, simulations, error, loading, onRetry: () => setRetry(x => x + 1) }
}

export function LegacySimulations() {
  const d = useLegacy()
  return <div className="cf-legacy"><h1 className="cf-sr">Season simulations</h1><SeasonSimulations simulations={d.simulations} ratings={d.ratings} loading={d.loading} error={d.error} onRetry={d.onRetry} /></div>
}

export function LegacyBetting() {
  const d = useLegacy()
  return <div className="cf-legacy"><h1 className="cf-sr">Betting lines</h1><BettingAnalysis ratings={d.ratings} /></div>
}
