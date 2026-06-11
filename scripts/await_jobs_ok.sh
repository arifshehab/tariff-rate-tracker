#!/bin/bash
#
# Wait until every given Slurm job ID reaches a terminal state; exit 0 only if
# ALL ended COMPLETED.
#
# Used by submit_build_array.sh: the finalize job's scheduler dependency covers
# only the LAST gather, because earlier gathers may have finished more than
# MinJobAge (5 min here) before the finalize is submitted and been purged from
# the controller -- a dependency on a purged job ID is rejected outright
# ("Job dependency problem"). sacct reads the accounting DB, which keeps the
# records, so success of the earlier gathers is re-checked here instead.
set -euo pipefail
[ $# -ge 1 ] || { echo "usage: $0 <jobid>..." >&2; exit 2; }

POLL=30          # seconds between sacct polls for a not-yet-terminal job
MAX_EMPTY=20     # consecutive empty sacct replies tolerated (accounting lag)

for j in "$@"; do
  empty=0
  while :; do
    st=$(sacct -j "$j" -X -n -o State%30 2>/dev/null | head -1 | awk '{print $1}')
    case "$st" in
      COMPLETED) break ;;
      "")
        empty=$((empty + 1))
        if [ "$empty" -ge "$MAX_EMPTY" ]; then
          echo "job $j: no sacct record after $((empty * POLL))s -- aborting" >&2
          exit 1
        fi
        sleep "$POLL" ;;
      PENDING|RUNNING|REQUEUED|RESIZING|SUSPENDED|COMPLETING)
        empty=0
        sleep "$POLL" ;;
      *)
        echo "job $j ended in state '$st' (want COMPLETED) -- aborting" >&2
        exit 1 ;;
    esac
  done
done
echo "all $# job(s) COMPLETED: $*"
