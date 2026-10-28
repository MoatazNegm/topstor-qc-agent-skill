#!/bin/bash
# ts-disk-remove.sh <loopN>   Detach one test loop disk of a CONTAINER-flavour lab (reverse of ts-disk-add.sh). The pool must not use it.
# Other flavours: NEEDS-HUMAN (exit 10).
. "$(dirname "$(readlink -f "$0")")/lib/node.sh"
L=${1:?loopN}; case $L in loop[0-9]*) ;; *) die "give a name like loop12";; esac
LF=$(cfg get container_host.loopdisks_files ""|tr ',' ' ')
for n in $(cluster_nodes); do [ "$(node_type "$n")" = container ] || { echo "NEEDS-HUMAN: remove the disk in the hypervisor or hardware" >&2; exit 10; }; done
require_local_kernel
for n in $(cluster_nodes); do p=$(node_exec "$n" "timeout 20 zpool status -P 2>/dev/null | grep -c $L"); [ "${p:-0}" = 0 ] || die "$L is used by a pool on $n"; done
for x in $LF; do run sed -i "/^$L\$/d" "$x"; done
run losetup -d "/dev/$L"
