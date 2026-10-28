#!/bin/bash
# qc-complete.sh <round> <test id> <complete|end>   complete = all steps answered, advance the platform's loop; end = after a hard stop
# when the platform did not end the test by itself (a reply with autoEnded:true already ended it). Logged in run.log.
. "$(dirname "$(readlink -f "$0")")/lib/qc.sh"
R=${1:?round}; T=${2:?test id}; A=${3:?complete|end}; case $A in complete|end) ;; *) die "complete or end";; esac
[ -n "$DRYRUN" ] && { echo "DRYRUN: POST tests/$T/$A"; exit 0; }
O=$(qc_curl "tests/$T/$A" -X POST | mask | cut -c1-300)
"$QC_TOOLS/log.sh" "$R" NOTE "platform tests/$T/$A -> $O" >/dev/null; echo "$O"
