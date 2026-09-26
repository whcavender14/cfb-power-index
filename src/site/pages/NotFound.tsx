import { Link } from '../router'

export default function NotFound() {
  return <div className="cf-state">
    <p className="cf-state-title">This page doesn’t exist</p>
    <p className="cf-muted">The link may be out of date. Try the <Link to="/rankings/">rankings</Link> or the <Link to="/teams/">team list</Link>.</p>
  </div>
}
