#!/bin/bash
# ts-disk-remove.sh <loopN>   Detach one test loop disk of a CONTAINER-flavour lab (reverse of ts-disk-add.sh). The pool must not use it.
# Other flavours: NEEDS-HUMAN (exit 10).
. "$(dirname "$(readlink -f "$0")")/lib/node.sh"
L=${1:?loopN}; case $L in loop[0-9]*) ;; *) die "give a name like loop12";; esac
LF=$(cfg get container_host.loopdisks_files ""|tr ',' ' ')
for n in $(cluster_nodes); do [ "$(node_type "$n")" = container ] || { echo "NEEDS-HUMAN: remove the disk in the hypervisor or hardware" >&2; exit 10; }; done
require_local_kernel
# K-06: a hung zpool or a silent node must never read as "disk not used": every running node must answer zpool, at least one must run
RUN=0
for n in $(cluster_nodes); do [ "$(node_state "$n")" = running ] || continue; RUN=$((RUN+1))
	zpool_answers "$n" || { echo "zpool does not answer on $n (rc 124? possible SUSPENDED pool): nothing detached, report at once" >&2; exit 3; }
	node_exec "$n" "timeout 20 zpool status -P" > "$QC_STATE/tmp/zs.$$" 2>&1 || { rm -f "$QC_STATE/tmp/zs.$$"; echo "zpool status failed on $n: nothing detached" >&2; exit 3; }
	grep -qE "/dev/$L(p?[0-9]+)?([[:space:]]|\$)" "$QC_STATE/tmp/zs.$$" && { rm -f "$QC_STATE/tmp/zs.$$"; die "$L is used by a pool on $n"; }
	rm -f "$QC_STATE/tmp/zs.$$"; done
[ $RUN -gt 0 ] || die "no cluster node is running: cannot prove that $L is unused"
for x in $LF; do run sed -i "/^$L\$/d" "$x"; done
run losetup -d "/dev/$L"
