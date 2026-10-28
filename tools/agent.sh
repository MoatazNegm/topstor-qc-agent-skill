#!/bin/bash
# agent.sh <command>   registry of the fresh agents the supervisor runs (one task per agent), in state/agents/.
#   register <id> <role> <task...>          role = tester | coder | validator (supervisor is the caller itself)
#   status <id> <text...>                   the agent's own status line (also its NOW line when it has no round): time is added
#   finish <id> <result...>                 the agent handed back
#   usage <id> <model> <tokens> <tool uses> <duration>   completion numbers -> state/agent-usage.md (the usage ledger)
#   list                                    one line per agent: id role state last status age
. "$(dirname "$(readlink -f "$0")")/lib/common.sh"
A=$QC_STATE/agents; c=${1:-list}; shift
case $c in
register) id=${1:?id}; shift; r=${1:?role}; shift; printf 'role=%s\nstate=running\nstarted=%s\ntask=%s\n' "$r" "$(date '+%F %T')" "$*" > "$A/$id.meta"; : > "$A/$id.status" ;;
status) id=${1:?id}; shift; echo "$(date +%s) $(date +%T) $*" | mask >> "$A/$id.status" ;;
finish) id=${1:?id}; shift; sed -i 's/^state=.*/state=finished/' "$A/$id.meta"; echo "$(date +%s) $(date +%T) FINISHED $*" | mask >> "$A/$id.status" ;;
usage) id=${1:?id}; L=$QC_STATE/agent-usage.md; [ -f "$L" ] || printf '| date | agent | role | model | tokens | tool uses | duration | task |\n|---|---|---|---|---|---|---|---|\n' > "$L"
	r=$(sed -n 's/^role=//p' "$A/$1.meta" 2>/dev/null); t=$(sed -n 's/^task=//p' "$A/$1.meta" 2>/dev/null | cut -c1-80)
	echo "| $(date '+%F %T') | $1 | $r | ${2:?model} | ${3:?tokens} | ${4:?tool uses} | ${5:?duration} | $t |" >> "$L" ;;
list) now=$(date +%s); for m in "$A"/*.meta; do [ -f "$m" ] || continue; id=$(basename "$m" .meta)
	last=$(tail -n1 "$A/$id.status" 2>/dev/null); ts=${last%% *}; age=$(( now - ${ts:-$now} ))
	printf '%s %s %s age=%ss last: %s\n' "$id" "$(sed -n 's/^role=//p' "$m")" "$(sed -n 's/^state=//p' "$m")" "$age" "$(echo "${last#* }" | cut -c1-200)"; done ;;
*) sed -n 2,8p "$0"; exit 1 ;;
esac
