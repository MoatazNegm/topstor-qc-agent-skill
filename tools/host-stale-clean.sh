#!/bin/bash
# host-stale-clean.sh   CONTAINER FLAVOUR ONLY, on the docker host at the START of a build, after every node was stopped with
# cluster-stopnode.sh (adapted stalelooppclean.sh). Runs host-kernelclean.sh, deletes the stale LIO SCSI disks the host sees,
# detaches leftover loops of earlier tests (container_host.stale_loop_regex) and sets the export lists of the running container
# nodes to "none". Without it a fresh cluster listed 17 instead of 12 disks (old loops survived the build). Refuses with a pool imported.
. "$(dirname "$(readlink -f "$0")")/lib/node.sh"
say() { log "stale-clean: $*"; }
[ "$(cfg get cluster.flavour)" = container ] || { say "only for the container flavour"; exit 1; }
timeout 10 zpool list -H -o name >/dev/null 2>&1 || { say "STOP: zpool does not answer (report at once)"; exit 3; }
IMP=$(timeout 10 zpool list -H -o name 2>/dev/null | tr '\n' ' '); [ -n "${IMP// }" ] && { say "STOP: a pool is still imported: $IMP"; exit 2; }
"$QC_TOOLS/host-kernelclean.sh" 2>&1 | tail -5
for d in $(lsscsi 2>/dev/null | awk '/LIO-ORG/{print $NF}' | sed 's#/dev/##'); do
	[ -e "/sys/block/$d/device/delete" ] && echo 1 > "/sys/block/$d/device/delete" && say "deleted stale LIO disk $d"; done
RX=$(cfg get container_host.stale_loop_regex)
if [ -n "$RX" ]; then for l in $(losetup -nO NAME,BACK-FILE 2>/dev/null | awk -v rx="$RX" '$2 ~ rx {print $1}'); do
	losetup -d "$l" 2>/dev/null && say "detached stale loop $l"; done; fi
for n in $(cluster_nodes); do [ "$(node_type "$n")" = container ] && [ "$(node_state "$n")" = running ] && node_exec "$n" 'echo none > /root/loopdisks' && say "$n: export list set to none"; done
say "done; LIO disks left: $(lsscsi 2>/dev/null | grep -c LIO-ORG)"
