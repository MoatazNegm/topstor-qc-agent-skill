#!/bin/bash
# repl-iscsi-cross.sh <node>[:<ip>] ...   CONTAINER FLAVOUR, replication setups (adapted replisciscross.sh). The shared kernel has ONE
# iscsid (held by one node container), so the disks of the other cluster's nodes are never logged in by themselves. For each GIVEN
# node: give the iscsid holder an explicit ACL with the LUNs mapped READ-WRITE (a dynamic ACL maps them read-only: zpool create then
# fails with EROFS) and log in. Arguments are REQUIRED: never run it for nodes whose pool is imported (re-logging the pool owner's
# own target suspended its pool once). The ACL is lost when the node restarts: run it again then. OWN=<node> forces the holder.
. "$(dirname "$(readlink -f "$0")")/lib/node.sh"
. "$QC_TOOLS/lib/tstor.sh"
[ $# -gt 0 ] || die "give the node(s) explicitly, e.g. repl-iscsi-cross.sh node3 (never the default list)"
OWN=${OWN:-$(for c in $(cluster_nodes); do [ "$(node_type "$c")" = container ] && node_exec "$c" 'pgrep -x iscsid' >/dev/null 2>&1 && echo "$c" && break; done)}
[ -n "$OWN" ] || die "no node holds iscsid"
INI=$(node_exec "$OWN" 'cat /etc/iscsi/initiatorname.iscsi' | sed 's/InitiatorName=//' | tr -d '\r\n')
for p in "$@"; do n=${p%%:*}; ip=${p#*:}; [ "$ip" = "$p" ] && ip=$(cfgn "$n" host)
	[ "$(node_state "$n")" = running ] || { echo "$n not running, skipped"; continue; }
	# enforced guard: re-logging the target of a node that owns an imported pool suspends that pool
	[ -z "$(pools_owned "$n")" ] || die "REFUSED: $n owns an imported pool ($(pools_owned "$n" | tr '\n' ' ')): never run this for the owner of an imported pool"
	hn=$(node_exec "$n" hostname | tr -d '\r\n'); iqn=iqn.2016-03.com.$hn:t1
	node_exec "$OWN" "iscsiadm -m discovery --portal $ip:3266 --type sendtargets" >/dev/null 2>&1
	node_exec "$OWN" "iscsiadm -m node --targetname $iqn --portal $ip:3266 -u" >/dev/null 2>&1
	node_exec "$n" "targetcli /iscsi/$iqn/tpg1/acls delete $INI" >/dev/null 2>&1
	node_exec "$n" "targetcli /iscsi/$iqn/tpg1/acls create $INI" 2>&1 | grep -v setlocale | tail -1
	for l in $(node_exec "$n" "ls /sys/kernel/config/target/iscsi/$iqn/tpgt_1/lun" | sed 's/lun_//'); do
		node_exec "$n" "targetcli /iscsi/$iqn/tpg1/acls/$INI create mapped_lun=$l tpg_lun_or_backstore=$l write_protect=false" 2>&1 | grep -v setlocale | tail -1; done
	echo "$n $ip target: $iqn"
	node_exec "$OWN" "iscsiadm -m node --targetname $iqn --portal $ip:3266 -l" 2>&1 | grep -v setlocale | tail -1
done
node_exec "$OWN" 'iscsiadm -m session'
