#!/bin/bash
# Activates the forward-evidence schedule on this Mac. NOT run automatically: run it only after approving activation.
#   bash scripts/forward/install_launchd.sh <git-commit-to-pin>
# 1. Clones the repository at the pinned commit into ~/cfb-forward/code (outside the iCloud Desktop, so launchd jobs are
#    not blocked by macOS folder privacy and files are never evicted). The pinned copy is never edited; a code change
#    means a new pinned commit and a logged re-install.
# 2. Creates the evidence archive ~/cfb-forward/evidence (write-once files + hash-chained manifest).
# 3. Installs two user LaunchAgents: Sunday pre-cutoff play-by-play pulls and twice-daily pre-kickoff snapshots.
# Uninstall: launchctl bootout gui/$(id -u)/com.cfbmodel.forward.snapshot (and .pbp); the archive is left untouched.
set -euo pipefail
COMMIT="${1:?pin a commit}"
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
BASE="$HOME/cfb-forward"; CODE="$BASE/code"; ARCHIVE="$BASE/evidence"
[ -e "$CODE" ] && { echo "$CODE exists; refusing to replace a pinned install" >&2; exit 1; }
mkdir -p "$BASE" "$ARCHIVE/logs"
git clone --quiet --no-hardlinks "$SRC" "$CODE"
git -C "$CODE" checkout --quiet --detach "$COMMIT"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) installed commit $(git -C "$CODE" rev-parse HEAD)" >> "$ARCHIVE/install_log.txt"
( cd "$CODE" && /usr/local/bin/Rscript tests/forward/test_forward.R ) >> "$ARCHIVE/install_log.txt" 2>&1
for job in snapshot pbp; do
  dst="$HOME/Library/LaunchAgents/com.cfbmodel.forward.$job.plist"
  sed -e "s#__CODE__#$CODE#g" -e "s#__ARCHIVE__#$ARCHIVE#g" "$CODE/config/forward/launchd/com.cfbmodel.forward.$job.plist" > "$dst"
  launchctl bootout "gui/$(id -u)/com.cfbmodel.forward.$job" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$dst"
done
launchctl print "gui/$(id -u)/com.cfbmodel.forward.snapshot" | grep -E "state|last exit" || true
echo "Installed. Archive: $ARCHIVE"
