#!/bin/bash
# iscsi-stale-clean.sh [node...]   delete iSCSI node records (and, container flavour, LUN-less LIO targets) of targets that are not a
# current node of this cluster: logins to them stall the product's discovery/disk refresh for minutes (adapted cleaniscsistale.sh).
# Only records of foreign targets are touched; run it between builds, never while a pool uses a session of those targets.
. "$(dirname "$(readlink -f "$0")")/lib/node.sh"
. "$QC_TOOLS/lib/tstor.sh"
NS=${@:-$(cluster_nodes)}; names=""
# enforced guard: never while a pool is imported (a stale-looking record may be the session a pool is running on)
for c in $NS; do [ "$(node_state "$c")" = running ] || continue; [ -z "$(pools_on "$c")" ] || die "REFUSED: pool(s) imported ($(pools_on "$c" | tr '\n' ' ')): run this between builds, with no pool imported"; done
# K-07: "current" targets = EVERY configured cluster node (also stopped ones and nodes not given as arguments); the host name is read from the
# running node, else from the config (hostname:, or alias:). A configured node whose name cannot be found = refuse (nothing may be deleted blind).
for c in $(cluster_nodes); do h=; [ "$(node_state "$c")" = running ] && h=$(node_exec "$c" hostname 2>/dev/null | tr -d '\r\n')
	[ -n "$h" ] || h=$(cfgn "$c" hostname); [ -n "$h" ] || h=$(cfgn "$c" alias)
	[ -n "$h" ] || die "REFUSED: cannot find the host name of configured node $c (not running, no hostname:/alias: in the config); start it or add hostname: to its config entry"
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
