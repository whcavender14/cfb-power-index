#!/bin/bash
# Scheduler entry point for the forward-evidence tasks. Usage: run_forward.sh <pull_pbp|snapshot>
# Requires CFB_FORWARD_ARCHIVE. Logs every run; on failure posts a macOS notification and exits non-zero.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TASK="${1:?task: pull_pbp or snapshot}"
case "$TASK" in pull_pbp|snapshot) ;; *) echo "unknown task $TASK" >&2; exit 64 ;; esac
ARCHIVE="${CFB_FORWARD_ARCHIVE:?set CFB_FORWARD_ARCHIVE}"
mkdir -p "$ARCHIVE/logs"
LOG="$ARCHIVE/logs/$(date -u +%Y%m%dT%H%M%SZ)_${TASK}.log"
cd "$ROOT" || exit 1
RSCRIPT="${CFB_RSCRIPT:-/usr/local/bin/Rscript}"
"$RSCRIPT" "scripts/forward/${TASK}.R" >"$LOG" 2>&1
CODE=$?
if [ "$CODE" -ne 0 ]; then
  /usr/bin/osascript -e "display notification \"forward ${TASK} exited ${CODE}; see ${LOG}\" with title \"CFB forward evidence\" sound name \"Basso\"" >/dev/null 2>&1 || true
fi
exit "$CODE"
