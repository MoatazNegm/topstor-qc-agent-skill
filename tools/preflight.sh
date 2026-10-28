#!/bin/bash
# preflight.sh [--offline]   FIRST command of every agent. Checks config/input.yaml exists and is complete (cfg.py validate), that
# secrets are given as file paths only, that the tools each node type needs exist, and (unless --offline) that the platform accepts
# the tester key (prints the user name and role only), every node answers node-exec, and your three repos are reachable.
# rc 2 = config missing/incomplete: STOP and ask the user to fill config/input.yaml (copy config/input.example.yaml); do nothing else.
# rc 1 = a check failed (fix it or ask the user); rc 0 = ready.
QC_ROOT=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
CF=${QC_CONFIG:-$QC_ROOT/config/input.yaml}
if [ ! -f "$CF" ]; then
	echo "PREFLIGHT STOP: $CF is missing. Ask the user to copy config/input.example.yaml to config/input.yaml and fill in every field (secrets as file paths only)."; exit 2; fi
python3 -I "$QC_ROOT/tools/lib/cfg.py" validate || { echo "PREFLIGHT STOP: ask the user to complete $CF (the lines above say what is missing)."; exit 2; }
. "$QC_ROOT/tools/lib/node.sh"
bad=0; need() { command -v "$1" >/dev/null 2>&1 || { echo "MISSING TOOL: $1 ($2)"; bad=1; }; }
need curl "platform and TopStor API"; need python3 "config, JSON"; need git "repos"; need zip "config zip of a FAIL"; need unzip "config zip check"
for t in $(for n in $(cfg nodes); do cfgn "$n" type; done | sort -u); do case $t in
	container) need docker "container nodes" ;; physical) need ssh "physical nodes"; need scp "physical nodes" ;;
	virtualbox) need ssh "virtualbox nodes"; [ -n "$(for n in $(cfg nodes --type virtualbox); do cfgn "$n" vbox_manager_ssh; done)" ] || need VBoxManage "virtualbox nodes" ;; esac; done
[ "$1" = --offline ] && { [ $bad = 0 ] && echo "PREFLIGHT OK (offline checks only)"; exit $bad; }
. "$QC_TOOLS/lib/qc.sh"
ME=$(qc_get api-keys/me | python3 -I -c 'import sys,json;d=json.load(sys.stdin);u=d.get("user") or {};print("%s role=%s"%(u.get("username"),u.get("role")) if d.get("authenticated") else "")' 2>/dev/null)
[ -n "$ME" ] && echo "platform: authenticated as $ME" || { echo "platform: the tester key was NOT accepted (401/403 or no answer): STOP and tell the user"; bad=1; }
for n in $(cfg nodes); do s=$(node_state "$n" 2>/dev/null)
	if [ "$s" = running ]; then node_exec "$n" true >/dev/null 2>&1 && echo "node $n: $s, node-exec ok" || { echo "node $n: $s but node-exec FAILED"; bad=1; }
	else echo "node $n: $s (not started; fine if the test builds it)"; fi; done
. "$QC_TOOLS/lib/git.sh"
for r in $REPOS; do gls --heads "$(repo_url "$r")" >/dev/null 2>&1 && echo "repo $r: reachable" || { echo "repo $r: NOT reachable with the credential file"; bad=1; }; done
[ $bad = 0 ] && echo "PREFLIGHT OK" || echo "PREFLIGHT FAILED: fix the lines above (or ask the user) before any test step"
exit $bad
