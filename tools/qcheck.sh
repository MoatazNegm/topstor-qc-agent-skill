#!/bin/bash
# qcheck.sh [node]   the usual after-step checks in ONE summary line: pool health on the first RUNNING node (or the one named; timeout 10 s,
#   every pool must be ONLINE), the product's isinsync, the active platform test, git status of the three clones. Odd items are expanded
#   below the line, rc 1 when anything is odd, rc 2 (printed once) when config/input.yaml is missing. Read-only. QCHECK_DRY=1 skips nodes and platform.
CFGF=${QC_CONFIG:-$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)/config/input.yaml}
[ -r "$CFGF" ] || { echo "QCHECK: config missing ($CFGF): copy config/input.example.yaml and fill it in; nothing checked"; exit 2; }
. "$(dirname "$(readlink -f "$0")")/lib/qc.sh"
. "$QC_TOOLS/lib/tstor.sh"
X=(); N=${1:-}
if [ -n "${QCHECK_DRY:-}" ]; then ZP=skipped; IS=skipped; AT=skipped; N=${N:-skipped}
else
	if [ -z "$N" ]; then for c in $(cfg nodes 2>/dev/null); do
		[ "$(cfgn "$c" role 2>/dev/null)" = client ] && continue
		[ "$(node_state "$c" 2>/dev/null)" = running ] && { N=$c; break; }; done; fi
	if [ -z "$N" ]; then ZP="no-running-node"; X+=("no running cluster node found in the config")
	else
		ZO=$("$QC_TOOLS/node-exec" "$N" timeout 10 zpool list -H -o name,health 2>&1); zr=$?
		if [ $zr = 124 ]; then ZP="RC124-HUNG"; X+=("zpool list timed out (rc 124): report at once, see docs/safety.md")
		elif [ $zr != 0 ]; then ZP="rc$zr"; X+=("$ZO")
		else ZP="$(echo "$ZO" | grep -c .)pool(s)ok"; BAD=$(echo "$ZO" | grep -v -w ONLINE | grep .)
			[ -n "$BAD" ] && { ZP="NOT-ONLINE"; X+=("$BAD"); }; fi
	fi
	IV=$(ts_isinsync "$(cfg get cluster.cluster_ip 2>/dev/null)" 2>/dev/null); IS="isinsync=${IV:-unknown}"; ts_green "$IV" || X+=("isinsync not green: '${IV:-unknown}'")
	AT=$(qc_get tests/active | python3 -I -c 'import sys,json
try: d=json.load(sys.stdin); d=d.get("activeTest") or d; print(d["id"],d.get("name","")[:30])
except Exception: print("unreadable")' 2>/dev/null); [ -z "$AT" ] || [ "$AT" = unreadable ] && { AT=unreadable; X+=("active test could not be read"); }
fi
GS=; for r in topstor pace topstorweb; do c=$(cfg get repos.$r.clone 2>/dev/null); [ -d "$c/.git" ] && GS="$GS $r:$(git -C "$c" status -sb | head -n1 | cut -c1-40)$([ -n "$(git -C "$c" status -s)" ] && echo '+dirty')"; done
echo "QCHECK node=${N:-?} zpool=$ZP $IS active=[$AT] git:${GS:- none}"; for l in "${X[@]}"; do echo "  ! $l"; done
[ ${#X[@]} = 0 ]
