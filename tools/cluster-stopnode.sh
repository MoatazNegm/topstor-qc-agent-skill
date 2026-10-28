#!/bin/bash
# cluster-stopnode.sh <node> [--keep-running] [--hard] [--export]   the ONLY way to stop a TopStor cluster node (adapted stopnode.sh).
# Container flavour (one shared kernel): refuse when this node holds the iSCSI initiator (iscsid) and another node has a pool
# imported (rc 5); stop the share containers that hold this node's pools, release LIO, export each pool (3 tries), check it is
# gone, log the initiator out of THIS node's own target, then a graceful stop. Physical/VirtualBox: a real shutdown (the test's
# "sudden death" may use --hard = power cut); pools are exported first only with --export.
# FORCE_DEGRADED=1 also exports a DEGRADED pool. rc: 0 ok, 1 not running, 2 pool not exportable (node NOT stopped),
# 3 zpool does not answer (STOP, report at once), 4 stop did not finish, 5 refused by the iSCSI guard.
. "$(dirname "$(readlink -f "$0")")/lib/tstor.sh"
N=${1:?node}; shift; KEEP=0; HARD=; EXPORT=0
for a in "$@"; do case $a in --keep-running) KEEP=1;; --hard) HARD=--hard;; --export) EXPORT=1;; esac; done
FL=$(cfg get cluster.flavour); TYPE=$(node_type "$N")
say() { log "stopnode $N: $*"; }
[ "$(cfgn "$N" role)" = client ] && { QC_GUARDED=1 node_stop "$N"; exit; }
[ "$(node_state "$N")" = running ] || { say "not running"; exit 1; }
zpool_answers "$N" || { say "zpool does not answer -- nothing done (report it at once: possible SUSPENDED pool)"; exit 3; }
[ "$FL" = container ] && EXPORT=1
[ "$FL" = container ] && [ -n "$HARD" ] && { say "REFUSED: --hard in the container flavour (shared kernel)"; exit 5; }
MINE=" $(pools_owned "$N" | tr '\n' ' ') "
if [ "$FL" = container ] && node_exec "$N" 'pgrep -x iscsid' >/dev/null 2>&1; then
	for p in $(pools_on "$N"); do case "$MINE" in *" $p "*) ;; *)
		say "REFUSED: $N holds the iSCSI initiator and pool $p is imported by another node -- stopping $N would suspend it. Move the pool first (stop its owner) or stop the other node first"; exit 5;; esac; done
fi
if [ $EXPORT = 1 ]; then
	for p in $MINE; do
		st=$(pool_state "$N" "$p")
		[ "$st" = ONLINE ] || { [ "$st" = DEGRADED ] && [ -n "${FORCE_DEGRADED:-}" ]; } || { say "pool $p is '$st' -- not touched, node NOT stopped (never export/clear a SUSPENDED pool)"; exit 2; }
		ok=0
		for try in 1 2 3; do
			names=$(node_exec "$N" "for c in \$(docker ps --format '{{.Names}}'); do docker inspect -f '{{range .Mounts}}{{.Source}} {{end}}' \$c 2>/dev/null | grep -q '/$p' && echo \$c; done" 2>/dev/null | tr '\n' ' ')
			[ -n "${names// }" ] && { say "try $try: stopping the share containers of $p: $names"; node_exec "$N" "docker stop -t 10 $names" >/dev/null 2>&1; }
			node_exec "$N" "$(cfg get repos.node_paths.pace /pace)/ciscsirelease.sh" >/dev/null 2>&1   # LIO backstores on zvols hold the pool open
			if node_exec "$N" "timeout 120 zpool export $p" >/dev/null 2>&1 && ! pools_on "$N" | grep -qx "$p"; then ok=1; break; fi
			say "try $try: export of $p refused"; sleep 5
		done
		[ $ok = 1 ] && say "pool $p exported" || { say "pool $p could not be exported -- node NOT stopped (a stop would suspend the pool)"; exit 2; }
	done
	zpool_answers "$N" || { say "zpool does not answer after the export -- stop here, report at once"; exit 3; }
fi
[ $KEEP = 1 ] && { say "pools exported, node left running"; exit 0; }
if [ "$FL" = container ]; then
	# graceful iSCSI teardown of THIS node's own target only (its pools are exported). A session that dies together with its
	# target container once ended in a kernel oops in iscsi_tcp. Done from the node that holds iscsid, never with host iscsiadm.
	NIP=$(cfgn "$N" host); OWN=
	for c in $(cluster_nodes); do [ "$(node_type "$c")" = container ] && [ "$(node_state "$c")" = running ] && node_exec "$c" 'pgrep -x iscsid' >/dev/null 2>&1 && { OWN=$c; break; }; done
	if [ -n "$OWN" ] && [ -n "$NIP" ]; then
		node_exec "$OWN" 'iscsiadm -m session' 2>/dev/null | awk -v ip="$NIP:" 'index($3, ip) == 1 {print $4}' | while read -r iqn; do
			say "iSCSI logout of $iqn ($NIP:3266) from $OWN"; node_exec "$OWN" "timeout 60 iscsiadm -m node -T $iqn -p $NIP:3266 -u" >/dev/null 2>&1 || say "logout of $iqn failed (continuing)"
		done
	fi
fi
say "stopping ($TYPE${HARD:+, hard})"; QC_GUARDED=1 node_stop "$N" $HARD || { say "stop command failed"; exit 4; }
node_wait_down "$N" 300 && say "node stopped" || { say "stop did not finish"; exit 4; }
