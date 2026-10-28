#!/bin/bash
# cluster-settle.sh <node> [--after-start] [--settle S] [--no-sync]   wait until the node's own setup (docker_setup.sh) has finished, then a REAL
# settle of cluster.settle_seconds (default 300 s), then the isinsync check of its cluster. Run it after EVERY node start/return
# and before EVERY stop. --after-start: the setup is expected to start (waits up to 10 min to see it). --no-sync: skip the
# isinsync check (a node on its first-boot address during a build). Prints one SETTLE line.
# rc 0 = settled and in sync, 1 = not in sync / not reachable, 2 = setup stalled (log silent 240 s).
. "$(dirname "$(readlink -f "$0")")/lib/tstor.sh"
N=${1:?node}; shift; AFTER=0; NOSYNC=0; S=$(cfg get cluster.settle_seconds 300)
while [ $# -gt 0 ]; do case $1 in --after-start) AFTER=1;; --no-sync) NOSYNC=1;; --settle) S=$2; shift;; esac; shift; done
CL=$(cfgn "$N" cluster 1); CIP=$([ "$CL" = 2 ] && cfg get cluster.second_cluster_ip || cfg get cluster.cluster_ip)
[ -n "${DRYRUN:-}" ] && { echo "DRYRUN: settle $N (after-start=$AFTER) ${S}s, isinsync on $CIP"; exit 0; }
T0=$SECONDS
node_wait_up "$N" 1800 || exit 1
seen=0 quiet=0 lines=-1 stall=0 B=$(node_bootid "$N")
while :; do
	b=$(node_bootid "$N"); [ "$b" != "$B" ] && { log "$N restarted while settling; waiting again"; B=$b; seen=0; quiet=0; node_wait_up "$N" 1800 || exit 1; }
	if setup_running "$N"; then
		seen=1; quiet=0
		now=$(node_exec "$N" 'wc -l < /var/log/docker_setup.log' 2>/dev/null)
		if [ "$now" = "$lines" ]; then stall=$((stall+5)); else stall=0; lines=$now; fi
		[ $stall -ge 240 ] && { log "STALL $N: setup log silent 240 s; tail:"; node_exec "$N" 'tail -3 /var/log/docker_setup.log' | cut -c1-160; exit 2; }
	else
		quiet=$((quiet+1))
		if [ $AFTER = 1 ] && [ $seen = 0 ]; then [ $((SECONDS-T0)) -gt 600 ] && { log "$N: the setup never started in 10 min"; exit 1; }
		elif [ $quiet -ge 3 ]; then break; fi
	fi
	sleep 5
done
SETUP=$((SECONDS-T0))
for ((i=0; i<S; i+=60)); do [ $i -gt 0 ] && log "settle $N: $i of $S s"; sleep $(( S-i < 60 ? S-i : 60 )); done
node_exec "$N" true >/dev/null 2>&1 || { log "SETTLE $N: node stopped answering during the settle"; exit 1; }
[ $NOSYNC = 1 ] && { log "SETTLE $N: setup finished after ${SETUP}s; settle ${S}s; isinsync not checked (--no-sync)"; exit 0; }
M=$(cfg get cluster.isinsync_timeout 300); t=0
while :; do v=$(ts_isinsync "$CIP"); ts_green "$v" && break; [ $t -ge "$M" ] && break; sleep 10; t=$((t+10)); done
if ts_green "$v"; then log "SETTLE $N: setup finished after ${SETUP}s; real settle ${S}s; isinsync=$v on $CIP (after ${t}s more)"; exit 0; fi
log "SETTLE $N: setup finished after ${SETUP}s; real settle ${S}s; isinsync NOT green on $CIP after ${t}s (value '$v')"; exit 1
