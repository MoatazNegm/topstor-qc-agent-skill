#!/bin/bash
# cluster-insync.sh [cluster ip] [max seconds]   poll info/notification until isinsync is green (the UI's "Cluster in Sync" sign);
# prints the value every 10 s. rc 0 = green. Default: cluster.cluster_ip, cluster.isinsync_timeout.
. "$(dirname "$(readlink -f "$0")")/lib/tstor.sh"
ip=${1:-$(cfg get cluster.cluster_ip)}; M=${2:-$(cfg get cluster.isinsync_timeout 300)}; t=0
while [ "$t" -le "$M" ]; do v=$(ts_isinsync "$ip"); log "${t}s isinsync=$v"; ts_green "$v" && { echo "GREEN after ${t}s"; exit 0; }; sleep 10; t=$((t+10)); done
echo "NOT green after ${M}s"; exit 1
