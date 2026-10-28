#!/bin/bash
# host-kernelclean.sh   CONTAINER FLAVOUR ONLY, run on the docker host that runs the node containers (adapted kernelclean.sh).
# The nodes share the host kernel, so earlier clusters leave LIO targets/backstores, iSCSI sessions and ZFS labels behind that a
# pair of wiped servers would not have. Removes them for the test loop disks matching container_host.test_disk_regex only.
# REFUSES while any pool is imported or zpool does not answer (the legacy "clear + export -f" of leftover pools is NOT done:
# never export/clear a SUSPENDED pool). Never run it while iSCSI sessions serve an imported pool.
. "$(dirname "$(readlink -f "$0")")/lib/node.sh"
say() { log "kernelclean: $*"; }
[ "$(cfg get cluster.flavour)" = container ] || { say "only for the container flavour"; exit 1; }
RX=$(cfg get container_host.test_disk_regex); [ -n "$RX" ] || { say "container_host.test_disk_regex is not set"; exit 1; }
timeout 10 zpool list -H -o name >/dev/null 2>&1 || { say "STOP: zpool does not answer (report at once)"; exit 3; }
IMP=$(timeout 10 zpool list -H -o name 2>/dev/null | tr '\n' ' ')
[ -n "${IMP// }" ] && { say "STOP: a pool is imported ($IMP): export it with cluster-stopnode.sh first"; exit 2; }
LOOPS=$(losetup -l --noheadings -O NAME,BACK-FILE | awk -v rx="$RX" '$2 ~ rx {print $1}')
LOOPRE=$(for l in $LOOPS; do basename "$l" | sed 's/^loop//'; done | tr '\n' '|' | sed 's/|$//')
[ -n "$LOOPRE" ] || { say "no test loops attached; nothing to do"; exit 0; }
HELPER=; for n in $(cluster_nodes); do [ "$(node_type "$n")" = container ] && [ "$(node_state "$n")" = running ] && { HELPER=$n; break; }; done
if [ -n "$HELPER" ]; then
	# 0. sessions to targets that no longer exist in LIO (they make the product believe a portal is logged in)
	node_exec "$HELPER" 'timeout 30 iscsiadm -m session' 2>/dev/null | awk '{print $3" "$4}' | while read -r portal iqn; do
		[ -d "/sys/kernel/config/target/iscsi/$iqn" ] && continue
		node_exec "$HELPER" "timeout 30 iscsiadm -m node -T $iqn -p ${portal%%,*} -u" >/dev/null 2>&1 && say "logged out stale session $iqn"; done
	# 1. LIO targets that export the test loops, then their backstores
	for t in /sys/kernel/config/target/iscsi/iqn.*; do [ -d "$t" ] || continue
		ls -l "$t"/tpgt_1/lun/*/ 2>/dev/null | grep -Eq "loop($LOOPRE)-" || continue
		node_exec "$HELPER" "timeout 60 targetcli /iscsi delete $(basename "$t")" >/dev/null 2>&1 && say "deleted target $(basename "$t")"; done
	for bs in $(node_exec "$HELPER" 'timeout 30 targetcli ls /backstores/block' 2>/dev/null | sed -n 's/.*o- \(loop[0-9][0-9]*-[a-z0-9]*\) .*/\1/p' | grep -E "^loop($LOOPRE)-"); do
		node_exec "$HELPER" "timeout 30 targetcli /backstores/block delete $bs" >/dev/null 2>&1 && say "deleted backstore $bs"; done
else say "no running container node: LIO cleanup skipped"; fi
# 2. empty disks for the next cluster: wipe the labels, drop the partition mappings
for l in $LOOPS; do
	for part in ${l}p1 ${l}p9; do [ -b "$part" ] && timeout 20 zpool labelclear -f "$part" >/dev/null 2>&1; done
	timeout 20 zpool labelclear -f "$l" >/dev/null 2>&1; wipefs -a -q "$l" >/dev/null 2>&1
	dd if=/dev/zero of="$l" bs=1M count=4 conv=notrunc status=none 2>/dev/null
	sz=$(blockdev --getsz "$l"); dd if=/dev/zero of="$l" bs=512 seek=$((sz-8192)) count=8192 conv=notrunc status=none 2>/dev/null
	partx -d "$l" >/dev/null 2>&1
done
say "done: test loops wiped: $(echo $LOOPS)"
