#!/bin/bash
# supervisor-snapshot.sh   the supervisor's input for the periodic report (adapted from the original harness watch script): clock, platform active test, loop
# state, every registered agent (last status, age, STUCK flag), the newest round's NOW / STEPCHECK / STOP / HOLD lines and steps
# submitted since the last snapshot, the newest build status, node states, and whether zpool answers. Read-only.
. "$(dirname "$(readlink -f "$0")")/lib/qc.sh"
. "$QC_TOOLS/lib/tstor.sh"
IV=$(cfg get loop.report_interval_minutes 3); SA=$(cfg get loop.stuck_after_reports 2); LIM=$((IV*SA*60))
echo "== $(date +%H:%M) snapshot"
qc_get tests/active | python3 -I -c 'import sys,json
try:
    d=json.load(sys.stdin).get("activeTest")
    print("platform active test: %s %s (%d steps)"%(d["id"],d["name"],len(d.get("steps",[]))) if d else "platform active test: none")
except Exception: print("platform active test: platform did not answer")'
echo "loop: $("$QC_TOOLS/loop-state.sh" show)"
echo "rules: fail_needs_user_ok=$(cfg get loop.fail_needs_user_ok false) reboot_for_tool_problems=$(cfg get loop.reboot_for_tool_problems true)"
now=$(date +%s)
"$QC_TOOLS/agent.sh" list | while read -r id role state age rest; do a=${age#age=}; a=${a%s}
	flag=""; [ "$state" = running ] && [ "${a:-0}" -gt "$LIM" ] && flag=" STUCK (no status for ${a}s > ${LIM}s: nudge it)"
	echo "agent $id ($role, $state)$flag $rest"; done
R=$(ls -td "$QC_STATE"/rounds/*/ 2>/dev/null | head -1)
if [ -n "$R" ]; then L=$R/run.log; M=$QC_STATE/tmp/.snap.$(basename "$R")
	echo "round $(basename "$R"): $(head -1 "$L" | cut -c1-160)"
	echo "  now: $(grep -a ' NOW ' "$L" | tail -1 | cut -c1-240)"
	lm=$(stat -c %Y "$L"); echo "  run.log last written $((now-lm))s ago$([ $((now-lm)) -gt $LIM ] && echo ' (STUCK?)')"
	from=$(cat "$M" 2>/dev/null || echo 0); total=$(wc -l < "$L")
	tail -n +$((from+1)) "$L" | grep -aE 'STEPCHECK|STOPPED-SUBMIT|HOLD|AUTOENDED|DONE' | cut -c1-260 | sed 's/^/  since last: /'
	echo "$total" > "$M"
	grep -aE 'STOPPED-SUBMIT| HOLD ' "$L" | tail -1 | sed 's/^/  last stop\/hold: /' | cut -c1-260
fi
B=$(ls -t "$QC_STATE"/builds/*/status 2>/dev/null | head -1); [ -n "$B" ] && echo "build $(basename "$(dirname "$B")"): $(tail -1 "$B" | cut -c1-200)"
"$QC_TOOLS/node-status" 2>/dev/null | sed 's/^/node /'
# K-11: probe the first RUNNING node of every cluster (the primary may be stopped in a takeover test; cluster 2 exists in replication tests)
for CLN in $(cfg nodes | while read -r x; do cfgn "$x" cluster 1; done | sort -u); do P=
	for x in $(cluster_nodes "$CLN"); do [ "$(node_state "$x")" = running ] && { P=$x; break; }; done
	if [ -z "$P" ]; then echo "pools (cluster $CLN): no running node to probe"; continue; fi
	node_exec "$P" 'timeout 15 zpool list -H -o name,health' > "$QC_STATE/tmp/zp" 2>&1; rc=$?
	[ $rc = 124 ] && echo "ZPOOL DOES NOT ANSWER (rc 124) on $P (cluster $CLN): report to the user at once" || echo "pools (cluster $CLN, via $P): $(grep -v setlocale "$QC_STATE/tmp/zp" | tr '\n' ' ' | tr '\t' ':')"
	grep -q SUSPENDED "$QC_STATE/tmp/zp" && echo "SUSPENDED POOL: report to the user at once"
done
