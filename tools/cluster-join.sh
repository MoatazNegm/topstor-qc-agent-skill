#!/bin/bash
# cluster-join.sh <member node> [alias]   join a freshly reset node to its cluster with ONE call (hosts/joincluster: name, alias, node ip),
# wait for its restart and settle, verify ready/ + ActivePartners on the leader, etcd on its node ip, same branch+commit of the three
# repos, nextlead synced (adapted join.sh). Ends with "JOIN OK" or "JOIN FAILED".
. "$(dirname "$(readlink -f "$0")")/lib/tstor.sh"
M=${1:?member node}; AL=${2:-$(cfgn "$M" alias "node$RANDOM")}
CL=$(cfgn "$M" cluster 1); P=$(primary_of "$CL"); CIP=$([ "$CL" = 2 ] && cfg get cluster.second_cluster_ip || cfg get cluster.cluster_ip)
DIP=$(cfg get cluster.discovery_ip 10.11.11.253); BITS=$(cfg get cluster.subnet_bits 24); MIP=$(cfgn "$M" host)
FAILS=0; ok() { log "  PASS $*"; }; bad() { log "  FAIL $*"; FAILS=$((FAILS+1)); }; fail() { bad "$*"; log "JOIN FAILED"; exit 1; }
[ -n "$P" ] || fail "cluster $CL has no primary in the config"
T=; for i in $(seq 1 120); do T=$(ts_token "$CIP"); [ -n "$T" ] && [ "$T" != baduser ] && break; sleep 5; done
[ -n "$T" ] && [ "$T" != baduser ] || fail "no login on $CIP after 600 s"
# a node that is still starting answers docker exec with an error text: wait for a real first-boot name (dhcpNNN)
H=; for i in $(seq 1 60); do H=$(node_exec "$M" hostname 2>/dev/null | tr -d '\r\n'); echo "$H" | grep -qE '^dhcp[0-9]+$' && break; H=; sleep 3; done
[ -n "$H" ] || fail "$M has no first-boot host name after 180 s (is it reset?)"
API="http://$CIP:$TS_PORT/api/v1"
curl -s -m 20 -o /dev/null -X POST -G "$API/hosts/discover" --data-urlencode name=nothing --data-urlencode "token=$T"
n=0; until etcd_get "$P" "$DIP" possible --prefix | grep -q "possible/$H"; do sleep 5; n=$((n+5)); [ $n -gt 900 ] && fail "$H not in discovery after 900 s"; done
B=$(node_bootid "$M")
st=$(curl -s -m 90 -X POST -G "$API/hosts/joincluster" --data-urlencode "name=$H" --data-urlencode "alias=$AL" --data-urlencode "ipaddr=$MIP" \
	--data-urlencode "ipaddrsubnet=$BITS" --data-urlencode "token=$T" | python3 -I -c 'import sys,json;print(json.load(sys.stdin).get("joinstatus","none"))' 2>/dev/null)
[ "$st" = acknowledged ] && ok "join $H as $AL at $MIP -> $st" || fail "join $H -> $st"
node_wait_reboot "$M" "$B" 600 && ok "$M restarted by itself after the join" || fail "$M did not restart after the join"
"$QC_TOOLS/cluster-settle.sh" "$M" --after-start || bad "$M did not settle after the join"
n=0; until etcd_get "$P" "$CIP" "ready/$H" | grep -q "$MIP"; do sleep 5; n=$((n+5)); [ $n -gt 300 ] && break; done
etcd_get "$P" "$CIP" "ready/$H" | grep -q "$MIP" && ok "leader ready/$H = $MIP" || bad "leader ready/$H is '$(etcd_get "$P" "$CIP" "ready/$H")'"
etcd_get "$P" "$CIP" "ActivePartners/$H" | grep -q "$MIP" && ok "leader ActivePartners/$H" || bad "ActivePartners/$H missing"
node_exec "$M" 'docker port etcd' 2>/dev/null | grep -q "$MIP:2379" && ok "$M etcd on its node ip" || bad "$M etcd not on $MIP"
for r in topstor pace topstorweb; do p=$(cfg get repos.node_paths.$r)
	a=$(node_exec "$P" "cd $p && echo \$(git rev-parse --abbrev-ref HEAD) \$(git rev-parse HEAD)" 2>/dev/null); b=$(node_exec "$M" "cd $p && echo \$(git rev-parse --abbrev-ref HEAD) \$(git rev-parse HEAD)" 2>/dev/null)
	[ -n "$a" ] && [ "$a" = "$b" ] && ok "$r same branch+commit (${a:0:30})" || bad "$r differs: primary '$a' node '$b'"; done
n=0; until [ "$(etcd_get "$M" "$MIP" nextlead/er | tr -d ' ')" = "$H/$MIP" ]; do sleep 2; n=$((n+2)); [ $n -gt 120 ] && break; done
[ "$(etcd_get "$M" "$MIP" nextlead/er | tr -d ' ')" = "$H/$MIP" ] && ok "$M local nextlead/er synced after ${n}s" || bad "$M local nextlead/er not $H/$MIP"
[ $FAILS -eq 0 ] && { log "JOIN OK"; exit 0; }; log "JOIN FAILED ($FAILS)"; exit 1
