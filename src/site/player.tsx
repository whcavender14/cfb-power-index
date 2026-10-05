import { createContext, lazy, Suspense, useCallback, useContext, useState, type ReactNode } from 'react'
import { TeamLogo } from './components'

// Player detail modal: any player name on the site opens it (public/data/v2/player/<athlete_id>.json).
const PlayerModal = lazy(() => import('./PlayerModal'))

const PlayerContext = createContext<(id: string) => void>(() => {})
export const useOpenPlayer = () => useContext(PlayerContext)

export function PlayerProvider({ children }: { children: ReactNode }) {
  const [id, setId] = useState<string | null>(null)
  const [opener, setOpener] = useState<HTMLElement | null>(null)
  const open = useCallback((next: string) => { setOpener(document.activeElement as HTMLElement | null); setId(next) }, [])
  const close = useCallback(() => { setId(null); opener?.focus() }, [opener])
  return <PlayerContext.Provider value={open}>
    {children}
    {id && <Suspense fallback={null}><PlayerModal id={id} onClose={close} /></Suspense>}
  </PlayerContext.Provider>
}

/** A player's name that opens the player modal. Falls back to plain text when there is no athlete id. */
export function PlayerLink({ id, children, className = '', style }: { id?: string | null; children: ReactNode; className?: string; style?: React.CSSProperties }) {
  const open = useOpenPlayer()
  if (!id) return <>{children}</>
  return <button type="button" className={`cf-plink ${className}`} style={style} onClick={e => { e.stopPropagation(); open(id) }} aria-haspopup="dialog">{children}</button>
}

/** Small round player headshot (ESPN's image for the CFBD athlete id, as in the player modal); the team logo when there is none. */
export function Headshot({ id, teamId, name, size = 32 }: { id: string; teamId: string; name: string; size?: number }) {
  const [broken, setBroken] = useState(false)
  if (broken) return <TeamLogo id={teamId} name={name} size={size} />
  return <img src={`https://a.espncdn.com/i/headshots/college-football/players/full/${id}.png`} alt="" loading="lazy" decoding="async" width={size} height={size}
    style={{ width: size, height: size, borderRadius: '50%', objectFit: 'cover', objectPosition: 'top', background: 'var(--cf-fill-2)', flex: 'none' }} onError={() => setBroken(true)} />
}
