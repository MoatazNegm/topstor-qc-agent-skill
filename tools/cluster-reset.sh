#!/bin/bash
# cluster-reset.sh <build> [--cluster N] [--single] [--no-disks]   a fresh cluster from the EXISTING nodes (adapted resetcluster.sh):
# product reset (docker_setup.sh reset) on the primary, node + cluster address through the API, then every member reset and joined
# with cluster-join.sh. No container/VM is recreated. Refuses while any pool is imported or zpool does not answer.
# --single: only the primary. --no-disks: container flavour, export lists set to "none" (the test adds its own disks).
# Progress: state/builds/build<build>/status, last line "DONE: ..." or "STOP: ...".
. "$(dirname "$(readlink -f "$0")")/lib/tstor.sh"
BUILD=${1:?build number}; shift; CL=1; SINGLE=0; NODISKS=0
while [ $# -gt 0 ]; do case $1 in --cluster) CL=$2; shift;; --single) SINGLE=1;; --no-disks) NODISKS=1;; esac; shift; done
S=$QC_STATE/builds/build$BUILD; mkdir -p "$S"; : > "$S/status"
st() { echo "$(date +%T) $*" | mask | tee -a "$S/status"; }; stop() { st "STOP: $*"; exit 1; }
FL=$(cfg get cluster.flavour); P=$(primary_of "$CL"); [ -n "$P" ] || stop "cluster $CL has no primary"
CIP=$([ "$CL" = 2 ] && cfg get cluster.second_cluster_ip || cfg get cluster.cluster_ip); FB=$(cfg get cluster.first_boot_ip 10.11.11.250)
BITS=$(cfg get cluster.subnet_bits 24); RPW=$(cfg get cluster.reset_admin_password_file); RPW=${RPW:-$(pwfile_for "$CIP")}
TP=$(cfg get repos.node_paths.topstor /TopStor)
MEMBERS=$(cluster_nodes "$CL" | grep -vx "$P")
for n in $(cluster_nodes "$CL"); do [ "$(node_state "$n")" = running ] || continue
	zpool_answers "$n" || stop "zpool does not answer on $n (report at once)"
	[ -n "$(pools_on "$n")" ] && stop "a pool is imported on $n ($(pools_on "$n" | tr '\n' ' ')): export it with cluster-stopnode.sh first"; done
# only one node may sit on the first-boot address at a time: members down while the primary is reset
for m in $MEMBERS; do [ "$(node_state "$m")" = running ] && { st "stop member $m"; "$QC_TOOLS/cluster-stopnode.sh" "$m" || stop "could not stop $m"; }; done
reset_node() {   # reset_node <node>: run the product reset without a TTY and wait until it is over (it may restart the node)
	local n=$1 b; b=$(node_bootid "$n")
	st "$n: docker_setup.sh reset"
	node_exec "$n" "setsid nohup bash $TP/docker_setup.sh reset > /var/log/qc-reset.log 2>&1 < /dev/null &" || return 1
	"$QC_TOOLS/cluster-settle.sh" "$n" --after-start --settle 30 --no-sync >> "$S/status" 2>&1 || return 1
	node_exec "$n" 'docker port etcd' 2>/dev/null | grep -q "$FB:2379" || { st "$n is not on the first-boot address $FB after the reset"; return 1; }
}
[ "$(node_state "$P")" = running ] || { st "start $P"; node_start "$P" && node_wait_up "$P" 900 || stop "$P does not start"; }
reset_node "$P" || stop "reset of $P failed"
HN=$(node_exec "$P" hostname | tr -d '\r\n'); PIP=$(cfgn "$P" host)
T=; for i in $(seq 1 20); do T=$(ts_token "$FB" "$RPW"); [ -n "$T" ] && [ "$T" != baduser ] && break; sleep 6; done
[ -n "$T" ] && [ "$T" != baduser ] || stop "no login on $FB with the reset admin password (cluster.reset_admin_password_file)"
B=$(node_bootid "$P"); NIP=(--data-urlencode "ipaddr=$PIP" --data-urlencode "ipaddrsubnet=$BITS")
node_exec "$P" 'ip -4 -o addr show' | grep -q " $PIP/" && NIP=()      # sending ipaddr again when the node already holds it breaks the call
st "$P: node $PIP, cluster $CIP/$BITS through the API"
curl -s -m 60 -o /dev/null -X POST -G "http://$FB:$TS_PORT/api/v1/hosts/config" --data-urlencode "name=$HN" "${NIP[@]}" \
	--data-urlencode "cluster=$CIP/$BITS" --data-urlencode "user=$TS_USER" --data-urlencode id=0 --data-urlencode "token=$T"
node_wait_reboot "$P" "$B" 600 || stop "$P did not restart after the address change"
"$QC_TOOLS/cluster-settle.sh" "$P" --after-start --settle 30 --no-sync >> "$S/status" 2>&1 || stop "$P did not settle"
node_exec "$P" 'docker port etcd; docker port flask' 2>/dev/null | grep -q "$CIP:" || stop "$P: cluster address $CIP not up"
st "$P ($HN) is the primary of cluster $CIP"
if [ $SINGLE = 0 ]; then for m in $MEMBERS; do
	st "start $m"; node_start "$m" && node_wait_up "$m" 900 || stop "$m does not start"
	reset_node "$m" || stop "reset of $m failed"
	st "join $m"; "$QC_TOOLS/cluster-join.sh" "$m" > "$S/join-$m.log" 2>&1; tail -n1 "$S/join-$m.log" | grep -q "JOIN OK" || stop "join of $m failed (see $S/join-$m.log)"
done; fi
if [ $NODISKS = 1 ] && [ "$FL" = container ]; then
	st "no test disks: export lists set to none"
	for n in $(cluster_nodes "$CL"); do [ "$(node_state "$n")" = running ] && node_exec "$n" 'echo none > /root/loopdisks'; done
fi
V=""; for r in topstor pace topstorweb; do V="$V $r $(node_exec "$P" "cd $(cfg get repos.node_paths.$r) && echo \$(git branch --show-current) \$(git rev-parse --short HEAD)" 2>/dev/null)"; done
st "DONE: $([ $SINGLE = 1 ] && echo 1-node || echo multi-node) cluster $CIP is up;$V"
