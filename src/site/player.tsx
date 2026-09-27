import { createContext, lazy, Suspense, useCallback, useContext, useState, type ReactNode } from 'react'

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
export function PlayerLink({ id, children, className = '' }: { id?: string | null; children: ReactNode; className?: string }) {
  const open = useOpenPlayer()
  if (!id) return <>{children}</>
  return <button type="button" className={`cf-plink ${className}`} onClick={e => { e.stopPropagation(); open(id) }} aria-haspopup="dialog">{children}</button>
}
