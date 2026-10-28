#!/bin/bash
# git-pushbranch.sh <BRANCH>   push a fix branch of the three clones to YOUR repos with the stored credential (adapted pushbranch.sh),
# then compare the remote head with the local HEAD. Refuses a dirty tree or a clone not on BRANCH. One line per repo; rc 0 when all
# three say "pushed, remote has the same commit". Push only on a product change (never for harness/tool changes).
. "$(dirname "$(readlink -f "$0")")/lib/git.sh"
BR=${1:?branch}; bad=0
for r in $REPOS; do u=$(repo_url "$r")
	[ "$(g "$r" branch --show-current)" = "$BR" ] || { echo "$r: clone is not on $BR"; bad=1; continue; }
	[ -z "$(g "$r" status --porcelain)" ] || { echo "$r: uncommitted changes: commit them first"; bad=1; continue; }
	run g "$r" push -q "$u" "$BR:$BR" 2>&1 | mask | tail -2
	l=$(g "$r" rev-parse HEAD); rm_=$(gls "$u" "refs/heads/$BR" | cut -f1)
	[ -n "$DRYRUN" ] && { echo "$r: DRYRUN local=${l:0:8}"; continue; }
	[ "$l" = "$rm_" ] && echo "$r: pushed, remote has the same commit ${l:0:8}" || { echo "$r: MISMATCH local=${l:0:8} remote=${rm_:0:8}"; bad=1; }
done
exit $bad
