#!/bin/bash
# cluster-refreshcversion.sh [node...]   re-publish cversion/<host> from the code really checked out on each node (the product's
# getcversion.sh with the arguments of its last call). Run after EVERY build or code deploy: a stale key makes a returning node
# fall back to the old branch. Default: all running cluster nodes.
. "$(dirname "$(readlink -f "$0")")/lib/node.sh"
TP=$(cfg get repos.node_paths.topstor /TopStor)
BAD=0
for n in ${@:-$(cluster_nodes)}; do [ "$(node_state "$n")" = running ] || { echo "$n: not running, skipped"; continue; }
	o=$(node_exec "$n" "$TP/getcversion.sh \$(cat /root/getcversion)" 2>&1); rc=$?
	o=$(echo "$o" | grep -v -e setlocale -e '^$' | tail -2 | tr '\n' ' ')
	echo "$n: $o"; { [ $rc = 0 ] && [ -n "$o" ]; } || { echo "ERROR: getcversion failed on $n (rc $rc): cversion not refreshed" >&2; BAD=1; }; done
exit $BAD
