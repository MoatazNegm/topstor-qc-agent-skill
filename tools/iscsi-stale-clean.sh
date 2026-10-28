#!/bin/bash
# iscsi-stale-clean.sh [node...]   delete iSCSI node records (and, container flavour, LUN-less LIO targets) of targets that are not a
# current node of this cluster: logins to them stall the product's discovery/disk refresh for minutes (adapted cleaniscsistale.sh).
# Only records of foreign targets are touched; run it only when every configured node is up and no pool is imported (e.g. right after a --no-disks build); at the build start (nodes stopped) use host-stale-clean.sh.
. "$(dirname "$(readlink -f "$0")")/lib/node.sh"
. "$QC_TOOLS/lib/tstor.sh"
NS=${@:-$(cluster_nodes)}; names=""
# enforced guard: never while a pool is imported (a stale-looking record may be the session a pool is running on)
for c in $NS; do [ "$(node_state "$c")" = running ] || continue; [ -z "$(pools_on "$c")" ] || die "REFUSED: pool(s) imported ($(pools_on "$c" | tr '\n' ' ')): run this only with every node up and no pool imported"; done
# K-07: "current" targets = EVERY configured cluster node (also stopped ones and nodes not given as arguments); the host name is read from the
# running node. A configured node that is not running = refuse (L-04: the name is per build, never the alias; nothing may be deleted blind).
for c in $(cluster_nodes); do h=; [ "$(node_state "$c")" = running ] && h=$(node_exec "$c" hostname 2>/dev/null | tr -d '\r\n')
	[ -n "$h" ] || die "REFUSED: cannot read the host name of configured node $c (not running): start every configured node first, or use host-stale-clean.sh at the build start (nodes stopped)"
	names="$names iqn.2016-03.com.$h:t1"; done
c1=$(echo $NS | cut -d' ' -f1)
if [ "$(cfg get cluster.flavour)" = container ]; then
	node_exec "$c1" 'timeout 60 targetcli ls /iscsi 2>/dev/null' | grep -o 'iqn.2016-03.com.[a-z0-9]*:t1' | sort -u | while read -r iqn; do
		echo " $names " | grep -q " $iqn " && continue
		node_exec "$c1" "timeout 60 targetcli ls /iscsi/$iqn/tpg1/luns" 2>/dev/null | grep -q 'lun[0-9]' && { echo "foreign target $iqn still has LUNs: left alone"; continue; }
		echo "stale LIO target $iqn -> delete"; node_exec "$c1" "timeout 60 targetcli /iscsi delete $iqn; timeout 30 targetcli saveconfig >/dev/null 2>&1" 2>&1 | grep -v setlocale
	done
fi
for c in $NS; do node_exec "$c" 'iscsiadm -m node' 2>/dev/null | while read -r rec iqn; do
	echo " $names " | grep -q " $iqn " && continue; portal=${rec%%,*}
	echo "$c: stale record $iqn $portal -> delete"; node_exec "$c" "iscsiadm -m node -T $iqn -p $portal -u >/dev/null 2>&1; iscsiadm -m node -T $iqn -p $portal -o delete" 2>&1 | grep -v setlocale
done; done
