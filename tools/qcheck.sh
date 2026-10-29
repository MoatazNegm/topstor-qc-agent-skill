#!/bin/bash
# qcheck.sh [node]   the usual after-step checks in ONE summary line: pool health (timeout 15, first node or the one named), active platform test,
#   git status of the three clones. Odd items are expanded below the line. Read-only. QCHECK_DRY=1 skips nodes and platform.
. "$(dirname "$(readlink -f "$0")")/lib/qc.sh"
N=${1:-$(cfg nodes 2>/dev/null | head -n1)}; X=
if [ -n "${QCHECK_DRY:-}" ]; then ZP=skipped; AT=skipped
else
	ZO=$("$QC_TOOLS/node-exec" "$N" timeout 15 zpool list -H -o name,health 2>&1); zr=$?
	if [ $zr = 124 ]; then ZP="RC124-HUNG"; elif [ $zr != 0 ]; then ZP="rc$zr"; X="$X$ZO
"; elif echo "$ZO" | grep -qE 'SUSPENDED|FAULTED|UNAVAIL|DEGRADED'; then ZP=BAD; X="$X$ZO
"; else ZP=ok; fi
	AT=$(qc_get tests/active | python3 -I -c 'import sys,json
try: d=json.load(sys.stdin); d=d.get("activeTest") or d; print(d.get("id","?"),d.get("name","")[:30])
except Exception: print("unreadable")' 2>/dev/null)
fi
GS=; for r in topstor pace topstorweb; do c=$(cfg get repos.$r.clone 2>/dev/null); [ -d "$c/.git" ] && GS="$GS $r:$(git -C "$c" status -sb | head -n1 | cut -c1-40)$([ -n "$(git -C "$c" status -s)" ] && echo '+dirty')"; done
echo "QCHECK node=${N:-?} zpool=$ZP active=[$AT] git:${GS:- none}"; [ -n "$X" ] && printf '%s' "$X"; exit 0
