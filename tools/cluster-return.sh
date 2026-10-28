#!/bin/bash
# cluster-return.sh <returning node> <leading node> [tag]   a stopped node comes back while the other node leads (adapted return.sh):
# start, settle, then checks: returning node does NOT hold the cluster ip, the leader keeps it, leader key unchanged, ready/ and
# ActivePartners list the node, nextlead names it, same commit of the three repos on both, API answered while it came back,
# isinsync. Refuses a node that is running (never "return" a node that was never stopped) unless NOSTART=1 (already started).
# Ends with "RETURN OK" or "RETURN FAILED (n)".
. "$(dirname "$(readlink -f "$0")")/lib/tstor.sh"
R=${1:?returning node}; LD=${2:?leading node}; TAG=${3:-r}
CL=$(cfgn "$LD" cluster 1); CIP=$([ "$CL" = 2 ] && cfg get cluster.second_cluster_ip || cfg get cluster.cluster_ip)
FAILS=0; ok() { log "  PASS $*"; }; bad() { log "  FAIL $*"; FAILS=$((FAILS+1)); }
if [ -z "$NOSTART" ]; then
	[ "$(node_state "$R")" = running ] && { log "REFUSED: $R is running; it was never stopped (use NOSTART=1 if you started it yourself)"; exit 5; }
fi
gl() { etcd_get "$LD" "$CIP" "$@"; }
HL=$(node_exec "$LD" hostname | tr -d '\r\n')
log "before: leader=$HL ($LD) ready=$(gl ready --prefix) nextlead=$(gl nextlead/er) isinsync=$(gl isinsync)"
SMP=$QC_STATE/tmp/return-$TAG.samples; : > "$SMP"
( while [ ! -f "$SMP.stop" ]; do c=$(curl -s -m 2 -o /dev/null -w '%{http_code}' "http://$CIP:$TS_PORT/"); echo "$(date +%T) $c" >> "$SMP"; sleep 2; done ) &
rm -f "$SMP.stop"; trap 'touch "$SMP.stop"' EXIT   # K-12: the sampler always ends, also on a kill / abort
T0=$SECONDS; [ -z "$NOSTART" ] && { log "START $R"; node_start "$R" || { touch "$SMP.stop"; log "start of $R failed"; exit 1; }; }
"$QC_TOOLS/cluster-settle.sh" "$R" --after-start && ok "$R settled after $((SECONDS-T0))s (incl. the real settle and isinsync)" || bad "$R did not settle"
touch "$SMP.stop"; sleep 3
HR=$(node_exec "$R" hostname | tr -d '\r\n'); IPR=$(cfgn "$R" host)
n=0; until gl ready --prefix | grep -q "$HR" && [ "$(etcd_get "$R" "$IPR" nextlead/er | tr -d ' ')" = "$HR/$IPR" ]; do sleep 3; n=$((n+3)); [ $n -ge 180 ] && break; done
node_exec "$R" 'ip -4 -o addr show' | grep -q " $CIP/" && bad "the returning node holds the cluster ip $CIP (duplicate ip)" || ok "the returning node does not hold the cluster ip"
node_exec "$LD" 'ip -4 -o addr show' | grep -q " $CIP/" && ok "cluster ip $CIP still on $LD" || bad "cluster ip left $LD"
L=$(gl leader); echo "$L" | grep -q "$HL" && ok "leader key still $HL" || bad "leader key is '$L'"
gl ready --prefix | grep -q "$HR" && ok "leader lists ready/$HR" || bad "ready/$HR missing"
gl ActivePartners --prefix | grep -q "$HR" && ok "leader lists ActivePartners/$HR" || bad "ActivePartners/$HR missing"
NLL=$(gl nextlead/er | tr -d ' '); [ "$NLL" = "$HR/$IPR" ] && ok "leader named the returning node next leader (after ${n}s)" || bad "nextlead/er on the leader is '$NLL', wanted $HR/$IPR"
for r in topstor pace topstorweb; do p=$(cfg get repos.node_paths.$r); a=$(node_exec "$LD" "cd $p && git rev-parse HEAD" 2>/dev/null); b=$(node_exec "$R" "cd $p && git rev-parse HEAD" 2>/dev/null)
	[ -n "$a" ] && [ "$a" = "$b" ] && ok "$r same commit on both (${a:0:8})" || bad "$r differs: $LD '${a:0:8}' $R '${b:0:8}'"; done
tot=$(wc -l < "$SMP"); badn=$(grep -vc ' 200$' "$SMP")
[ "$badn" = 0 ] && ok "cluster API answered 200 in all $tot samples while $R came back" || bad "cluster API not 200 in $badn of $tot samples (see $SMP)"
log "=== RESULT $TAG: FAILS=$FAILS"; [ $FAILS -eq 0 ] && { log "RETURN OK"; exit 0; }; log "RETURN FAILED ($FAILS)"; exit 1
