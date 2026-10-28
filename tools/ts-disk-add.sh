#!/bin/bash
# ts-disk-add.sh <count> [size GB, default 1]      Add test disks to a CONTAINER-flavour lab (adapted hotadd.sh).
# Per disk: a sparse backing file in container_host.disk_dir, a loop device (new node made when missing), the name appended to every file in
# container_host.loopdisks_files, the device node created inside every container node. Physical / VirtualBox labs: add the disk by hand
# (hypervisor or hardware), exit 10 = NEEDS-HUMAN. --wait <seconds> (last argument): poll ts-pool.sh disks until the product lists more disks. Needs config keys container_host.disk_dir and container_host.loopdisks_files.
. "$(dirname "$(readlink -f "$0")")/lib/node.sh"
WAIT=0; if [ "${*: -2:1}" = --wait ]; then WAIT=${*: -1}; set -- "${@:1:$#-2}"; fi
N=${1:?count}; SZ=${2:-1}; DD=$(cfg get container_host.disk_dir ""); LF=$(cfg get container_host.loopdisks_files ""|tr ',' ' ')
for n in $(cluster_nodes); do [ "$(node_type "$n")" = container ] || { echo "NEEDS-HUMAN: node $n is not a container node: add the disk in the hypervisor or hardware" >&2; exit 10; }; done
[ -n "$DD" ] && [ -n "$LF" ] || die "set container_host.disk_dir and container_host.loopdisks_files in the config"
require_local_kernel
cnt() { "$QC_TOOLS/ts-pool.sh" disks 2>/dev/null | sed -n 's/^DISKS=\([0-9]*\).*/\1/p'; }
[ "$WAIT" -gt 0 ] && [ -z "${DRYRUN:-}" ] && N0=$(cnt)
for i in $(seq 1 "$N"); do
	run mkdir -p "$DD"; f="$DD/qcdisk-$(date +%s)-$i.img"; run truncate -s "${SZ}G" "$f"
	if [ -n "${DRYRUN:-}" ]; then echo "DRYRUN: losetup -f --show $f; append to $LF; mknod in the containers"; continue; fi
	free=$(losetup -f); [ -b "$free" ] || mknod "$free" b 7 "${free#/dev/loop}"
	dev=$(losetup -f --show "$f"); l=${dev#/dev/}; for x in $LF; do echo "$l" >> "$x"; done
	maj=7; min=${l#loop}
	for n in $(cluster_nodes); do node_exec "$n" "[ -b $dev ] || mknod $dev b $maj $min" || log "WARN: node $n has no $dev"; done
	log "added $dev ($f, ${SZ}G)"
done
if [ "$WAIT" -gt 0 ] && [ -z "${DRYRUN:-}" ]; then t=0; c=
	while [ $t -lt "$WAIT" ]; do c=$(cnt); [ -n "$c" ] && [ -n "${N0:-}" ] && [ "$c" -ge $((N0+N)) ] && { log "product lists $c disks (was $N0)"; exit 0; }; sleep 5; t=$((t+5)); done
	log "WARN: product lists ${c:-?} disks after ${WAIT}s, expected $((${N0:-0}+N))"; exit 1; fi
