#!/bin/bash
# ts-pool.sh [--cluster N] <list|new <redundancy> <useable> <cache true|false>|del <pool>|cachespare-add <disk>...|disks>
# Pool calls of the product API (the same calls the UI makes; adapted poollib.sh + diskapi.sh). list = pools known to the API
# (name, host, status, raids); disks = the disk summary the UI shows (count, bad names, per host). new answers the echo + HTTP code.
# The admin user and password come from the config (password FILE); nothing is printed that is a secret. DRYRUN=1 sends no write.
. "$(dirname "$(readlink -f "$0")")/lib/tstor.sh"
CL=1; [ "${1:-}" = --cluster ] && { CL=$2; shift 2; }
CIP=$([ "$CL" = 2 ] && cfg get cluster.second_cluster_ip || cfg get cluster.cluster_ip)
C=${1:?list|new|del|cachespare-add|disks}; shift
dgs() { ts_api "$CIP" GET pools/dgsinfo; }
case $C in
list) dgs | python3 -I -c 'import sys,json
d=json.load(sys.stdin)
for n,p in d.get("pools",{}).items():
    if n!="pree": print(n,"host=%s status=%s raids=%s"%(p.get("host"),p.get("status"),",".join(p.get("raids",[]))))';;
disks) dgs | python3 -I -c 'import sys,json
d=json.load(sys.stdin).get("disks",{}); h={}
bad=[n for n in d if not n.startswith("scsi-3")]
for n,k in d.items(): h.setdefault(k.get("host","?"),[]).append("%s(%s,%sG)"%(k.get("devname"),n[-6:],k.get("size")))
print("DISKS=%d BADNAMES=%d HOSTS=%s"%(len(d),len(bad),",".join(sorted(h))))
for x in sorted(h): print("  %s: %d disks: %s"%(x,len(h[x])," ".join(sorted(h[x]))))';;
new) ts_api "$CIP" POST pools/newpool -w ' HTTP%{http_code}' --data-urlencode "redundancy=${1:?redundancy}" --data-urlencode "useable=${2:?useable}" --data-urlencode "cache_bool=${3:?cache true|false}" | tr -d '\n' | cut -c1-500; echo;;
del) ts_api "$CIP" POST pools/delpool --data-urlencode "pool=${1:?pool}" | tr -d '\n ' | cut -c1-200; echo;;
cachespare-add) q=(); for x in "$@"; do q+=(--data-urlencode "cache_disks[]=$x"); done; [ ${#q[@]} -gt 0 ] || die "give the disk names"
	ts_api "$CIP" POST pools/cachespares "${q[@]}" | tr -d '\n' | cut -c1-200; echo;;
*) die "unknown command $C";;
esac
