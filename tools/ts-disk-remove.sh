#!/bin/bash
# ts-disk-remove.sh <loopN>   Detach one test loop disk of a CONTAINER-flavour lab (reverse of ts-disk-add.sh). Refused (rc 5) while any pool is imported, rc 3 if zpool does not answer.
# Other flavours: NEEDS-HUMAN (exit 10).
. "$(dirname "$(readlink -f "$0")")/lib/node.sh"
. "$QC_TOOLS/lib/tstor.sh"
L=${1:?loopN}; case $L in loop[0-9]*) ;; *) die "give a name like loop12";; esac
LF=$(cfg get container_host.loopdisks_files ""|tr ',' ' ')
for n in $(cluster_nodes); do [ "$(node_type "$n")" = container ] || { echo "NEEDS-HUMAN: remove the disk in the hypervisor or hardware" >&2; exit 10; }; done
require_local_kernel
# K-06: a hung zpool or a silent node must never read as "disk not used": every running node must answer zpool, at least one must run
RUN=0
for n in $(cluster_nodes); do [ "$(node_state "$n")" = running ] || continue; RUN=$((RUN+1))
	zpool_answers "$n" || { echo "zpool does not answer on $n (rc 124? possible SUSPENDED pool): nothing detached, report at once" >&2; exit 3; }
	# L-02: the loops are exported over LIO/iSCSI, so zpool status never names /dev/loopN: the use cannot be proven from the pool listing.
	# Rule instead (as the real stale-loop cleanup): refuse while ANY pool is imported anywhere (container flavour: the kernel is shared).
	[ -z "$(pools_on "$n")" ] || { echo "REFUSED: pool(s) imported ($(pools_on "$n" | tr '\n' ' ')): a loop disk may back a LUN of a pool; export/destroy the pools first, nothing detached" >&2; exit 5; }
	done
[ $RUN -gt 0 ] || die "no cluster node is running: cannot prove that $L is unused"
for x in $LF; do run sed -i "/^$L\$/d" "$x"; done
run losetup -d "/dev/$L"
