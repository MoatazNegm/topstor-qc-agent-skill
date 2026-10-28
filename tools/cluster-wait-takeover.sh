#!/bin/bash
# cluster-wait-takeover.sh <survivor node> [max seconds, default 600] [--cluster N]
# After a node was stopped: poll the cluster portal login (a login that works = the survivor leads) then print users, CIFS and HOME
# volumes and the pool state seen on the survivor (adapted waittakeover.sh). Exit 0 = answered, 1 = timeout. Read-only.
. "$(dirname "$(readlink -f "$0")")/lib/tstor.sh"
S=${1:?survivor node}; MAX=${2:-600}; CL=1; [ "${3:-}" = --cluster ] && CL=${4:-1}
CIP=$([ "$CL" = 2 ] && cfg get cluster.second_cluster_ip || cfg get cluster.cluster_ip)
[ -n "${DRYRUN:-}" ] && { log "DRYRUN: would poll the login at $CIP for $MAX s, then list users, volumes, pools"; exit 0; }
t=0; until [ -n "$(ts_token "$CIP" 2>/dev/null | grep -v baduser)" ]; do [ $t -ge $MAX ] && { log "no takeover answer after $MAX s"; exit 1; }; sleep 10; t=$((t+10)); done
log "portal answered after about $t s"
echo "users: $("$QC_TOOLS/ts-user.sh" list 2>&1 | tr '\n' ' ')"
for T in CIFS HOME; do echo "$T volumes:"; "$QC_TOOLS/ts-volume.sh" list $T 2>&1 | sed 's/^/  /'; done
echo "pools on $S:"; node_exec "$S" "timeout 20 zpool list -H -o name,health" 2>&1 | sed 's/^/  /'
