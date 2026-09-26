import { useState } from 'react'
import { ImageDown } from 'lucide-react'

/** "Download PNG" with busy state and a plain fallback message if the browser cannot export a canvas. */
export default function ShareButton({ label = 'Download PNG', run, disabled = false }: { label?: string; run: () => Promise<void>; disabled?: boolean }) {
  const [state, setState] = useState<'idle' | 'busy' | 'failed'>('idle')
  const go = async () => {
    setState('busy')
    try { await run(); setState('idle') } catch { setState('failed') }
  }
  return <span className="cf-share">
    <button type="button" className="cf-btn" onClick={go} disabled={disabled || state === 'busy'}>
      <ImageDown size={15} aria-hidden="true" />{state === 'busy' ? 'Rendering…' : label}
    </button>
    {state === 'failed' && <span className="cf-share-err" role="alert">Couldn’t create the image in this browser. Try again, or take a screenshot.</span>}
  </span>
}
