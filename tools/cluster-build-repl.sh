#!/bin/bash
# cluster-build-repl.sh <build> [--single]   TWO clusters for the replication tests (adapted buildrepl.sh): cluster 1 (config nodes with
# cluster: 1, normally ONE node) and cluster 2 (cluster: 2, one or more nodes). Every node must already exist in the config; this tool
# never creates a node container/VM (see "Not portable" below).
# Steps: refuse when zpool does not answer or any pool is imported; refuse when two nodes of the config share a node address or a
# cluster address (only ONE node may sit on the first-boot address at a time); graceful iSCSI logout of every session (no pool is
# imported, so nothing is torn down) from the iscsid holder; stop every node with cluster-stopnode.sh; cluster-reset.sh --single for
# cluster 1, then cluster-reset.sh for cluster 2 (--single here too with --single: cluster 2 = its primary only); then
# repl-iscsi-cross.sh with EXPLICIT node:ip arguments so the iscsid holder can log in to the other cluster's targets.
# Progress: state/builds/build<build>/status, last line "DONE: ..." or "STOP: ...".
# Not portable: the original also recreated the third node container (zfs3) from the second one's trees, with its own docker address,
# loop-disk device numbers and ports. How to create a node is environment specific: create the cluster-1 node yourself (container, VM
# or server), put it in the config with cluster: 1 and its own host/second_cluster_ip, then run this tool.
. "$(dirname "$(readlink -f "$0")")/lib/tstor.sh"
BUILD=${1:?build number}; shift; SINGLE=0; for a in "$@"; do case $a in --single) SINGLE=1;; *) die "unknown option $a";; esac; done
S=$QC_STATE/builds/build$BUILD; mkdir -p "$S" "$QC_STATE/builds"
# K-04: never a second build at once, never wipe the status of a build that has not ended (restart it only on purpose: QC_BUILD_RESTART=1)
if [ -z "${QC_BUILD_LOCKED:-}" ]; then exec 9>"$QC_STATE/builds/.lock"; flock -n 9 || { echo "REFUSED: another build is running (lock $QC_STATE/builds/.lock); let it finish, read its status file" >&2; exit 5; }; export QC_BUILD_LOCKED=1; fi
if [ -z "${DRYRUN:-}" ] && [ -s "$S/status" ] && ! tail -n1 "$S/status" | grep -qE '(DONE|STOP):' && [ -z "${QC_BUILD_RESTART:-}" ]; then
	echo "REFUSED: build$BUILD has a status that did not end with DONE/STOP: $(tail -n1 "$S/status" | cut -c1-100). Resume from it; QC_BUILD_RESTART=1 starts it over on purpose" >&2; exit 5; fi
: > "$S/status"
st() { echo "$(date +%T) $*" | mask | tee -a "$S/status"; }; stop() { st "STOP: $*"; exit 1; }
N1=$(cluster_nodes 1); N2=$(cluster_nodes 2)
[ -n "$N1" ] && [ -n "$N2" ] || stop "the config needs nodes in cluster 1 AND cluster 2"
[ -n "$(cfg get cluster.second_cluster_ip)" ] || stop "cluster.second_cluster_ip is not set"
D=$(for n in $N1 $N2; do cfgn "$n" host; done | sort | uniq -d); [ -z "$D" ] || stop "two nodes share the node address $D (set unique host: values)"
[ "$(cfg get cluster.cluster_ip)" != "$(cfg get cluster.second_cluster_ip)" ] || stop "cluster_ip and second_cluster_ip are equal"
for n in $N1 $N2; do [ "$(node_state "$n")" = running ] || continue
	zpool_answers "$n" || stop "zpool does not answer on $n (report at once)"
	[ -z "$(pools_on "$n")" ] || stop "a pool is imported ($(pools_on "$n" | tr '\n' ' ')): export it with cluster-stopnode.sh first"; done
if [ -n "${DRYRUN:-}" ]; then st "DRYRUN: would log out iSCSI sessions, stop [$(echo $N1 $N2)], reset cluster 1 [$(echo $N1)] --single, reset cluster 2 [$(echo $N2)], cross-login the targets (nothing touched)"; exit 0; fi
HOLD=; for n in $N1 $N2; do [ "$(node_state "$n")" = running ] && node_exec "$n" 'pgrep -x iscsid' >/dev/null 2>&1 && { HOLD=$n; break; }; done
[ -z "$HOLD" ] || { st "iSCSI: graceful logout of all sessions from $HOLD (no pool is imported)"; node_exec "$HOLD" 'timeout 60 iscsiadm -m node -u' >/dev/null 2>&1; }
for n in $(for x in $N2 $N1; do [ "$x" != "$HOLD" ] && echo $x; done) $HOLD; do [ "$(node_state "$n")" = running ] && { st "stop $n"; "$QC_TOOLS/cluster-stopnode.sh" "$n" || stop "could not stop $n"; }; done   # the iscsid holder is stopped last
st "cluster 1: reset (single)"; "$QC_TOOLS/cluster-reset.sh" "${BUILD}a" --cluster 1 --single --no-disks > "$S/c1.log" 2>&1
tail -n1 "$QC_STATE/builds/build${BUILD}a/status" | grep -q DONE || stop "cluster 1 failed: $(tail -n1 "$QC_STATE/builds/build${BUILD}a/status")"
st "cluster 2: reset$([ $SINGLE = 1 ] && echo ' (single)')"; "$QC_TOOLS/cluster-reset.sh" "${BUILD}b" --cluster 2 --no-disks $([ $SINGLE = 1 ] && echo --single) > "$S/c2.log" 2>&1
tail -n1 "$QC_STATE/builds/build${BUILD}b/status" | grep -q DONE || stop "cluster 2 failed: $(tail -n1 "$QC_STATE/builds/build${BUILD}b/status")"
if [ "$(cfg get cluster.flavour)" = container ]; then
	ARGS=; for n in $N1 $N2; do [ "$(node_state "$n")" = running ] && ARGS="$ARGS $n:$(cfgn "$n" host)"; done
	st "iSCSI cross login (explicit nodes:$ARGS)"; "$QC_TOOLS/repl-iscsi-cross.sh" $ARGS >> "$S/status" 2>&1 || stop "repl-iscsi-cross.sh failed"
fi
st "DONE: cluster 1 = [$(echo $N1)] at $(cfg get cluster.cluster_ip), cluster 2 = [$(echo $N2)] at $(cfg get cluster.second_cluster_ip)"
